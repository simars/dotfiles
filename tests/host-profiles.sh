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
# Makes its own chezmoi config from .chezmoi.toml.tmpl (below). Runs under bash 3.2, the macOS /bin/bash.
#
# SC2016 is off for this file: single-quoted `$` here is deliberate, either a grep pattern for a literal `$VAR` in a
# rendered file or code for a child shell (`bash -c`, `zsh -c`, stub scripts) that must expand it there, not here.
# shellcheck disable=SC2016

set -u

base=""
if [[ "${1:-}" == "--base" ]]; then
    base="${2:?--base needs a git ref}"
fi

cd "$(dirname "$0")/.." || exit 1
repo="$PWD"

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

# Every chezmoi call here reads a config made just now from .chezmoi.toml.tmpl with CI's answers, and this checkout as
# the source: never this machine's own config or source directory, so a local run sees what CI sees. A later --config
# or --source on a call wins.
suite_config="$work/chezmoi.toml"
printf '' > "$work/blank.toml"
if ! command chezmoi --config "$work/blank.toml" --source "$repo" execute-template --init --no-tty \
    --promptString "What is your Git email address=ci-bot@example.com" \
    --promptString "What is your Git full name=CI Runner" \
    --promptString "Work email for your work GitHub orgs (none if this machine has no work repositories)=work@example.com" \
    --promptString "Work GitHub orgs (separate with commas)=example-org, other-org" \
    "$(cat "$repo/.chezmoi.toml.tmpl")" < /dev/null > "$suite_config"; then
    echo "FAIL .chezmoi.toml.tmpl does not render: $(cat "$suite_config")"
    exit 1
fi
chezmoi() { command chezmoi --config "$suite_config" --source "$repo" "$@"; }

# Every host renders the whole tree with that fresh config: a template reading a key the config no longer writes
# fails here, not on a new machine.
fresh_render_failures() { # prints "HOST: first error line; " for each host that fails
    local host err
    for host in $hosts; do
        if ! err="$(chezmoi --destination "$work/dest-$host" --override-data "$(host_data "$host")" archive --output /dev/null 2>&1 > /dev/null)"; then
            printf '%s: %s; ' "$host" "$(printf '%s\n' "$err" | head -1)"
        fi
    done
}
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

# Terminal checks: on_tty runs a command with stdin, stdout and stderr on a pseudo-terminal (script(1)) and prints
# its output with the carriage returns removed. util-linux script takes the command as one string (-c); BSD/macOS
# script takes it as arguments after the typescript file.
on_tty() { # on_tty CMD...
    local words
    if script --version 2> /dev/null | grep -q util-linux; then
        words="$(printf ' %q' "$@")"
        SHELL=/bin/bash script -qec "${words# }" /dev/null < /dev/null | tr -d '\r'
    else
        # BSD script writes the EOF character to the pty when stdin ends; the tty echoes it as ^D plus two
        # backspaces, possibly after the child's first output, so strip every ^D, not only a leading one.
        script -q /dev/null "$@" < /dev/null | tr -d '\r\b' | sed 's/\^D//g'
    fi
}
tty_ok=no
probe="$(on_tty sh -c '[ -t 2 ] && echo yes' 2> /dev/null)"
if [[ "$probe" == "yes" ]]; then
    tty_ok=yes
else
    echo "SKIP terminal checks: the probe printed [$(printf '%s' "$probe" | od -c | head -2 | tr -s ' ' | tr '\n' ';')], not [yes]"
fi
tty_check() { # tty_check NAME EXPECTED DIR CMD...: check, with CMD run in DIR on a terminal; skipped without one
    local name="$1" expected="$2" dir="$3"
    shift 3
    [[ "$tty_ok" == yes ]] || return 0
    check "$name" "$expected" "$(cd "$dir" && on_tty "$@")"
}

manages() { # manages HOST TARGET
    if grep -qxF -- "$2" "$work/$1.managed"; then echo yes; else echo no; fi
}

render() { # render HOST FILE [SOURCE_DIR]
    local source="${3:-.}"
    chezmoi --source "$source" --override-data "$(host_data "$1")" execute-template < "$source/$2"
}

check "every host renders with a fresh config" "" "$(fresh_render_failures)"

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
check "omarchy package script installs AUR with omarchy pkg aur add" 1 "$(grep -c '^install_missing "pkg aur add" "lunarvim-git" "waveterm-bin"$' "$work/omarchy.packages")"
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
for line in 'window_title = "{hostname}: {workspace}"' 'panel_bg = "reset"' 'surface_dim = "black"' 'prefix = ["ctrl+b", "ctrl+space"]'; do
    check "omarchy herdr has $line" 1 "$(grep -cxF -- "$line" "$work/omarchy.herdr")"
done
check "darwin herdr has no Omarchy chrome" 0 "$(grep -cE 'window_title|panel_bg|^\[theme' "$work/darwin.herdr")"
# Omarchy's [ui] holds exactly its stock [ui] settings (order, comments and blank lines aside), except confirm_close:
# every host asks before closing (stock false).
check "omarchy herdr [ui] is Omarchy's stock [ui]" "" "$(diff <(sed -n '/^\[ui\]/,$p' docs/omarchy-stock/herdr.toml | grep -vE '^(#|$|confirm_close)' | sort) <(sed -n '/^\[ui\]/,$p' "$work/omarchy.herdr" | grep -vE '^(#|$|confirm_close)' | sort))"
for host in darwin omarchy; do
    check "$host herdr asks before every close" 1 "$(grep -cx 'confirm_close = true' "$work/$host.herdr")"
done
check "darwin herdr keeps gaps" 1 "$(grep -cxF 'pane_gaps = true' "$work/darwin.herdr")"
for host in darwin omarchy; do
    check "$host herdr takes Ctrl-b and Ctrl-Space as prefixes, like tmux" 1 "$(grep -cxF 'prefix = ["ctrl+b", "ctrl+space"]' "$work/$host.herdr")"
    check "$host herdr has tmux's ( ) for previous/next workspace and f for find" "1 1 1" \
        "$(grep -c '^previous_workspace = \["prefix+(",' "$work/$host.herdr") $(grep -c '^next_workspace = \["prefix+)",' "$work/$host.herdr") $(grep -c '^goto = .*"prefix+f"' "$work/$host.herdr")"
done
check "requirement check names a stale Herdr server" 1 "$(render omarchy run_after_99_assert_requirements.sh.tmpl | grep -c 'server_binary_stale')"
# tmux's layout keys after the prefix run herdr-layout: Space, Alt+1..7, Ctrl+o, Alt+o.
for host in darwin omarchy; do
    check "$host herdr: tmux's layout and rotate keys run herdr-layout" \
        "next even-horizontal even-vertical main-horizontal main-vertical tiled main-horizontal-mirrored main-vertical-mirrored rotate-up rotate-down" \
        "$(for k in space alt+1 alt+2 alt+3 alt+4 alt+5 alt+6 alt+7 ctrl+o alt+o; do grep -A3 -xF "key = \"prefix+$k\"" "$work/$host.herdr" | sed -n 's|^command = .*/\.local/bin/herdr-layout" \([a-z-]*\) .*|\1|p'; done | xargs)"
done
# Herdr has no equalize: prefix Shift+e runs herdr-equalize (tmux's E, Ghostty's equalize_splits), on every host.
for host in darwin omarchy; do
    check "$host herdr: prefix Shift+e runs herdr-equalize" 1 \
        "$(grep -A3 -xF 'key = "prefix+shift+e"' "$work/$host.herdr" | grep -c '^command = .*/\.local/bin/herdr-equalize')"
done
# tmux's join-pane: prefix Shift+j picks another tab and moves the pane there (tmux J, Herdr through herdr-join).
for host in darwin omarchy; do
    check "$host herdr: prefix Shift+j opens herdr-join in a popup" "type = \"popup\" 1" \
        "$(grep -A3 -xF 'key = "prefix+shift+j"' "$work/$host.herdr" | grep '^type') $(grep -A3 -xF 'key = "prefix+shift+j"' "$work/$host.herdr" | grep -c '^command = .*/\.local/bin/herdr-join" "$HERDR_ACTIVE_PANE_ID"')"
done
check "tmux: prefix J picks a window and joins the pane to it, on the right" 1 \
    "$(grep -cxF 'bind -N "Move pane into another window" J choose-tree -Zw "join-pane -h -t '"'%%'"'"' dot_config/tmux/tmux.conf)"
if command -v jq > /dev/null 2>&1; then
    # A stub herdr: `pane layout` prints layout.<n>.json, `pane resize` logs its arguments and, unless the state dir
    # has a file named stuck, moves on to the next layout.
    eq="$work/herdr-eq"; mkdir -p "$eq"
    cat > "$eq/herdr" <<'STUB'
#!/usr/bin/env bash
d=$(dirname "$0"); n=$(cat "$d/n")
case "$1 $2" in
    "pane layout") printf '{"result":{"layout":%s}}\n' "$(cat "$d/layout.$n.json")" ;;
    "pane resize") shift 2; echo "$*" >> "$d/calls"; [ -e "$d/stuck" ] || echo $((n + 1)) > "$d/n"; echo '{}' ;;
    *) exit 2 ;;
esac
STUB
    chmod +x "$eq/herdr"
    eq_run() { echo 0 > "$eq/n"; : > "$eq/calls"; HERDR_BIN_PATH="$eq/herdr" bash dot_local/bin/executable_herdr-equalize p1 2> "$eq/err"; echo "exit $?"; }
    pane() { printf '{"pane_id":"%s","rect":{"x":%s,"y":0,"width":%s,"height":40}}' "$@"; }
    # Three columns at 60/30/30 (two nested right splits at 0.5): the root split is fixed through p1, by -1/6.
    printf '{"panes":[%s,%s,%s],"splits":[{"id":"split_0_root","direction":"right","ratio":0.5,"rect":{"x":0,"y":0,"width":120,"height":40}},{"id":"split_1_1","direction":"right","ratio":0.5,"rect":{"x":60,"y":0,"width":60,"height":40}}]}' \
        "$(pane p1 0 60)" "$(pane p2 60 30)" "$(pane p3 90 30)" > "$eq/layout.0.json"
    printf '{"panes":[%s,%s,%s],"splits":[{"id":"split_0_root","direction":"right","ratio":0.33333334,"rect":{"x":0,"y":0,"width":120,"height":40}},{"id":"split_1_1","direction":"right","ratio":0.5,"rect":{"x":40,"y":0,"width":80,"height":40}}]}' \
        "$(pane p1 0 40)" "$(pane p2 40 40)" "$(pane p3 80 40)" > "$eq/layout.1.json"
    rm -f "$eq/stuck"
    check "herdr-equalize: evens three columns with one resize" "exit 0" "$(eq_run)"
    check "herdr-equalize: shrinks the root split through the pane after it, by a sixth" "1 --pane p2 --direction left --amount 0.1666" \
        "$(wc -l < "$eq/calls" | tr -d ' ') $(cut -c1-42 "$eq/calls")"
    touch "$eq/stuck"
    check "herdr-equalize: a split that will not move fails, no loop" "exit 1 1 1" \
        "$(eq_run) $(wc -l < "$eq/calls" | tr -d ' ') $(grep -c 'stayed at' "$eq/err")"
    rm -f "$eq/stuck"
    # A|(B|C) at 1/3 and 0.6: the inner split must shrink. Herdr moves the split at the named edge of the pane, so the
    # pane after the boundary (p3) moves left; p2 moving left would move the root split instead.
    printf '{"panes":[%s,%s,%s],"splits":[{"id":"split_0_root","direction":"right","ratio":0.33333334,"rect":{"x":0,"y":0,"width":120,"height":40}},{"id":"split_1_1","direction":"right","ratio":0.6,"rect":{"x":40,"y":0,"width":80,"height":40}}]}' \
        "$(pane p1 0 40)" "$(pane p2 40 48)" "$(pane p3 88 32)" > "$eq/layout.0.json"
    check "herdr-equalize: a shrinking inner split moves through the pane after it" "exit 0 --pane p3 --direction left" \
        "$(eq_run) $(cut -c1-26 "$eq/calls")"
    # Herdr moves a ratio at most 0.5 per call: 0.9 to 1/3 goes in steps, and stops when the ratio arrives.
    printf '{"panes":[%s,%s,%s],"splits":[{"id":"split_0_root","direction":"right","ratio":0.9,"rect":{"x":0,"y":0,"width":120,"height":40}},{"id":"split_1_1","direction":"right","ratio":0.5,"rect":{"x":108,"y":0,"width":12,"height":40}}]}' \
        "$(pane p1 0 108)" "$(pane p2 108 6)" "$(pane p3 114 6)" > "$eq/layout.0.json"
    printf '{"panes":[%s,%s,%s],"splits":[{"id":"split_0_root","direction":"right","ratio":0.45,"rect":{"x":0,"y":0,"width":120,"height":40}},{"id":"split_1_1","direction":"right","ratio":0.5,"rect":{"x":54,"y":0,"width":66,"height":40}}]}' \
        "$(pane p1 0 54)" "$(pane p2 54 33)" "$(pane p3 87 33)" > "$eq/layout.1.json"
    printf '{"panes":[%s,%s,%s],"splits":[{"id":"split_0_root","direction":"right","ratio":0.33333334,"rect":{"x":0,"y":0,"width":120,"height":40}},{"id":"split_1_1","direction":"right","ratio":0.5,"rect":{"x":40,"y":0,"width":80,"height":40}}]}' \
        "$(pane p1 0 40)" "$(pane p2 40 40)" "$(pane p3 80 40)" > "$eq/layout.2.json"
    check "herdr-equalize: a big change goes in steps of at most 0.45" "exit 0 2 0.45" \
        "$(eq_run) $(wc -l < "$eq/calls" | tr -d ' ') $(head -1 "$eq/calls" | awk '{print $NF}')"
    rm -f "$eq/stuck"
    printf '{"panes":[%s],"splits":[]}' "$(pane p1 0 120)" > "$eq/layout.0.json"
    check "herdr-equalize: one pane, nothing to do" "exit 0 0" "$(eq_run) $(wc -l < "$eq/calls" | tr -d ' ')"
    # herdr-layout: tmux's preset layouts, next-layout and rotate-window. The stub serves layout.json, logs the rest, and
    # answers a move with the moved pane's id and, for --new-tab, the temporary tab w1:t9.
    lay="$work/herdr-lay"; mkdir -p "$lay"
    cat > "$lay/herdr" <<'STUB'
#!/usr/bin/env bash
d=$(dirname "$0")
[ "$1" = pane ] || exit 2
shift
case "$1" in
    layout) printf '{"result":{"layout":%s}}\n' "$(cat "$d/layout.json")" ;;
    move) echo "$*" >> "$d/calls"; [ -e "$d/fail-move" ] && [ "$(wc -l < "$d/calls")" -ge "$(cat "$d/fail-move")" ] && exit 1
          printf '{"result":{"move_result":{"pane":{"pane_id":"%s"},"created_tab":{"tab_id":"w1:t9"}}}}\n' "$2" ;;
    swap | zoom) echo "$*" >> "$d/calls"; echo '{}' ;;
    *) exit 2 ;;
esac
STUB
    chmod +x "$lay/herdr"
    lay_set() { # lay_set WIDTH FOCUSED ZOOMED PANE...
        local w=$1 f=$2 z=$3; shift 3
        jq -nc --argjson w "$w" --arg f "$f" --argjson z "$z" '$ARGS.positional as $p
            | {tab_id: "w1:t1", focused_pane_id: $f, zoomed: $z, area: {x: 0, y: 0, width: $w, height: 48},
               panes: [$p[] | {pane_id: ., rect: {x: 0, y: 0, width: 1, height: 1}}], splits: []}' --args "$@" > "$lay/layout.json"
    }
    lay_run() { : > "$lay/calls"; HERDR_BIN_PATH="$lay/herdr" XDG_STATE_HOME="$lay/state" bash dot_local/bin/executable_herdr-layout "$@" p1 2> "$lay/err"; echo "exit $?"; }
    lay_calls() { paste -sd'|' "$lay/calls"; }
    rm -rf "$lay/state" "$lay/fail-move"
    lay_set 160 p1 false p1 p2 p3
    # Herdr focuses a swap's source pane; tmux keeps focus on the place, so the pane rotated into it gets focus: a pair
    # of swaps with that pane as source puts the panes back and focuses it.
    check "herdr-layout rotate-up: each pane one place back, the first goes last, focus stays on the place (tmux C-o)" \
        "exit 0 swap --source-pane p1 --target-pane p2|swap --source-pane p1 --target-pane p3|swap --source-pane p2 --target-pane p3|swap --source-pane p2 --target-pane p3" "$(lay_run rotate-up) $(lay_calls)"
    rm -rf "$lay/state"; lay_set 160 p2 false p1 p2 p3
    check "herdr-layout rotate-up: focus goes to the pane rotated into the focused place" \
        "swap --source-pane p3 --target-pane p2|swap --source-pane p3 --target-pane p2" "$(lay_run rotate-up >/dev/null; sed -n '3,4p' "$lay/calls" | paste -sd'|' -)"
    lay_set 160 p1 false p1 p2 p3
    rm -rf "$lay/state"
    check "herdr-layout rotate-down: the last pane comes first, already focused (tmux M-o)" \
        "exit 0 swap --source-pane p3 --target-pane p2|swap --source-pane p3 --target-pane p1" "$(lay_run rotate-down) $(lay_calls)"
    rm -rf "$lay/state"
    check "herdr-layout even-horizontal: out to a temporary tab, back side by side, equal" \
        "exit 0 move p2 --new-tab --no-focus|move p3 --tab w1:t9 --split right --target-pane p2 --no-focus|move p2 --tab w1:t1 --split right --target-pane p1 --ratio 0.3333 --no-focus|move p3 --tab w1:t1 --split right --target-pane p2 --ratio 0.5000 --no-focus" \
        "$(lay_run even-horizontal) $(lay_calls)"
    check "herdr-layout remembers the preset for next" "even-horizontal" "$(cat "$lay/state/herdr-layout/default_w1_t1.layout")"
    check "herdr-layout next: the preset after the last one (even-vertical stacks)" "exit 0 2 even-vertical" \
        "$(lay_run next) $(grep -c -- '--split down' "$lay/calls") $(cat "$lay/state/herdr-layout/default_w1_t1.layout")"
    lay_set 160 p3 false p1 p2 p3 p4
    check "herdr-layout main-vertical: main 80 of 160 columns, the rest stacked, focus kept" \
        "exit 0 move p2 --tab w1:t1 --split right --target-pane p1 --ratio 0.5000 --no-focus|move p3 --tab w1:t1 --split down --target-pane p2 --ratio 0.3333 --focus|move p4 --tab w1:t1 --split down --target-pane p3 --ratio 0.5000 --no-focus" \
        "$(lay_run main-vertical) $(sed -n '4,$p' "$lay/calls" | paste -sd'|' -)"
    lay_set 200 p1 false p1 p2 p3
    check "herdr-layout main-vertical-mirrored: the rest on the left, main (80 of 200) on the right" \
        "exit 0 move p3 --new-tab --no-focus|move p1 --tab w1:t9 --split right --target-pane p3 --no-focus|move p1 --tab w1:t1 --split right --target-pane p2 --ratio 0.6000 --focus|move p3 --tab w1:t1 --split down --target-pane p2 --ratio 0.5000 --no-focus" \
        "$(lay_run main-vertical-mirrored) $(lay_calls)"
    lay_set 160 p1 false p1 p2 p3 p4 p5
    check "herdr-layout tiled: 5 panes in rows of 2, 2 and 1, as tmux 3.8" \
        "exit 0 move p3 --tab w1:t1 --split down --target-pane p1 --ratio 0.3333 --no-focus|move p5 --tab w1:t1 --split down --target-pane p3 --ratio 0.5000 --no-focus|move p2 --tab w1:t1 --split right --target-pane p1 --ratio 0.5000 --no-focus|move p4 --tab w1:t1 --split right --target-pane p3 --ratio 0.5000 --no-focus" \
        "$(lay_run tiled) $(sed -n '5,$p' "$lay/calls" | paste -sd'|' -)"
    check "herdr-layout next after tiled wraps to even-horizontal" "exit 0 even-horizontal" "$(lay_run next) $(cat "$lay/state/herdr-layout/default_w1_t1.layout")"
    rm -rf "$lay/state"; lay_set 160 p1 false p1 p2
    check "herdr-layout tiled: 2 panes stacked, as tmux" "move p2 --tab w1:t1 --split down --target-pane p1 --ratio 0.5000 --no-focus" "$(lay_run tiled >/dev/null; sed -n 2p "$lay/calls")"
    lay_set 160 p1 false p1 p2 p3
    check "herdr-layout: each Herdr session keeps its own state" "exit 0 even-vertical tiled" \
        "$( (export HERDR_SESSION=s2; lay_run even-vertical) ) $(cat "$lay/state/herdr-layout/s2_w1_t1.layout") $(cat "$lay/state/herdr-layout/default_w1_t1.layout")"
    rm -rf "$lay/state"
    lay_set 160 p2 true p1 p2 p3
    check "herdr-layout unzooms first, as tmux does" "zoom --pane p2 --off" "$(lay_run rotate-up >/dev/null; head -1 "$lay/calls")"
    # tmux's pane numbers do not change with a layout, only with a rotation: herdr-layout keeps the order per tab.
    rm -rf "$lay/state"; lay_set 160 p1 false p1 p2 p3
    check "herdr-layout keeps the pane order it used" "p1 p2 p3" "$(lay_run main-horizontal-mirrored >/dev/null; cat "$lay/state/herdr-layout/default_w1_t1.order")"
    lay_set 160 p1 false p2 p3 p1
    echo "p2 p3 p1" > "$lay/state/herdr-layout/default_w1_t1.tree" # the split tree that layout left (the stub cannot)
    check "herdr-layout: after a mirrored layout the main pane is still the first one (tmux numbering)" \
        "exit 0 move p2 --tab w1:t1 --split right --target-pane p1 --ratio 0.5000 --no-focus" "$(lay_run main-vertical) $(sed -n 3p "$lay/calls")"
    check "herdr-layout rotate-up rotates the kept order, so the next pane becomes main" \
        "swap --source-pane p1 --target-pane p2|swap --source-pane p1 --target-pane p3|swap --source-pane p2 --target-pane p3|swap --source-pane p2 --target-pane p3 p2 p3 p1" "$(lay_run rotate-up >/dev/null; lay_calls) $(cat "$lay/state/herdr-layout/default_w1_t1.order")"
    lay_set 160 p1 false p4 p2 p3 p1
    check "herdr-layout: a new pane joins the order at the end" "p2 p3 p1 p4" "$(lay_run tiled >/dev/null; cat "$lay/state/herdr-layout/default_w1_t1.order")"
    rm -rf "$lay/state"
    lay_set 160 p1 false p1
    check "herdr-layout: one pane, nothing to do" "exit 0 0" "$(lay_run tiled) $(wc -l < "$lay/calls" | tr -d ' ')"
    lay_set 160 p1 false p1 p2 p3
    echo 3 > "$lay/fail-move"
    check "herdr-layout: a failed move names the tab still holding panes" "exit 1 1" "$(lay_run even-vertical) $(grep -c 'w1:t9' "$lay/err")"
    rm -f "$lay/fail-move"
    check "herdr-layout: an unknown layout is refused" "exit 2" "$(lay_run sideways)"
    check "herdr-layout: no action prints the usage" "exit 2 1" "$(lay_run '') $(grep -c '^usage: herdr-layout' "$lay/err")"
    # Herdr's own swaps (prefix { } H L) change which pane sits in each place; like tmux's swap-pane, they change the
    # pane numbers, so the main pane is whichever now sits in the first one's place.
    rm -rf "$lay/state"; mkdir -p "$lay/state/herdr-layout"
    echo "p1 p2 p3" > "$lay/state/herdr-layout/default_w1_t1.order"; echo "p1 p2 p3" > "$lay/state/herdr-layout/default_w1_t1.tree"
    lay_set 160 p1 false p2 p1 p3
    check "herdr-layout: after Herdr swapped p1 and p2, p2 is the main pane" \
        "exit 0 move p1 --tab w1:t1 --split right --target-pane p2 --ratio 0.5000 --focus" "$(lay_run main-vertical) $(sed -n 3p "$lay/calls")"
    rm -rf "$lay/state"; mkdir -p "$lay/state/herdr-layout/default_w1_t1.lock"
    sleep 30 & live=$!
    echo "$live" > "$lay/state/herdr-layout/default_w1_t1.lock/pid"
    check "herdr-layout: a second run at once is refused" "exit 1 1" "$(lay_run tiled) $(grep -c 'already running' "$lay/err")"
    kill "$live" 2> /dev/null; wait "$live" 2> /dev/null
    check "herdr-layout: a lock left by a run that died is taken over" "exit 0 0" "$(lay_run tiled) $(find "$lay/state/herdr-layout" -maxdepth 1 -name default_w1_t1.lock 2> /dev/null | wc -l | tr -d ' ')"
    # herdr-join: tmux's join-pane. The stub serves the pane's layout (tab w1:t1), tabs.json and workspaces.json, logs
    # a move and answers it with move.json. Not a terminal here, so the script reads a number from stdin.
    join="$work/herdr-join"; mkdir -p "$join"
    cat > "$join/herdr" <<'STUB'
#!/usr/bin/env bash
d=$(dirname "$0")
case "$1 $2" in
    "pane layout") if [ -e "$d/layout.$4.json" ]; then cat "$d/layout.$4.json"
                   else echo '{"result":{"layout":{"tab_id":"w1:t1","focused_pane_id":"p1","zoomed":false}}}'; fi ;;
    "pane list") echo '{"result":{"panes":[{"pane_id":"p1","tab_id":"w1:t1"},{"pane_id":"q1","tab_id":"w2:t1"},{"pane_id":"q2","tab_id":"w2:t1"}]}}' ;;
    "pane zoom") shift; echo "$*" >> "$d/calls"; echo '{}' ;;
    "tab list") printf '{"result":{"tabs":%s}}\n' "$(cat "$d/tabs.json")" ;;
    "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"chezmoi"},{"workspace_id":"w2","label":"other"}]}}' ;;
    "pane move") shift; echo "$*" >> "$d/calls"; cat "$d/move.json" ;;
    *) exit 2 ;;
esac
STUB
    chmod +x "$join/herdr"
    join_tabs() { # join_tabs TAB_ID:LABEL:PANES...
        local t
        for t in "$@"; do
            jq -nc --arg t "$(cut -d: -f1,2 <<< "$t")" --arg l "$(cut -d: -f3 <<< "$t")" --argjson n "${t##*:}" \
                '{tab_id: $t, workspace_id: ($t | split(":")[0]), number: ($t | split(":t")[1] | tonumber), label: $l, pane_count: $n}'
        done | jq -sc . > "$join/tabs.json"
    }
    # ${2-p1} unquoted on purpose: join_run X '' must pass no argument at all, not an empty one.
    # shellcheck disable=SC2086
    join_run() { : > "$join/calls"; printf '%s\n' "$1" | HERDR_BIN_PATH="$join/herdr" bash dot_local/bin/executable_herdr-join ${2-p1} 2> "$join/err"; echo "exit $?"; }
    join_calls() { paste -sd'|' "$join/calls"; }
    echo '{"result":{"move_result":{"changed":true}}}' > "$join/move.json"
    join_tabs w1:t1:1:2 w1:t2:2:1 w2:t1:logs:3
    check "herdr-join lists every other tab, in every workspace, numbered" \
        "1) chezmoi  2  (1 pane)|2) other  1: logs  (3 panes)" "$(join_run '' > /dev/null; grep -E '^[0-9]+\) ' "$join/err" | paste -sd'|' -)"
    check "herdr-join moves the pane right of the picked tab's focused pane, focus following (tmux join-pane -h)" \
        "exit 0 move p1 --tab w2:t1 --split right --focus" "$(join_run 2) $(join_calls)"
    check "herdr-join: an empty choice cancels" "exit 0 " "$(join_run '') $(join_calls)"
    # Herdr refuses a move into or out of a zoomed tab (reason zoomed_tab); tmux's join-pane unzooms. Unzoom through the
    # tab's focused pane, so focus stays where it was.
    echo '{"result":{"layout":{"tab_id":"w2:t1","focused_pane_id":"q2","zoomed":true}}}' > "$join/layout.q1.json"
    check "herdr-join unzooms the picked tab through its focused pane first" \
        "exit 0 zoom --pane q2 --off|move p1 --tab w2:t1 --split right --focus" "$(join_run 2) $(join_calls)"
    rm "$join/layout.q1.json"
    echo '{"result":{"layout":{"tab_id":"w1:t1","focused_pane_id":"p1","zoomed":true}}}' > "$join/layout.p1.json"
    check "herdr-join unzooms the pane's own tab first" "exit 0 zoom --pane p1 --off|move p1 --tab w2:t1 --split right --focus" \
        "$(join_run 2) $(join_calls)"
    check "herdr-join: a cancel leaves the zoom alone" "exit 0 " "$(join_run '') $(join_calls)"
    rm "$join/layout.p1.json"
    check "herdr-join: a number not on the list is refused" "exit 1 " "$(join_run 9) $(join_calls)"
    check "herdr-join: a choice that is not a number is refused" "exit 1 " "$(join_run x) $(join_calls)"
    echo '{"error":{"code":"tab_not_found","message":"tab w1:t2 not found"}}' > "$join/move.json"
    check "herdr-join shows Herdr's refusal" "exit 1 1" "$(join_run 1) $(grep -c 'tab w1:t2 not found' "$join/err")"
    echo 'oops' > "$join/move.json"
    check "herdr-join: an answer that is not JSON fails" "exit 1" "$(join_run 1)"
    echo '{"result":{"move_result":{"changed":false,"reason":"same_tab"}}}' > "$join/move.json"
    check "herdr-join: a move Herdr did not make fails" "exit 1 1" "$(join_run 1) $(grep -c 'same_tab' "$join/err")"
    join_tabs w1:t1:1:2
    check "herdr-join: no other tab, no move" "exit 1 1 " "$(join_run 1) $(grep -c 'no other tab' "$join/err") $(join_calls)"
    check "herdr-join: no pane id" "exit 1" "$(HERDR_ACTIVE_PANE_ID='' HERDR_PANE_ID='' join_run 1 '')"
fi
check "requirement check wants Herdr 0.9.2 or later (multiple prefixes)" 1 "$(render darwin run_after_99_assert_requirements.sh.tmpl | grep -c 'version_ge "$herdr_version" 0.9.2')"
# The stock-drift report runs on Omarchy only and never fails.
drift=run_after_95_omarchy_stock_drift.sh.tmpl
for host in $hosts; do
    expected=0
    [[ "$host" == omarchy ]] && expected=1
    check "$host stock-drift report present" "$expected" "$(render "$host" "$drift" | grep -c '^check_stock "tmux config"')"
done
check "omarchy stock-drift report is valid bash" "" "$(render omarchy "$drift" | bash -n 2>&1)"

# git's editor: VS Code on macOS; none on Omarchy, so git follows $EDITOR (Omarchy's launcher); nvim elsewhere.
check "darwin ~/.gitconfig editor" "editor = code --wait" "$(render darwin dot_gitconfig.tmpl | grep -E '^\s*editor' | xargs)"
check "omarchy ~/.gitconfig sets no editor" 0 "$(render omarchy dot_gitconfig.tmpl | grep -c 'editor =')"
check "ubuntu ~/.gitconfig editor" "editor = nvim" "$(render ubuntu dot_gitconfig.tmpl | grep -E '^\s*editor' | xargs)"

# zsh on Omarchy: interactive shells load Omarchy's defaults first (the omarchy-zsh package's options, then Omarchy's
# own envs, aliases and helpers), so everything after them, ~/.aliases included, still wins. Panes and nested shells
# follow zsh; Claude Code keeps bash. No other host gets any of it.
render omarchy dot_zshrc.tmpl > "$work/omarchy.zshrc"
check "omarchy ~/.zshrc loads omarchy-zsh options in interactive shells only" 1 \
    "$(grep -c '^if \[\[ -o interactive && -r /usr/share/omarchy-zsh/shell/zoptions ' "$work/omarchy.zshrc")"
check "omarchy ~/.zshrc loads Omarchy's aliases" 1 "$(grep -c 'source "$OMARCHY_PATH/default/bash/aliases"' "$work/omarchy.zshrc")"
check "omarchy ~/.zshrc runs ssh and the drive helpers in bash" 3 "$(grep -cE '^ +(ssh|iso2sd|format-drive)\(\) \{ _omarchy_bash ' "$work/omarchy.zshrc")"
check "omarchy ~/.zshrc sets SHELL to zsh" 1 "$(grep -c '^ *export SHELL=/usr/bin/zsh$' "$work/omarchy.zshrc")"
check "omarchy ~/.zshrc keeps Claude Code on bash" 1 "$(grep -c '^ *export CLAUDE_CODE_SHELL=/usr/bin/bash$' "$work/omarchy.zshrc")"
omarchy_block=$(grep -n 'omarchy-zsh/shell/zoptions ' "$work/omarchy.zshrc" | head -1 | cut -d: -f1)
aliases_line=$(grep -n 'source "$HOME/.aliases"' "$work/omarchy.zshrc" | head -1 | cut -d: -f1)
check "omarchy ~/.zshrc loads Omarchy's defaults before ~/.aliases" yes "$([[ ${omarchy_block:-0} -gt 0 && ${omarchy_block:-0} -lt ${aliases_line:-0} ]] && echo yes || echo no)"
if command -v zsh > /dev/null 2>&1; then
    check "omarchy ~/.zshrc is valid zsh" "" "$(zsh -n "$work/omarchy.zshrc" 2>&1)"
fi
for host in darwin intel arch ubuntu debian; do
    check "$host ~/.zshrc has no Omarchy zsh block" 0 "$(render "$host" dot_zshrc.tmpl | grep -c 'omarchy')"
done

# zsh feels the same on every host: vi keys set explicitly (after Omarchy's emacs default), Up/Down search history by
# prefix in vi mode, history suggestions from the system package, and syntax highlighting last unless already loaded.
for host in $hosts; do
    render "$host" dot_zshrc.tmpl > "$work/$host.zshrc"
    check "$host ~/.zshrc sets vi keys" 1 "$(grep -c '^ *bindkey -v$' "$work/$host.zshrc")"
    check "$host ~/.zshrc searches history by prefix in vi mode" 1 \
        "$(grep -c 'bindkey -M "$_keymap" "$_key" history-search-backward' "$work/$host.zshrc")"
    check "$host ~/.zshrc finds packaged zsh-autosuggestions" 1 \
        "$(grep -c '^ */usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \\$' "$work/$host.zshrc")"
    check "$host ~/.zshrc loads syntax highlighting only once" 1 \
        "$(grep -c 'ZSH_HIGHLIGHT_VERSION:-}" ]]; then$' "$work/$host.zshrc")"
    keys=$(grep -n '^ *bindkey -v$' "$work/$host.zshrc" | head -1 | cut -d: -f1)
    fzf=$(grep -n 'fzf --zsh' "$work/$host.zshrc" | head -1 | cut -d: -f1)
    highlight=$(grep -n 'ZSH_HIGHLIGHT_VERSION:-}' "$work/$host.zshrc" | head -1 | cut -d: -f1)
    local_rc=$(grep -n 'source "$HOME/.zshrc.local"' "$work/$host.zshrc" | head -1 | cut -d: -f1)
    check "$host ~/.zshrc sets vi keys before fzf binds its keys" yes "$([[ ${keys:-0} -gt 0 && ${keys:-0} -lt ${fzf:-0} ]] && echo yes || echo no)"
    check "$host ~/.zshrc loads syntax highlighting after ~/.zshrc.local" yes "$([[ ${highlight:-0} -gt ${local_rc:-0} && ${local_rc:-0} -gt 0 ]] && echo yes || echo no)"
    if command -v zsh > /dev/null 2>&1; then
        check "$host ~/.zshrc is valid zsh" "" "$(zsh -n "$work/$host.zshrc" 2>&1)"
    fi
done
check "omarchy ~/.zshrc sets vi keys after Omarchy's emacs default" yes \
    "$([[ ${omarchy_block:-0} -gt 0 && ${omarchy_block:-0} -lt $(grep -n '^ *bindkey -v$' "$work/omarchy.zshrc" | cut -d: -f1) ]] && echo yes || echo no)"
check "darwin packages include the zsh plugins" 2 "$(grep -cE '^brew "zsh-(autosuggestions|syntax-highlighting)"$' <(render darwin run_onchange_before_00_install_packages.sh.tmpl))"
check "omarchy packages include zsh-autosuggestions" 1 "$(render omarchy run_onchange_before_00_install_packages.sh.tmpl | grep -c '"zsh-autosuggestions"')"
# Omarchy's helpers on hosts without Omarchy: generated from the snapshots, deployed and sourced everywhere but Omarchy,
# with what is not taken over removed, and Omarchy's Ctrl+Alt+F widget renamed so fzf's Ctrl-T one cannot replace it.
check "omarchy does not get shared-helpers.zsh" no "$(manages omarchy .config/zsh/shared-helpers.zsh)"
for host in darwin intel arch ubuntu; do
    check "$host gets shared-helpers.zsh" yes "$(manages "$host" .config/zsh/shared-helpers.zsh)"
    check "$host ~/.zshrc sources shared-helpers.zsh" 1 "$(grep -c 'source "$HOME/.config/zsh/shared-helpers.zsh"' "$work/$host.zshrc")"
done
render darwin dot_config/zsh/shared-helpers.zsh.tmpl > "$work/helpers.zsh"
check "shared helpers define tdl, hdl, fip, ga and sff" 5 "$(grep -cE '^(tdl|hdl|fip|ga|sff)\(\) \{' "$work/helpers.zsh")"
check "shared helpers drop open, zd, a, cd and r, keep compress" 2 "$(grep -cE '^(unalias a cd r|unfunction zd open) 2> /dev/null$' "$work/helpers.zsh")"
check "shared helpers define Omarchy's compress" 1 "$(grep -c '^compress() {' "$work/helpers.zsh")"
check "shared helpers run ssh through Omarchy's reconnect wrapper in bash" 1 "$(grep -c 'ssh() { bash -c .source "$1"; shift; ssh "$@". ssh-reconnect "$HOME/.config/zsh/ssh-reconnect.bash" "$@"; }' "$work/helpers.zsh")"
check "omarchy does not get ssh-reconnect.bash" no "$(manages omarchy .config/zsh/ssh-reconnect.bash)"
for host in darwin intel arch ubuntu; do
    check "$host gets ssh-reconnect.bash" yes "$(manages "$host" .config/zsh/ssh-reconnect.bash)"
done
check "ssh-reconnect.bash is Omarchy's function, valid bash" "1 " "$(render darwin dot_config/zsh/ssh-reconnect.bash.tmpl | grep -c '^ssh() {') $(render darwin dot_config/zsh/ssh-reconnect.bash.tmpl | bash -n 2>&1)"
check "omarchy stock-drift report covers ssh-reconnect" 1 "$(render omarchy run_after_95_omarchy_stock_drift.sh.tmpl | grep -c 'ssh-port-forwarding ssh-reconnect tmux')"
check "every host's ~/.aliases makes cd plain where Omarchy aliased it to zd" "" "$(bash -c 'alias cd=zd; source dot_aliases; alias cd 2>&1 | grep zd')"
check "tmux opens zsh in new panes" 1 "$(grep -c "^if-shell '\[ -x /usr/bin/zsh \]' 'set -g default-shell /usr/bin/zsh' 'if-shell \"\[ -x /bin/zsh \]\" \"set -g default-shell /bin/zsh\"'$" dot_config/tmux/tmux.conf)"
check "shared helpers rename the Ctrl+Alt+F widget" "0 1" "$(grep -c 'fzf-file-widget()' "$work/helpers.zsh") $(grep -c "^  bindkey '\^\[\^F' fzf-find-files-widget" "$work/helpers.zsh")"
check "shared helpers' sff prefers GNU find" 1 "$(grep -cF 'file=$(${commands[gfind]:-find} . -type f' "$work/helpers.zsh")"
if command -v zsh > /dev/null 2>&1; then
    check "shared helpers are valid zsh" "" "$(zsh -n "$work/helpers.zsh" 2>&1)"
fi
check "omarchy ~/.zshrc turns variable completion back on" 1 "$(grep -c 'unfunction _parameters 2> /dev/null && autoload -Uz _parameters' "$work/omarchy.zshrc")"
check "omarchy ~/.zshrc keeps Omarchy's Ctrl+Alt+F widget" 1 "$(grep -c 'functions\[fzf-find-files-widget\]=\$functions\[fzf-file-widget\]' "$work/omarchy.zshrc")"
check "omarchy stock-drift report covers the shell snapshots" 1 "$(render omarchy run_after_95_omarchy_stock_drift.sh.tmpl | grep -c '^check_stock "zsh options (fzf keys)"')"

# Terminal settings set by chezmoi: iTerm2's dynamic profile (left Option as Alt) on macOS; Wave's settings (copy on
# select, plus Option as Alt on macOS) on macOS and Omarchy; foot's selection-target=both on Omarchy. Modify scripts
# change only those settings in files the apps (or Omarchy) write themselves. Warp is left to its own settings sync.
iterm="Library/Application Support/iTerm2/DynamicProfiles/chezmoi-option-as-alt.json"
check "darwin manages the iTerm2 profile" yes "$(manages darwin "$iterm")"
for host in omarchy arch ubuntu; do check "$host leaves the iTerm2 profile alone" no "$(manages "$host" "$iterm")"; done
for host in darwin omarchy; do check "$host manages Wave's settings" yes "$(manages "$host" .config/waveterm/settings.json)"; done
for host in arch ubuntu; do check "$host leaves Wave's settings alone" no "$(manages "$host" .config/waveterm/settings.json)"; done
check "omarchy manages foot's settings" yes "$(manages omarchy .config/foot/foot.ini)"
for host in darwin arch ubuntu; do check "$host leaves foot's settings alone" no "$(manages "$host" .config/foot/foot.ini)"; done
for host in $hosts; do check "$host leaves Warp's settings alone" no "$(manages "$host" .warp/settings.toml)"; done
iterm_modify="private_Library/private_Application Support/iTerm2/DynamicProfiles/modify_chezmoi-option-as-alt.json"
check "iTerm2 profile: left Option Esc+, right Option from the shared look, rewritable, Claude triggers" "2 null true iTermEnterWorkgroupTrigger,iTermExitWorkgroupTrigger" \
    "$(printf '' | bash "$iterm_modify" | jq -r '.Profiles[0] | "\(."Option Key Sends") \(."Right Option Key Sends") \(.Rewritable) \(.Triggers | map(.action) | join(","))"')"
check "iTerm2 profile: keeps what iTerm2 wrote, adds no duplicate trigger" "x,iTermEnterWorkgroupTrigger,iTermExitWorkgroupTrigger" \
    "$(printf '{"Profiles": [{"Triggers": [{"action": "x"}, {"action": "iTermEnterWorkgroupTrigger"}], "Right Option Key Sends": 0}]}' | bash "$iterm_modify" | bash "$iterm_modify" | jq -r '.Profiles[0].Triggers | map(.action) | join(",")')"
# The shared look: a second dynamic profile chezmoi owns entirely (iTerm2 never rewrites it), the parent of the profile
# above, so every Mac gets the same font, colours, bell and scrollback, and the repo's trigger switch.
shared="Library/Application Support/iTerm2/DynamicProfiles/chezmoi-0-shared-look.json"
shared_tmpl="private_Library/private_Application Support/iTerm2/DynamicProfiles/chezmoi-0-shared-look.json.tmpl"
shared_look() { # shared_look repo|true|false: the shared look as a Mac renders it, with the repo's trigger switch or this value
    local data
    data="$(host_data darwin)"
    [[ "$1" == repo ]] || data="$(printf '%s' "$data" | jq -c ". + {iterm2_triggers_in_interactive_apps: $1}")"
    chezmoi --override-data "$data" execute-template < "$shared_tmpl"
}
check "darwin manages the shared iTerm2 look" yes "$(manages darwin "$shared")"
for host in omarchy arch ubuntu; do check "$host leaves the shared iTerm2 look alone" no "$(manages "$host" "$shared")"; done
check "shared look loads before the profile that inherits from it (iTerm2 loads files in name order)" "chezmoi-0-shared-look.json chezmoi-option-as-alt.json" \
    "$(grep 'iTerm2/DynamicProfiles/' "$work/darwin.managed" | sed 's#.*/##' | LC_ALL=C sort | xargs)"
check "shared look: identity and parent" "Shared Look (chezmoi)|chezmoi-shared-look|Default|false" \
    "$(shared_look repo | jq -r '.Profiles[0] | "\(.Name)|\(.Guid)|\(."Dynamic Profile Parent Name")|\(has("Rewritable"))"')"
check "shared look: JetBrains Mono Nerd Font Mono, no second font, no ligatures" "JetBrainsMonoNFM-Regular 12|JetBrainsMonoNFM-Regular 12|false|false|false" \
    "$(shared_look repo | jq -r '.Profiles[0] | "\(."Normal Font")|\(."Non Ascii Font")|\(."Use Non-ASCII Font")|\(."ASCII Ligatures")|\(."Non-ASCII Ligatures")"')"
check "shared look: silent, flashing bell and all 16 ANSI colours" "true|true|true" \
    "$(shared_look repo | jq -r '.Profiles[0] as $p | "\($p."Silence Bell")|\($p."Flashing Bell")|\([range(0;16) | "Ansi \(.) Color"] | all(. as $k | $p | has($k)))"')"
check "shared look: 10000 lines of scrollback" "10000|false" \
    "$(shared_look repo | jq -r '.Profiles[0] | "\(."Scrollback Lines")|\(."Unlimited Scrollback")"')"
check "shared look: one colour set, not separate light and dark ones (which would hide the Atom colours)" false \
    "$(shared_look repo | jq '.Profiles[0]."Use Separate Colors for Light and Dark Mode"')"
check "shared look: no per-Mac or left-Option keys" "" \
    "$(shared_look repo | jq -r '.Profiles[0] | keys[] | select(IN("Description","Default Bookmark","Shortcut","Tags","Working Directory","Option Key Sends"))')"
check "shared look: names no font that isn't installed (Hack)" 0 "$(shared_look repo | grep -c Hack)"
check "shared look: triggers off in full-screen apps by default" false "$(shared_look repo | jq '.Profiles[0]."Enable Triggers in Interactive Apps"')"
check "shared look: switch on writes true" true "$(shared_look true | jq '.Profiles[0]."Enable Triggers in Interactive Apps"')"
check "shared look: a quoted \"true\" still writes true" true "$(shared_look '"true"' | jq '.Profiles[0]."Enable Triggers in Interactive Apps"')"
check "shared look: any other switch value stops the render with a clear message, instead of invalid JSON" 1 \
    "$(shared_look '"yes"' 2>&1 | grep -c 'iterm2_triggers_in_interactive_apps must be true or false')"
check "iTerm2 profile: inherits from the shared look" "chezmoi-shared-look|false|false|false|2" \
    "$(printf '' | bash "$iterm_modify" | jq -r '.Profiles[0] | "\(."Dynamic Profile Parent GUID")|\(has("Dynamic Profile Parent Name"))|\(has("Right Option Key Sends"))|\(has("Enable Triggers in Interactive Apps"))|\(."Option Key Sends")"')"
check "iTerm2 profile: drops the old parent and a local trigger switch, keeps other local settings" "false|false|x" \
    "$(printf '{"Profiles": [{"Dynamic Profile Parent Name": "Default", "Enable Triggers in Interactive Apps": true, "Font": "x"}]}' | bash "$iterm_modify" | jq -r '.Profiles[0] | "\(has("Dynamic Profile Parent Name"))|\(has("Enable Triggers in Interactive Apps"))|\(.Font)"')"
check "iTerm2 profile: leaves a file that is not JSON alone" "not json" "$(printf 'not json' | bash "$iterm_modify")"
if command -v jq > /dev/null 2>&1; then
    wave() { render "$1" dot_config/waveterm/modify_settings.json.tmpl > "$work/wave.$1.sh"; printf '%s' "$2" | bash "$work/wave.$1.sh"; }
    check "Wave on macOS: copy on select, split buttons and Option as Alt, rest kept" '{"a":1,"term:copyonselect":true,"app:showsplitbuttons":true,"term:macoptionismeta":true}' "$(wave darwin '{"a": 1}' | jq -c .)"
    check "Wave on Omarchy: copy on select and split buttons" '{"a":1,"term:copyonselect":true,"app:showsplitbuttons":true}' "$(wave omarchy '{"a": 1}' | jq -c .)"
    check "Wave: leaves a file that is not JSON alone" "not json" "$(wave darwin 'not json')"
fi
foot() { printf '%b' "$1" | bash dot_config/foot/modify_foot.ini | paste -sd'|' -; }
check "foot: sets selection-target at the end of [main]" "[main]|font=x|selection-target=both|[colors]|bg=1" "$(foot '[main]\nfont=x\n[colors]\nbg=1\n')"
check "foot: replaces an existing selection-target" "[main]|selection-target=both|font=x" "$(foot '[main]\nselection-target=primary\nfont=x\n')"
check "foot: settings above the first header are [main]" "font=x|selection-target=both|[colors]|bg=1" "$(foot 'font=x\n[colors]\nbg=1\n')"
check "foot: second run changes nothing" "$(foot '[main]\nfont=x\n')" "$(printf '[main]\nfont=x\n' | bash dot_config/foot/modify_foot.ini | bash dot_config/foot/modify_foot.ini | paste -sd'|' -)"
check "omarchy packages include alacritty and waveterm-bin" 2 "$(render omarchy run_onchange_before_00_install_packages.sh.tmpl | grep -oE '"(alacritty|waveterm-bin)"' | sort -u | wc -l | tr -d ' ')"

# Closing a pane, window/tab or session always asks first (left Option is Alt on the Macs); Alt+Left/Right jump words in zsh.
check "tmux Alt-Esc asks before killing the pane" 1 "$(grep -c '^bind -N "Kill pane (asks first)" -n M-Escape confirm-before ' dot_config/tmux/tmux.conf)"
check "tmux asks before every kill binding" "0 4" "$(grep -E '(kill-pane|kill-window|kill-session)$' dot_config/tmux/tmux.conf | grep -vc 'confirm-before') $(grep -cE '^bind .*confirm-before -p "kill-(pane|window|session) ' dot_config/tmux/tmux.conf)"
check "darwin ~/.zshrc binds Alt+Left to backward-word" 1 "$(grep -cF "for _key in '^[[1;3D' '^[^[[D'; do bindkey -M \"\$_keymap\" \"\$_key\" backward-word" "$work/darwin.zshrc")"

# Alt+Left/Right belong to the shell (word jumps), not to tmux windows or herdr tabs.
check "tmux unbinds Alt-Left/Right and binds nothing to them" "2 0" "$(grep -cE '^unbind -n M-(Left|Right)$' dot_config/tmux/tmux.conf) $(grep -cE '^bind .* -n M-(Left|Right) ' dot_config/tmux/tmux.conf)"
# tmux before 3.8 does not recognise Ghostty, so its extended keys (Ctrl+Enter, Shift+Enter) are declared once.
check "tmux declares Ghostty's extended keys once" 1 "$(grep -cxF 'set -ag terminal-features "xterm-ghostty:extkeys"' dot_config/tmux/tmux.conf)"
check "herdr binds nothing to alt+left/right" 0 "$(grep -vE '^ *#' dot_config/herdr/config.toml.tmpl | grep -cE '"alt\+(left|right)"')"

# iTerm2's after-script (macOS only): the repo's global settings (clipboard access for OSC 52 copies in tmux, herdr and
# Neovim among them), then three checks: the default profile, the Claude Code integration, and settings changed on this
# Mac only. Run here in a stub Mac: stub defaults and pgrep, ITERM2_APP, HOME and PATH pointed at $work/it.
it96=run_after_96_macos_iterm2.sh.tmpl
check "darwin runs the iTerm2 after-script, not the old clipboard one" "yes no" "$(manages darwin 96_macos_iterm2.sh) $(manages darwin 96_macos_terminal_clipboard.sh)"
check "darwin iTerm2 script turns on clipboard access with the other globals" 1 "$(render darwin "$it96" | grep -cx 'ensure_global "AllowClipboardAccess" -bool true')"
check "darwin iTerm2 script sets 9 globals" 9 "$(render darwin "$it96" | grep -c '^ensure_global "')"
check "darwin iTerm2 script: bool, int and spaced keys" 3 \
    "$(render darwin "$it96" | grep -cxE 'ensure_global "Print In Black And White" -bool true|ensure_global "ShowFullScreenTabBar" -bool false|ensure_global "PasteTabToStringTabStopSize" -int 4')"
check "darwin iTerm2 script is valid bash" "" "$(render darwin "$it96" | bash -n 2>&1)"
for host in omarchy arch ubuntu; do
    check "$host gets no iTerm2 script" "" "$(render "$host" "$it96" | tr -d '[:space:]')"
done
it="$work/it"
it_profile="$it/home/Library/Application Support/iTerm2/DynamicProfiles/chezmoi-option-as-alt.json"
mkdir -p "$it/iTerm.app" "$it/bin" "$it/home/.claude" "$it/home/.config/iterm2" "${it_profile%/*}"
cat > "$it/bin/defaults" << 'EOF'
#!/bin/bash
# Stub: defaults read|write com.googlecode.iterm2 KEY [-bool true|false | -int N], one file per key under $IT/defaults.
case "$1" in
    read) [[ -f "$IT/defaults/$3" ]] || exit 1; cat "$IT/defaults/$3" ;;
    write)
        grep -qxF "$3" "$IT/fail_write" 2> /dev/null && exit 1
        case "$4 $5" in "-bool true") v=1 ;; "-bool false") v=0 ;; *) v="$5" ;; esac
        printf '%s\n' "$v" > "$IT/defaults/$3"
        printf '%s\n' "$3" >> "$IT/defaults/written" ;;
esac
EOF
printf '#!/bin/sh\nexit "$(cat "$IT/running")"\n' > "$it/bin/pgrep"
chmod +x "$it/bin/defaults" "$it/bin/pgrep"
render darwin "$it96" > "$it/script.sh"
it_reset() { # the all-OK state, iTerm2 not running ($it/running holds pgrep's exit code)
    rm -rf "$it/defaults" "$it/cache" "$it/fail_write" "$it/nojq"
    mkdir -p "$it/defaults"
    for k in AllowClipboardAccess CopySelection DoubleClickPerformsSmartSelection "Print In Black And White"; do echo 1 > "$it/defaults/$k"; done
    for k in ShowFullScreenTabBar HapticFeedbackForEsc SoundForEsc VisualIndicatorForEsc; do echo 0 > "$it/defaults/$k"; done
    echo 4 > "$it/defaults/PasteTabToStringTabStopSize"
    echo chezmoi-left-option-as-alt > "$it/defaults/Default Bookmark Guid"
    printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\\"/Users/x/.config/iterm2/it2\\" handle-agent-hook"}]}]}}\n' > "$it/home/.claude/settings.json"
    printf '#!/bin/sh\n' > "$it/home/.config/iterm2/it2"
    chmod +x "$it/home/.config/iterm2/it2"
    printf '' | bash "$iterm_modify" > "$it_profile"
    shared_look repo > "${it_profile%/*}/chezmoi-0-shared-look.json"
    echo 1 > "$it/running"
}
iterm_after() { # the script's output in the stub Mac, then exit=<code>
    local out rc
    out="$(IT="$it" HOME="$it/home" PATH="${it_path:+$it_path:}$it/bin:$PATH" ITERM2_APP="${it_app:-$it/iTerm.app}" CHEZMOI_CACHE_DIR="$it/cache" XDG_STATE_HOME="$it/state" bash "$it/script.sh" 2>&1)"
    rc=$?
    printf '%s\nexit=%s' "$out" "$rc"
}
it_todo() { cat "$it/cache"/after-apply.* 2> /dev/null; }
ok4="OK:   iTerm2's global settings match the repo|OK:   iTerm2's default profile is chezmoi's (left Option as Alt)|OK:   iTerm2's Claude Code integration is installed|OK:   iTerm2 profile has no settings changed on this Mac only|exit=0"
it_reset
check "iTerm2 script: all OK on chezmoi's own profile, nothing written" "$ok4|no" "$(iterm_after | paste -sd'|' -)|$([[ -e "$it/defaults/written" ]] && echo yes || echo no)"
it_reset
echo 0 > "$it/defaults/DoubleClickPerformsSmartSelection"
echo 0 > "$it/running"
check "iTerm2 script: a changed global is written back; reopen iTerm2 goes on the to-do list" \
    "NOTE: iTerm2 global settings updated: DoubleClickPerformsSmartSelection; quit and reopen iTerm2 for them to take effect|1|1" \
    "$(iterm_after | head -1)|$(cat "$it/defaults/DoubleClickPerformsSmartSelection")|$(it_todo | grep -c 'reopen iTerm2')"
it_reset
rm "$it/defaults/PasteTabToStringTabStopSize"
check "iTerm2 script: a missing global is written (iTerm2 not running)" "OK:   iTerm2 global settings updated: PasteTabToStringTabStopSize|4" \
    "$(iterm_after | head -1)|$(cat "$it/defaults/PasteTabToStringTabStopSize")"
for guid in 246D2B5F ""; do
    it_reset
    printf '%s\n' "$guid" > "$it/defaults/Default Bookmark Guid"
    check "iTerm2 script: default profile [$guid], iTerm2 closed: made chezmoi's, command printed" \
        "1|1|chezmoi-left-option-as-alt|0" \
        "$(iterm_after > "$it/out"; grep -c '^\$ defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string chezmoi-left-option-as-alt$' "$it/out")|$(grep -c "^OK:   iTerm2's default profile is chezmoi's (set now)" "$it/out")|$(cat "$it/defaults/Default Bookmark Guid")|$(it_todo | grep -c 'Set as Default')"
    it_reset
    printf '%s\n' "$guid" > "$it/defaults/Default Bookmark Guid"
    echo 0 > "$it/running"
    check "iTerm2 script: default profile [$guid], iTerm2 running: left alone, quit and apply again" \
        "1|1|$guid" \
        "$(iterm_after | grep -c "^NOTE: iTerm2's default profile is not chezmoi's")|$(it_todo | grep -c 'Quit iTerm2, then run chezmoi apply')|$(cat "$it/defaults/Default Bookmark Guid")"
done
it_reset
printf '{}\n' > "$it/home/.claude/settings.json"
check "iTerm2 script: no hook means no Claude Code integration" 1 "$(iterm_after | grep -c "^NOTE: iTerm2's Claude Code integration is missing")"
it_reset
rm "$it/home/.config/iterm2/it2"
check "iTerm2 script: no it2 helper means no Claude Code integration" 1 "$(iterm_after | grep -c "^NOTE: iTerm2's Claude Code integration is missing")"
it_reset
jq '.Profiles[0] += {"Font": "x", "Columns": 100} | .Profiles[0].Triggers += [{"action": "iTermHighlightLineTrigger"}]' "$it_profile" > "$it/p.json" && mv "$it/p.json" "$it_profile"
check "iTerm2 script: names settings changed on this Mac only, off the to-do list" \
    "NOTE: iTerm2 settings changed on this Mac only, not shared: Columns, Font, trigger iTermHighlightLineTrigger. To share them, move them into chezmoi-0-shared-look.json.tmpl; to drop them, delete them from ~/Library/Application Support/iTerm2/DynamicProfiles/chezmoi-option-as-alt.json|0" \
    "$(iterm_after | grep '^NOTE: iTerm2 settings changed')|$(it_todo | grep -c 'this Mac only')"
# iTerm2 keeps some keys it saves even when they equal the parent's value ("Use Separate Colors for Light and Dark
# Mode" on 2026-11-20, after a font change and back on a real Mac): a value equal to the shared look is no local change.
it_reset
jq '.Profiles[0] += {"Use Separate Colors for Light and Dark Mode": false}' "$it_profile" > "$it/p.json" && mv "$it/p.json" "$it_profile"
check "iTerm2 script: a setting saved with the shared look's own value is not a local change" 1 "$(iterm_after | grep -c '^OK:   iTerm2 profile has no settings changed on this Mac only$')"
it_reset
jq '.Profiles[0] += {"Use Separate Colors for Light and Dark Mode": true}' "$it_profile" > "$it/p.json" && mv "$it/p.json" "$it_profile"
check "iTerm2 script: the same setting with another value is one" 1 "$(iterm_after | grep -c 'not shared: Use Separate Colors for Light and Dark Mode\.')"
it_reset
jq '.Profiles[0] += {"Use Separate Colors for Light and Dark Mode": false}' "$it_profile" > "$it/p.json" && mv "$it/p.json" "$it_profile"
rm "${it_profile%/*}/chezmoi-0-shared-look.json"
check "iTerm2 script: without the shared look file, every extra setting counts" 1 "$(iterm_after | grep -c 'not shared: Use Separate Colors for Light and Dark Mode\.')"
it_reset
printf 'not json' > "$it_profile"
check "iTerm2 script: a profile that is not JSON gives no local-changes line, exit 0" "0|exit=0" "$(iterm_after | grep -c 'changed on this Mac only')|$(iterm_after | tail -1)"

# macOS settings (run_after_97_macos_defaults.sh, every Mac): the keys in [[macos_defaults]] of .chezmoidata/macos.toml,
# written where a Mac differs, then the remote-access check. Run here in a stub Mac: stub defaults (-currentHost too),
# pgrep, killall, launchctl (a loaded job = a file under $MD/launchd) and pmset (prints $MD/pmset).
md97=run_after_97_macos_defaults.sh.tmpl
for host in darwin intel; do
    check "$host runs the macOS settings script" yes "$(manages "$host" 97_macos_defaults.sh)"
done
for host in omarchy arch ubuntu; do
    check "$host gets no macOS settings script" "" "$(render "$host" "$md97" | tr -d '[:space:]')"
done
check "darwin macOS settings script is valid bash" "" "$(render darwin "$md97" | bash -n 2>&1)"
check "darwin macOS settings script sets 43 keys" 43 "$(render darwin "$md97" | grep -c "^ensure_default '")"
check "darwin macOS settings: bool, float, string, int and per-machine keys" 5 "$(render darwin "$md97" | grep -cxE \
    "ensure_default 'Dock' - 0 'com.apple.dock' 'autohide' -bool true|ensure_default 'Dock' - 0 'com.apple.dock' 'autohide-time-modifier' -float 0.15|ensure_default 'Finder' - 0 'com.apple.finder' 'FXDefaultSearchScope' -string 'SCcf'|ensure_default 'logout' - 1 'com.apple.AppleMultitouchTrackpad' 'TrackpadFiveFingerPinchGesture' -int 2|ensure_default 'ControlCenter' -currentHost 0 'com.apple.controlcenter' 'BatteryShowPercentage' -bool true")"
check "darwin macOS settings: new Finder windows open in this Mac's Downloads" 1 \
    "$(render darwin "$md97" | grep -cxF "ensure_default 'Finder' - 0 'com.apple.finder' 'NewWindowTargetPath' -string 'file://$HOME/Downloads/'")"
check "darwin macOS settings: three-finger drag and tap-to-drag off on both trackpads" 6 \
    "$(render darwin "$md97" | grep -cE "'(TrackpadThreeFingerDrag|Dragging|DragLock)' -bool false$")"
md="$work/md"
mkdir -p "$md/bin"
cat > "$md/bin/defaults" << 'EOF'
#!/bin/bash
# Stub: defaults [-currentHost] read DOMAIN KEY | write DOMAIN KEY TYPE VALUE, one file per key under $MD/prefs.
scope=user
[[ "$1" == -currentHost ]] && { scope=host; shift; }
f="$MD/prefs/$scope/$2/$3"
case "$1" in
    read) [[ -f "$f" ]] || exit 1; cat "$f" ;;
    write)
        grep -qxF "$3" "$MD/fail_write" 2> /dev/null && exit 1
        if [[ "$4" == -dict-add ]]; then
            # A symbolic hotkey: append the entry in defaults' text form (the last entry for an id wins when read).
            set -- $(printf '%s' "$6" | grep -oE '<integer>[0-9]+</integer>|<(true|false)/>' | sed -E 's/<integer>([0-9]+)<\/integer>/\1/; s/<true\/>/1/; s/<false\/>/0/') "$5"
            mkdir -p "${f%/*}" && printf '    %s =     {\n        enabled = %s;\n        value =         {\n            parameters =             (\n                %s,\n                %s,\n                %s\n            );\n            type = standard;\n        };\n    };\n' "$5" "$1" "$2" "$3" "$4" >> "$f"
            printf '%s %s %s %s\n' "$5" "$1" "$3" "$4" >> "$MD/hotkeys-written"
            exit 0
        fi
        case "$4 $5" in "-bool true") v=1 ;; "-bool false") v=0 ;; *) v="$5" ;; esac
        mkdir -p "${f%/*}" && printf '%s\n' "$v" > "$f"
        printf '%s %s %s\n' "$scope" "$2" "$3" >> "$MD/written" ;;
esac
EOF
printf '#!/bin/sh\nexit "$(cat "$MD/running")"\n' > "$md/bin/pgrep"
printf '#!/bin/sh\necho "$1" >> "$MD/killed"\n' > "$md/bin/killall"
printf '#!/bin/sh\necho "$1" >> "$MD/activated"\n' > "$md/bin/activateSettings"
cat > "$md/bin/hidutil" << 'EOF_HID'
#!/bin/bash
# Stub: hidutil property --get UserKeyMapping | --set JSON, the state in $MD/hidutil (hidutil's own text form).
case "$1 $2" in
    "property --get") cat "$MD/hidutil" ;;
    "property --set")
        [[ -e "$MD/hidutil_fail" ]] && exit 1
        echo "$3" >> "$MD/hidutil-set"
        src=$(printf '%s' "$3" | grep -oE '"HIDKeyboardModifierMappingSrc": *[0-9]+' | grep -oE '[0-9]+$')
        dst=$(printf '%s' "$3" | grep -oE '"HIDKeyboardModifierMappingDst": *[0-9]+' | grep -oE '[0-9]+$')
        printf 'RegistryID  Key                   Value\n10000075d   UserKeyMapping   (\n        {\n        HIDKeyboardModifierMappingDst = %s;\n        HIDKeyboardModifierMappingSrc = %s;\n    }\n)\n' "$dst" "$src" > "$MD/hidutil" ;;
esac
EOF_HID
printf '#!/bin/sh\n[ "$1" = print ] && [ -e "$MD/launchd/${2#system/}" ]\n' > "$md/bin/launchctl"
printf '#!/bin/sh\ncat "$MD/pmset"\n' > "$md/bin/pmset"
chmod +x "$md/bin/defaults" "$md/bin/pgrep" "$md/bin/killall" "$md/bin/launchctl" "$md/bin/pmset" "$md/bin/activateSettings" "$md/bin/hidutil"
render darwin "$md97" > "$md/script.sh"
md_reset() { # a Mac with Remote Login, Screen Sharing and wake for network access on AC
    rm -rf "$md/prefs" "$md/written" "$md/killed" "$md/fail_write" "$md/cache" "$md/launchd" "$md/hotkeys-written" "$md/activated" "$md/hidutil-set" "$md/hidutil_fail"; echo 0 > "$md/running"
    printf 'RegistryID  Key                   Value\n10000075d   UserKeyMapping   (null)\n' > "$md/hidutil"
    mkdir -p "$md/launchd" && touch "$md/launchd/com.openssh.sshd" "$md/launchd/com.apple.screensharing"
    printf 'Battery Power:\n sleep                1\n womp                 0\nAC Power:\n sleep                1\n womp                 1\n' > "$md/pmset"
}
md_run() { MD="$md" PATH="$md/bin:$PATH" ACTIVATE_SETTINGS="$md/bin/activateSettings" HIDUTIL="$md/bin/hidutil" CHEZMOI_CACHE_DIR="$md/cache" XDG_STATE_HOME="$md/state" bash "$md/script.sh" 2>&1; echo "exit=$?"; }
md_todo() { cat "$md/cache"/after-apply.* 2> /dev/null; }
md_set() { mkdir -p "$md/prefs/$1/$2" && printf '%s\n' "$4" > "$md/prefs/$1/$2/$3"; } # SCOPE DOMAIN KEY VALUE
md_reset
md_run > "$md/out"
check "macOS settings on a new Mac: writes every key whose unset value differs (30 of 43)" 30 "$(wc -l < "$md/written" | tr -d ' ')"
check "macOS settings on a new Mac: leaves keys that are already right when unset" 0 \
    "$(grep -cE ' (Dragging|DragLock|TrackpadThreeFingerDrag|TrackpadFiveFingerPinchGesture|AppleInterfaceStyleSwitchesAutomatically|com.apple.swipescrolldirection|ShowExternalHardDrivesOnDesktop)$' "$md/written")"
check "macOS settings on a new Mac: restarts the Dock, Finder and Control Center" "Dock|Finder|ControlCenter" "$(paste -sd'|' - < "$md/killed")"
check "macOS settings on a new Mac: says what it updated, and log out goes on the to-do list" "1|1|1|exit=0" \
    "$(grep -c '^OK:   macOS settings updated: autohide, autohide-delay, ' "$md/out")|$(grep -c '; restarted Dock, Finder, ControlCenter; apps pick up the title-bar, scroll-bar and key-repeat settings' "$md/out")|$(md_todo | grep -c '^Log out of macOS and back in')|$(tail -1 "$md/out")"
check "macOS settings on a new Mac: desktops keep their order; separate Spaces left as macOS's default" "1|0" \
    "$(grep -cx 'user com.apple.dock mru-spaces' "$md/written")|$(grep -c 'spans-displays' "$md/written")"
check "desktop shortcuts on a new Mac: Desktops 1-16 (ids 118-133) written once, enabled, settings activated once" "16|$(seq 118 133 | paste -sd' ' -)|16|1|1" \
    "$(awk '$1 >= 118' "$md/hotkeys-written" | wc -l | tr -d ' ')|$(awk '$1 >= 118 { print $1 }' "$md/hotkeys-written" | paste -sd' ' -)|$(awk '$1 >= 118 && $2 == 1' "$md/hotkeys-written" | wc -l | tr -d ' ')|$(wc -l < "$md/activated" | tr -d ' ')|$(grep -c '^OK:   macOS settings updated: .*desktop shortcuts' "$md/out")"
check "desktop shortcuts: when macOS cannot reload them, log out goes on the to-do list" "1|1" \
    "$(md_reset; printf '#!/bin/sh\nexit 1\n' > "$md/bin/activateSettings-fails"; chmod +x "$md/bin/activateSettings-fails"; MD="$md" PATH="$md/bin:$PATH" ACTIVATE_SETTINGS="$md/bin/activateSettings-fails" CHEZMOI_CACHE_DIR="$md/cache" XDG_STATE_HOME="$md/state" bash "$md/script.sh" 2>&1 | grep -c '^NOTE: macOS did not reload its keyboard shortcuts')|$(md_todo | grep -c 'Log out of macOS and back in, so the desktop shortcuts')"
md_reset
md_run > "$md/out"
check "desktop shortcuts use one hidden modifier mask and 16 different keys" "1|16" \
    "$(awk '$1 >= 118 { print $4 }' "$md/hotkeys-written" | sort -u | wc -l | tr -d ' ')|$(awk '$1 >= 118 { print $3 }' "$md/hotkeys-written" | sort -u | wc -l | tr -d ' ')"
check "Ctrl+Space input-source shortcut on a new Mac: turned off (id 60), said" "60 0 49 262144|1" \
    "$(grep '^60 ' "$md/hotkeys-written")|$(grep -c '^OK:   macOS settings updated: .*input-source shortcut off' "$md/out")"
check "macOS settings: per-machine keys go to -currentHost" "host com.apple.controlcenter BatteryShowPercentage|host com.apple.Spotlight MenuItemHidden" \
    "$(grep '^host ' "$md/written" | paste -sd'|' -)"
rm -f "$md/written" "$md/killed" "$md/hotkeys-written" "$md/activated" "$md/hidutil-set" "$md/cache"/after-apply.*
check "macOS settings: a second apply writes nothing and restarts nothing" "OK:   macOS settings match the repo|OK:   remote access: Remote Login, Screen Sharing, wake for network access on AC|exit=0|no|no|0" \
    "$(md_run | paste -sd'|' -)|$([[ -e "$md/written" ]] && echo yes || echo no)|$([[ -e "$md/killed" ]] && echo yes || echo no)|$(md_todo | wc -l | tr -d ' ')"
check "desktop shortcuts: a Mac that already has them writes none and activates nothing" "no|no" \
    "$([[ -e "$md/hotkeys-written" ]] && echo yes || echo no)|$([[ -e "$md/activated" ]] && echo yes || echo no)"
hk="$md/prefs/user/com.apple.symbolichotkeys/AppleSymbolicHotKeys"
sed -n '/^    120 = /,/^    };/p' "$hk" | sed -E 's/^( +)([0-9]+)$/\1999/' > "$md/hk120" # Desktop 3's mask changed by hand
cat "$md/hk120" >> "$hk"
check "desktop shortcuts: one entry with the wrong mask is rewritten alone, then activated" "120|1" \
    "$(md_run > /dev/null; cut -d' ' -f1 "$md/hotkeys-written" | paste -sd' ' -)|$(wc -l < "$md/activated" | tr -d ' ')"
rm -f "$md/written" "$md/killed" "$md/hotkeys-written" "$md/activated" "$md/cache"/after-apply.*
printf '    21 =     {\n        enabled = 1;\n    };\n' >> "$hk"
check "macOS Invert Colors on Ctrl+Option+Cmd+8 is named and goes on the to-do list" "1|1" \
    "$(md_run | grep -c "^NOTE: macOS's Invert Colors shortcut (Ctrl+Option+Cmd+8) takes the window key for desktop 8$")|$(md_todo | grep -c 'Accessibility > Invert colors')"
rm -f "$md/cache"/after-apply.*
printf '    21 =     {\n        enabled = 0;\n    };\n' >> "$hk"
check "macOS Invert Colors turned off: nothing said" "0|0" "$(md_run | grep -c 'Invert Colors')|$(md_todo | grep -c 'Invert colors')"
rm -f "$md/written" "$md/killed" "$md/hotkeys-written" "$md/activated" "$md/cache"/after-apply.*
md_set user com.apple.AppleMultitouchTrackpad Dragging 1
md_set user com.apple.dock autohide-time-modifier 0.150
check "macOS settings: tap-to-drag turned on is turned off again; a float equal as a number is left; no restart" \
    "user com.apple.AppleMultitouchTrackpad Dragging|0|no|1" \
    "$(md_run > /dev/null; cat "$md/written")|$(cat "$md/prefs/user/com.apple.AppleMultitouchTrackpad/Dragging")|$([[ -e "$md/killed" ]] && echo yes || echo no)|$(md_todo | grep -c '^Log out')"
rm -f "$md/written" "$md/cache"/after-apply.*
md_set user NSGlobalDomain com.apple.trackpad.scaling 2
md_set user com.apple.dock autohide 0
echo 1 > "$md/running"
check "macOS settings: a different value is written; nothing restarted while the Dock is not running" "2.5|1|no" \
    "$(md_run > /dev/null; cat "$md/prefs/user/NSGlobalDomain/com.apple.trackpad.scaling")|$(cat "$md/prefs/user/com.apple.dock/autohide")|$([[ -e "$md/killed" ]] && echo yes || echo no)"
md_reset
printf 'mineffect\n' > "$md/fail_write"
md_run > "$md/out"
check "macOS settings: a key that cannot be written is named and goes on the to-do list" "1|1|exit=0" \
    "$(grep -c '^NOTE: macOS settings could not be written: com.apple.dock mineffect$' "$md/out")|$(md_todo | grep -c 'com.apple.dock mineffect')|$(tail -1 "$md/out")"
check "macOS settings: Dock size and key repeat are set" 4 "$(grep -cE ' (tilesize|magnification|largesize|ApplePressAndHoldEnabled)$' "$md/written")"
check "macOS remote access: all on gives one OK line and no remote-access to-do" "1|0" \
    "$(grep -c '^OK:   remote access: Remote Login, Screen Sharing, wake for network access on AC$' "$md/out")|$(md_todo | grep -cE 'Remote Login|Screen Sharing|womp')"
md_reset
rm "$md/launchd/com.openssh.sshd"
sed -i.bak '/^AC Power:/,$ s/womp                 1/womp                 0/' "$md/pmset"
md_run > "$md/out"
check "macOS remote access: Remote Login off and no wake on AC are named and go on the to-do list, exit 0" \
    "1|1|1|0|exit=0" \
    "$(grep -c '^NOTE: remote access off on this Mac: Remote Login, wake for network access on AC$' "$md/out")|$(md_todo | grep -c 'System Settings > General > Sharing > Remote Login')|$(md_todo | grep -c 'sudo pmset -c womp 1')|$(md_todo | grep -c 'Screen Sharing')|$(tail -1 "$md/out")"
md_reset
rm "$md/launchd/com.apple.screensharing"
printf 'Battery Power:\n sleep                1\n' > "$md/pmset"
md_run > "$md/out"
check "macOS remote access: Screen Sharing off is listed; a Mac with no AC section is not judged on wake" "1|1|0" \
    "$(grep -c '^NOTE: remote access off on this Mac: Screen Sharing$' "$md/out")|$(md_todo | grep -c 'Remote Management (or Screen Sharing)')|$(md_todo | grep -c womp)"
it_reset
echo 0 > "$it/defaults/DoubleClickPerformsSmartSelection"
echo DoubleClickPerformsSmartSelection > "$it/fail_write"
it_out="$(iterm_after)"
check "iTerm2 script: a global it cannot write is named, goes on the to-do list, and the apply goes on" \
    "NOTE: iTerm2 global settings could not be written: DoubleClickPerformsSmartSelection|0|1|exit=0" \
    "$(printf '%s\n' "$it_out" | head -1)|$(printf '%s\n' "$it_out" | grep -c "global settings match")|$(it_todo | grep -c "Set iTerm2's global settings by hand")|$(printf '%s\n' "$it_out" | tail -1)"
it_reset
jq '.Profiles[0] += {"Font": "x"}' "$it_profile" > "$it/p.json" && mv "$it/p.json" "$it_profile"
mkdir -p "$it/nojq"
printf '#!/bin/sh\nexit 127\n' > "$it/nojq/jq"
chmod +x "$it/nojq/jq"
check "iTerm2 script: without a working jq, no local-changes line, the other three, exit 0" "3|0|exit=0" \
    "$(it_path="$it/nojq" iterm_after | grep -c '^OK: ')|$(it_path="$it/nojq" iterm_after | grep -c 'this Mac only')|$(it_path="$it/nojq" iterm_after | tail -1)"
it_reset
jq '.Profiles[0].Triggers += [{"regex": "x"}]' "$it_profile" > "$it/p.json" && mv "$it/p.json" "$it_profile"
check "iTerm2 script: a trigger without an action is named \"unnamed\"" 1 "$(iterm_after | grep -c 'not shared: trigger unnamed\.')"
it_reset
check "iTerm2 script: silent without iTerm2" "|exit=0" "$(it_app="$it/none" iterm_after | paste -sd'|' -)"
check "the iTerm2 script leaves Ctrl+Space to the macOS settings script" 0 "$(render darwin run_after_96_macos_iterm2.sh.tmpl | grep -c 'symbolichotkeys\|Select the previous input source')"

# Wave pane commands: only inside Wave (WAVETERM_BLOCKID set and wsh on PATH), in bash and zsh.
check "Wave pane commands are not defined outside Wave" "" "$(bash -c 'source dot_aliases; type -t wt wr wsplit wsr wsd 2> /dev/null')"
check "Wave pane commands are defined inside Wave (bash)" "function function function function function" \
    "$(PATH="$work/fakebin:$PATH" WAVETERM_BLOCKID=x bash -c 'mkdir -p "$0/fakebin"; printf "#!/bin/sh\n" > "$0/fakebin/wsh"; chmod +x "$0/fakebin/wsh"; source dot_aliases; type -t wt wr wsplit wsr wsd | xargs' "$work")"
if command -v zsh > /dev/null 2>&1; then
    check "Wave pane commands parse in zsh" "" "$(zsh -n dot_aliases 2>&1)"
fi

# with-op turns ./.op-env into --environment flags, dropping # comments, in bash and in the interactive zsh, which
# has EXTENDED_GLOB on (dot_zshrc.tmpl): there an unquoted # in a pattern is a glob operator and `#*` a bad pattern.
# A stub `op` prints the arguments it was given.
mkdir -p "$work/with-op/bin"
printf '#!/bin/sh\necho "$@"\n' > "$work/with-op/bin/op"
chmod +x "$work/with-op/bin/op"
printf '# first environment\nenv111 # inline comment\n  env222\n' > "$work/with-op/.op-env"
with_op_expected="run --no-masking --environment env111 --environment env222 -- true"
check "with-op reads .op-env (bash)" "$with_op_expected" \
    "$(cd "$work/with-op" && PATH="$work/with-op/bin:$PATH" bash -c 'source "$0"; with-op true' "$repo/dot_aliases" 2>&1)"
if command -v zsh > /dev/null 2>&1; then
    check "with-op reads .op-env (zsh with EXTENDED_GLOB)" "$with_op_expected" \
        "$(cd "$work/with-op" && PATH="$work/with-op/bin:$PATH" zsh -fc 'setopt EXTENDED_GLOB; source "$0"; with-op true' "$repo/dot_aliases" 2>&1)"
fi

# Agent aliases (o = with-op, y = no prompts, oy = both): defined only for installed tools. Stubs stand in for the
# agents; $work/agents/some holds only codex and agy. Each check sources dot_aliases in /bin/bash under its own PATH.
mkdir -p "$work/agents/bin" "$work/agents/some"
for agent in claude copilot cursor-agent cursor codex agy; do
    printf '#!/bin/sh\necho "$0 $*"\n' > "$work/agents/bin/$agent"
    chmod +x "$work/agents/bin/$agent"
done
cp "$work/agents/bin/codex" "$work/agents/bin/agy" "$work/agents/some/"
agent_aliases="cldo cldy cldoy cplo cply cploy csao csay csaoy csro cdxy agyy"
agent_shell() { # PATH, then the command body; the alias list arrives as $AGENT_ALIASES
    PATH="$1" AGENT_ALIASES="$agent_aliases" /bin/bash -c "source dot_aliases 2> /dev/null; $2"
}
check "agent aliases expand as designed" "alias cldo='with-op claude'
alias cldy='claude --dangerously-skip-permissions'
alias cldoy='with-op claude --dangerously-skip-permissions'
alias cplo='with-op copilot'
alias cply='copilot --yolo'
alias cploy='with-op copilot --yolo'
alias csao='with-op cursor-agent'
alias csay='cursor-agent --yolo'
alias csaoy='with-op cursor-agent --yolo'
alias csro='with-op cursor .'
alias cdxy='codex --dangerously-bypass-approvals-and-sandbox'
alias agyy='agy --dangerously-skip-permissions'" "$(agent_shell "$work/agents/bin:$PATH" 'alias $AGENT_ALIASES')"
check "only installed agents get aliases" "cdxy agyy" "$(agent_shell "$work/agents/some" 'out=; for n in $AGENT_ALIASES; do alias "$n" > /dev/null 2>&1 && out="$out $n"; done; echo "${out# }"')"
check "cld and csr are gone" "" "$(agent_shell "$work/agents/bin:$PATH" 'alias cld csr 2> /dev/null')"
check "codex and agy never run under with-op" "" "$(agent_shell "$work/agents/bin:$PATH" 'alias | grep -E "with-op (codex|agy)"')"

# with-op prints the command it runs, to a terminal only (the two checks above capture stderr and see nothing).
mkdir -p "$work/no-secrets"
op_p="PATH=$work/with-op/bin:$PATH"
op_line="→ op run --no-masking --environment env111 --environment env222 -- true"
stub_line="run --no-masking --environment env111 --environment env222 -- true"
tty_check "with-op echoes the op run command (bash)" "$op_line
$stub_line" "$work/with-op" env "$op_p" bash -c 'source "$0"; with-op true' "$repo/dot_aliases"
if command -v zsh > /dev/null 2>&1; then
    tty_check "with-op echoes the op run command (zsh EXTENDED_GLOB)" "$op_line
$stub_line" "$work/with-op" env "$op_p" zsh -fc 'setopt EXTENDED_GLOB; source "$0"; with-op true' "$repo/dot_aliases"
fi
tty_check "with-op says when no secrets load" "→ echo hi  (no .op-env or .env: no secrets)
hi" "$work/no-secrets" bash -c 'source "$0"; with-op echo hi' "$repo/dot_aliases"
tty_check "with-op quotes arguments with spaces" "$op_line fix\\ the\\ bug
$stub_line fix the bug" "$work/with-op" env "$op_p" bash -c 'source "$0"; with-op true "fix the bug"' "$repo/dot_aliases"
check "with-op passes the exit status through" 1 \
    "$(cd "$work/no-secrets" && bash -c 'source "$0"; with-op false; echo $?' "$repo/dot_aliases" 2>&1)"

# tat prints the tmux command it runs, to a terminal only.
mkdir -p "$work/tat/bin" "$work/tat/my.app"
printf '#!/bin/sh\nif [ "$1" = has-session ]; then exit "${STUB_TMUX_HAS:-1}"; fi\necho "tmux $*"\n' > "$work/tat/bin/tmux"
chmod +x "$work/tat/bin/tmux"
tat_dir="$work/tat/my.app"; tat="$repo/dot_local/bin/executable_tat"; tp="PATH=$work/tat/bin:$PATH"
check "tat is silent off a terminal" "tmux new-session -As my-app" "$(cd "$tat_dir" && env -u TMUX "$tp" sh "$tat" 2>&1)"
tty_check "tat echoes outside tmux" "→ tmux new-session -As my-app
tmux new-session -As my-app" "$tat_dir" env -u TMUX "$tp" sh "$tat"
tty_check "tat echoes create and switch inside tmux" "→ tmux new-session -Ad -s my-app
tmux new-session -Ad -s my-app
→ tmux switch-client -t my-app
tmux switch-client -t my-app" "$tat_dir" env TMUX=x STUB_TMUX_HAS=1 "$tp" sh "$tat"
check "tat is valid sh" "" "$(sh -n "$tat" 2>&1)"

# dkill prints each docker compose down it runs, to a terminal only.
mkdir -p "$work/dkill/bin" "$work/dkill/api" "$work/dkill/web" "$work/dkill/docs" "$work/dkill/my svc"
touch "$work/dkill/api/docker-compose.yml" "$work/dkill/web/docker-compose.yaml" "$work/dkill/my svc/docker-compose.yml"
printf '#!/bin/sh\necho "docker $* in $(basename "$PWD")"\n' > "$work/dkill/bin/docker"
chmod +x "$work/dkill/bin/docker"
dkill_out="docker compose down in api
docker compose down in my svc
docker compose down in web"
dp="PATH=$work/dkill/bin:$PATH"
check "dkill is silent off a terminal" "$dkill_out" \
    "$(cd "$work/dkill" && env "$dp" bash -c 'source "$0"; dkill' "$repo/dot_aliases" 2>&1)"
dkill_tty="→ (cd api/ && docker compose down)
docker compose down in api
→ (cd my\\ svc/ && docker compose down)
docker compose down in my svc
→ (cd web/ && docker compose down)
docker compose down in web"
tty_check "dkill echoes each folder (bash)" "$dkill_tty" "$work/dkill" env "$dp" bash -c 'source "$0"; dkill' "$repo/dot_aliases"
if command -v zsh > /dev/null 2>&1; then
    tty_check "dkill echoes each folder (zsh EXTENDED_GLOB)" "$dkill_tty" "$work/dkill" env "$dp" zsh -fc 'setopt EXTENDED_GLOB; source "$0"; dkill' "$repo/dot_aliases"
fi

# Omarchy setup beyond packages (.chezmoidata/omarchy.toml): dev-env runtimes and shell plugins by a run_onchange
# script, guides only reported (setup-guides). Nothing of it on other hosts.
render omarchy run_onchange_after_91_omarchy_setup.sh.tmpl > "$work/omarchy.setup"
# LunarVim's one-time link (link_lunarvim): scratch HOME, a stub lvim that logs, LVIM_SHARE pointed at a scratch dir.
sed -n '/^link_lunarvim() {/,/^}/p' "$work/omarchy.setup" > "$work/lvim.sh"
mkdir -p "$work/lv/bin" "$work/lv/share" "$work/lv/home"
printf '#!/bin/sh\necho "lvim $*" >> "$LV/log"\n' > "$work/lv/bin/lvim"
chmod +x "$work/lv/bin/lvim"
lvim_link() { LV="$work/lv" HOME="$work/lv/home" LVIM_SHARE="$work/lv/share" PATH="$work/lv/bin:$PATH" bash -c 'source "$0"; link_lunarvim' "$work/lvim.sh" 2>&1 | paste -sd'|' -; }
check "LunarVim: linked for you, commands printed, lvim run headless once" \
    "\$ mkdir -p $work/lv/home/.local/share/lunarvim|\$ ln -s $work/lv/share $work/lv/home/.local/share/lunarvim/lvim|\$ lvim --headless +qa|link|lvim --headless +qa" \
    "$(lvim_link)|$([[ -L "$work/lv/home/.local/share/lunarvim/lvim" ]] && echo link)|$(cat "$work/lv/log")"
rm -f "$work/lv/log"
check "LunarVim: already linked, nothing done" "|no-run" "$(lvim_link)|$([[ -e "$work/lv/log" ]] && echo ran || echo no-run)"
check "LunarVim: never its init-lvim.sh" 0 "$(grep -c 'init-lvim' "$work/lvim.sh")"
check "LunarVim: the setup script reaches the link (before its exit 0)" yes \
    "$(awk '/^    link_lunarvim$/ { call = NR } /^exit 0$/ { ex = NR } END { print (call && ex && call < ex) ? "yes" : "no" }' "$work/omarchy.setup")"
mkdir -p "$work/lv/home2/.local/share/lunarvim" && ln -s "$work/lv/missing" "$work/lv/home2/.local/share/lunarvim/lvim"
check "LunarVim: a dangling link counts as linked (no ln error)" "" \
    "$(LV="$work/lv" HOME="$work/lv/home2" LVIM_SHARE="$work/lv/share" PATH="$work/lv/bin:$PATH" bash -c 'source "$0"; link_lunarvim' "$work/lvim.sh" 2>&1)"

check "omarchy setup script is valid bash" "" "$(bash -n "$work/omarchy.setup" 2>&1)"
check "omarchy setup adds the three shell plugins" 3 "$(grep -cE '^    if omarchy plugin add "https://github.com/[^"]+" --yes; then$' "$work/omarchy.setup")"
check "omarchy setup turns off Omarchy's display widget for monitor-layout" 1 "$(grep -c 'omarchy plugin disable "omarchy.monitor"' "$work/omarchy.setup")"
check "omarchy setup installs dev-env only from a terminal" 1 "$(grep -c '^elif \[\[ -t 0 && -t 1 \]\]; then$' "$work/omarchy.setup")"
check "omarchy setup never applies guides" 0 "$(grep -cE 'apply\.sh' "$work/omarchy.setup")"
for host in darwin intel arch ubuntu; do
    check "$host gets no Omarchy setup script" "" "$(render "$host" run_onchange_after_91_omarchy_setup.sh.tmpl | tr -d '[:space:]')"
    check "$host gets no setup-guides" no "$(manages "$host" .local/bin/setup-guides)"
    check "$host requirement check has no Omarchy setup" 0 "$(render "$host" run_after_99_assert_requirements.sh.tmpl | grep -c 'setup-guides')"
done
check "omarchy gets setup-guides" yes "$(manages omarchy .local/bin/setup-guides)"
render omarchy dot_local/bin/executable_setup-guides.tmpl > "$work/setup-guides"
check "setup-guides is valid bash" "" "$(bash -n "$work/setup-guides" 2>&1)"
check "setup-guides lists the guides" 'guides=("zsh" "terminals-clipboard" "wave-keys" "window-rescue" "window-keys" "caps-prefix" )' "$(grep '^guides=' "$work/setup-guides")"
check "omarchy requirement check reports guides with setup-guides apply" 1 "$(render omarchy run_after_99_assert_requirements.sh.tmpl | grep -c 'Fix: setup-guides apply')"
check "omarchy packages include omarchy-zsh" 1 "$(render omarchy run_onchange_before_00_install_packages.sh.tmpl | grep -c '"omarchy-zsh"')"

# Ghostty's terminfo (xterm-ghostty) on every host: compiled from terminfo/ unless the system has its own copy.
for host in $hosts; do
    render "$host" run_onchange_after_92_ghostty_terminfo.sh.tmpl > "$work/$host.terminfo.sh"
    check "$host terminfo script is valid bash" "" "$(bash -n "$work/$host.terminfo.sh" 2>&1)"
    check "$host terminfo script carries the whole description" "$(grep -cv '^#' terminfo/xterm-ghostty.terminfo)" \
        "$(sed -n "/^cat > \"\$src\" << 'TERMINFO_EOF'$/,/^TERMINFO_EOF$/p" "$work/$host.terminfo.sh" | grep -cv -e '^#' -e 'TERMINFO_EOF')"
    check "$host terminfo script leaves a system copy alone" 1 "$(grep -c 'env -u TERMINFO -u TERMINFO_DIRS HOME=/nonexistent infocmp xterm-ghostty' "$work/$host.terminfo.sh")"
    check "$host does not deploy terminfo/" 0 "$(grep -c '^terminfo' "$work/$host.managed")"
    check "$host requirement check looks for xterm-ghostty" 1 "$(render "$host" run_after_99_assert_requirements.sh.tmpl | grep -c '^if infocmp xterm-ghostty > /dev/null 2>&1; then$')"
done
check "terminfo script re-runs when the description changes" 1 \
    "$(grep -c '^# terminfo hash: {{ include "terminfo/xterm-ghostty.terminfo" | sha256sum }}$' run_onchange_after_92_ghostty_terminfo.sh.tmpl)"
if command -v tic > /dev/null 2>&1; then
    ti="$work/terminfo"
    tic -x -o "$ti" terminfo/xterm-ghostty.terminfo 2> /dev/null
    check "terminfo/xterm-ghostty.terminfo compiles (256 colours)" 256 "$(TERMINFO="$ti" TERM=xterm-ghostty tput colors 2>&1)"
fi

# iTerm2 shell integration: macOS ~/.zshrc only, loaded from the app, only in iTerm2 and not in SSH sessions.
check "darwin ~/.zshrc loads iTerm2 shell integration only in iTerm2" 1 "$(grep -c 'TERM_PROGRAM:-}" == iTerm.app || "${LC_TERMINAL:-}" == iTerm2 ) && -z "${SSH_CONNECTION:-}"' "$work/darwin.zshrc")"
for host in omarchy arch ubuntu; do
    check "$host ~/.zshrc has no iTerm2 shell integration" 0 "$(grep -c 'iterm2_shell_integration' "$work/$host.zshrc")"
done

# herdr opens zsh in new panes on every host.
check "darwin herdr default shell is /bin/zsh" 1 "$(render darwin dot_config/herdr/config.toml.tmpl | grep -cx 'default_shell = "/bin/zsh"')"
check "omarchy herdr default shell is /usr/bin/zsh" 1 "$(render omarchy dot_config/herdr/config.toml.tmpl | grep -cx 'default_shell = "/usr/bin/zsh"')"

# New Omarchy machine: one bootstrap command (bootstrap/omarchy.sh), kept in the repository, never deployed to $HOME.
for host in $hosts; do
    check "$host does not deploy bootstrap/" 0 "$(grep -c '^bootstrap' "$work/$host.managed")"
done
check "bootstrap/omarchy.sh is valid bash" "" "$(bash -n bootstrap/omarchy.sh 2>&1)"
if command -v shellcheck > /dev/null 2>&1; then
    check "bootstrap/omarchy.sh passes shellcheck" "" "$(shellcheck -S warning bootstrap/omarchy.sh 2>&1)"
fi
for b in omarchy macos; do
    check "bootstrap/$b.sh reads the installer first and stops loudly without it, or when the clone fails" "1 1 1" \
        "$(grep -cF 'installer="$(git --git-dir="$HOME/.cfg" show HEAD:guides/install.sh 2> /dev/null)" || die' bootstrap/$b.sh) $(grep -cF 'run git clone --bare "$CFG_SSH" "$HOME/.cfg" || die' bootstrap/$b.sh) $(grep -cF 'bash <(printf '"'"'%s\n'"'"' "$installer") || echo "    The installer reported a step that failed (above); fix it, then run this bootstrap again."' bootstrap/$b.sh)"
done
check "bootstrap/omarchy.sh prints the installer line readably (not /dev/fd)" 1 \
    "$(grep -cF "printf '    \$ bash <(git --git-dir=%s/.cfg show HEAD:guides/install.sh)" bootstrap/omarchy.sh)"
check "bootstrap/omarchy.sh prints each command it runs (run helper)" "1 1 1" \
    "$(grep -c '^run() {' bootstrap/omarchy.sh) $(grep -c '^run omarchy pkg add chezmoi git$' bootstrap/omarchy.sh) $(grep -c '^    run git clone --bare' bootstrap/omarchy.sh)"
check "bootstrap/omarchy.sh leaves the .cfg settings and guides to the installer" 0 \
    "$(grep -cE 'setup-guides\" apply|config status.showUntrackedFiles|set-upstream-to' bootstrap/omarchy.sh)"
# New Mac: bootstrap/macos.sh, run with stand-ins (uname, xcode-select, brew, curl, chezmoi, ssh, git, ssh-key-remember)
# in a scratch HOME; BREW_PREFIX points at a scratch Homebrew; BOOTSTRAP_ASSUME_TTY stands in for a terminal.
check "bootstrap/macos.sh is valid bash" "" "$(bash -n bootstrap/macos.sh 2>&1)"
if command -v shellcheck > /dev/null 2>&1; then
    check "bootstrap/macos.sh passes shellcheck" "" "$(shellcheck -S warning bootstrap/macos.sh 2>&1)"
fi
bm="$work/bm"
bm_reset() { # bm_reset [nokey]: a Mac with the Command Line Tools and Homebrew, and the SSH key unless nokey
    rm -rf "$bm"; mkdir -p "$bm/bin" "$bm/home/.ssh" "$bm/home/.local/bin" "$bm/brew/bin"
    [[ "${1:-}" == nokey ]] || touch "$bm/home/.ssh/id_rsa"
    printf '#!/bin/sh\nprintf "export PATH=%s/brew/bin:\\$PATH\\n"\n' "$bm" > "$bm/brew/bin/brew"
    printf '#!/bin/sh\ncase "$1" in -s) echo "${UNAME_S:-Darwin}" ;; -m) echo "${UNAME_M:-arm64}" ;; esac\n' > "$bm/bin/uname"
    printf '#!/bin/sh\n[ "$1" = -p ] && { echo /Library/Developer/CommandLineTools; exit 0; }\necho "xcode-select $*" >> "$BM/log"\n' > "$bm/bin/xcode-select"
    printf '#!/bin/sh\necho "chezmoi $*" >> "$BM/log"\nmkdir -p "$HOME/.local/share/chezmoi/.git"\n' > "$bm/bin/chezmoi"
    printf '#!/bin/sh\necho "Hi! You'"'"'ve successfully authenticated, but GitHub does not provide shell access."\n' > "$bm/bin/ssh"
    printf '#!/bin/sh\necho "ssh-key-remember" >> "$BM/log"\n' > "$bm/home/.local/bin/ssh-key-remember"
    cat > "$bm/bin/git" << 'EOF_GIT'
#!/bin/bash
case " $* " in
  *" show HEAD:guides/install.sh "*) echo 'echo "installer ran" >> "$BM/log"' ;;
  *" clone --bare "*) echo "git $*" >> "$BM/log"; mkdir -p "$HOME/.cfg" ;;
  *) echo "git $*" >> "$BM/log" ;;
esac
EOF_GIT
    chmod +x "$bm/bin/"* "$bm/brew/bin/brew" "$bm/home/.local/bin/ssh-key-remember"
}
macboot() { BM="$bm" HOME="$bm/home" BREW_PREFIX="$bm/brew" PATH="$bm/bin:/usr/bin:/bin" bash bootstrap/macos.sh "$@" 2>&1; echo "exit=$?"; }
bm_reset
check "bootstrap/macos.sh on an Intel Mac stops, pointing to INTEL_MACS.md, nothing run" "1|exit=1|no-log" \
    "$(UNAME_M=x86_64 BOOTSTRAP_ASSUME_TTY=1 macboot | grep -c 'docs/INTEL_MACS.md')|$(UNAME_M=x86_64 BOOTSTRAP_ASSUME_TTY=1 macboot | tail -1)|$([[ -e "$bm/log" ]] && echo logged || echo no-log)"
check "bootstrap/macos.sh off macOS stops" "exit=1" "$(UNAME_S=Linux BOOTSTRAP_ASSUME_TTY=1 macboot | tail -1)"
bm_reset nokey
check "bootstrap/macos.sh without the SSH key: stops before chezmoi, naming the copy command, nothing run" "1|exit=1|no-log" \
    "$(BOOTSTRAP_ASSUME_TTY=1 macboot > "$bm/out"; grep -c 'install -m 600 <copy>/id_rsa' "$bm/out")|$(tail -1 "$bm/out")|$([[ -e "$bm/log" ]] && echo logged || echo no-log)"
bm_reset
BOOTSTRAP_ASSUME_TTY=1 macboot > "$bm/out"
check "bootstrap/macos.sh: chezmoi, SSH remote, passphrase, .cfg clone, installer, in that order" \
    "chezmoi|git -C|ssh-key-remember|git clone --bare|installer ran|chezmoi|exit=0" \
    "$(cut -d' ' -f1-2 "$bm/log" | sed -E 's/^(chezmoi|ssh-key-remember|installer ran).*/\1/; s/^git (-C|clone).*/git \1/; s/^git clone$/git clone --bare/' | paste -sd'|' -)|$(tail -1 "$bm/out")"
check "bootstrap/macos.sh prints each command before it runs" "1 1 1 1" \
    "$(grep -c '^    \$ git -C .* remote set-url origin git@github.com:simars/dotfiles.git' "$bm/out") $(grep -c '^    \$ .*ssh-key-remember' "$bm/out") $(grep -c '^    \$ git clone --bare git@github.com:simars/.cfg.git' "$bm/out") $(grep -c '^    \$ bash <(git --git-dir=.*/.cfg show HEAD:guides/install.sh)' "$bm/out")"
bm_reset
check "bootstrap/macos.sh without a terminal lists the steps and changes nothing" "no-log|exit=0|1" \
    "$(macboot < /dev/null > "$bm/out"; [[ -e "$bm/log" ]] && echo logged || echo no-log)|$(tail -1 "$bm/out")|$(grep -c 'run it in a terminal' "$bm/out")"
check "bootstrap refuses to run without a terminal" 1 "$(bash bootstrap/omarchy.sh < /dev/null > /dev/null 2>&1; echo $?)"
check "omarchy setup runs the Tailscale and 1Password installers" 2 "$(grep -cE '^        omarchy install service (tailscale|1password) ' "$work/omarchy.setup")"
check "omarchy packages include the declared apps" 6 "$(render omarchy run_onchange_before_00_install_packages.sh.tmpl | grep -oE '"(chezmoi|claude-desktop|cursor-bin|google-chrome|slack-desktop|visual-studio-code-bin)"' | sort -u | wc -l | tr -d ' ')"

# kitty and Ghostty: copy on select everywhere, Option as Alt on macOS, as one-key edits of the apps' own files; the
# Herdr desktop app gets Option as Alt on macOS. Macs and Omarchy only (where they are installed).
for host in darwin omarchy; do
    check "$host manages kitty.conf" yes "$(manages "$host" .config/kitty/kitty.conf)"
    check "$host manages Ghostty's config" yes "$(manages "$host" .config/ghostty/config)"
done
for host in arch ubuntu; do
    check "$host leaves kitty and Ghostty alone" "no no" "$(manages "$host" .config/kitty/kitty.conf) $(manages "$host" .config/ghostty/config)"
done
check "darwin manages the Herdr app's settings" yes "$(manages darwin .config/herdr-app/settings.json)"
check "omarchy leaves the Herdr app's settings alone" no "$(manages omarchy .config/herdr-app/settings.json)"
# Hammerspoon's window rescue (Cmd+Ctrl+U): every Mac, no Linux host.
for host in darwin intel; do
    check "$host manages Hammerspoon's window rescue" "yes yes" "$(manages "$host" .hammerspoon/init.lua) $(manages "$host" .hammerspoon/window_rescue.lua)"
done
for host in omarchy arch ubuntu debian; do
    check "$host leaves ~/.hammerspoon alone" no "$(manages "$host" .hammerspoon/init.lua)"
done
check "darwin installs the hand-installed apps and gh with Homebrew" 7 \
    "$(render darwin run_onchange_before_00_install_packages.sh.tmpl | grep -cxE 'cask "(1password|claude|google-chrome|slack|visual-studio-code|cursor)"|brew "gh"')"
# Adopting apps already in /Applications (adopt-casks.sh): a stub brew logs its arguments; APPS_DIR is a scratch folder.
ad="$work/adopt"
mkdir -p "$ad/bin" "$ad/Applications"
printf '#!/bin/sh\n[ "$1" = list ] && { cat "$AD/brew-has" 2>/dev/null; exit 0; }\necho "$*" >> "$AD/brew-log"\n' > "$ad/bin/brew"
chmod +x "$ad/bin/brew"
render darwin run_onchange_before_00_install_packages.sh.tmpl > /dev/null
chezmoi --override-data "$(host_data darwin)" execute-template '{{ template "adopt-casks.sh" . }}' > "$ad/adopt.sh" 2>&1
adopt() { AD="$ad" PATH="$ad/bin:$PATH" bash -c 'source "$0"; adopt_casks "$1"; echo "skipped=[$skipped_casks]"' "$ad/adopt.sh" "$ad/Applications" 2>&1 | paste -sd'|' -; }
mkdir -p "$ad/Applications/Google Chrome.app/Contents"
check "adopt: a hand-installed app is adopted, its command printed first" \
    '$ brew install --cask --adopt google-chrome|skipped=[]|install --cask --adopt google-chrome' "$(adopt)|$(cat "$ad/brew-log")"
rm -rf "$ad/Applications/"* "$ad/brew-log"
mkdir -p "$ad/Applications/Slack.app/Contents/_MASReceipt"
check "adopt: an App Store app is skipped, named, and left out of the Brewfile" \
    'skipped: Slack.app is from the App Store; Homebrew leaves it alone|skipped=[slack]|no-log' "$(adopt)|$([[ -e "$ad/brew-log" ]] && echo logged || echo no-log)"
rm -rf "$ad/Applications/"*
mkdir -p "$ad/Applications/Visual Studio Code.app/Contents"
echo visual-studio-code > "$ad/brew-has"
check "adopt: an app Homebrew already has, or one not installed, is left to brew bundle" "skipped=[]|no-log" \
    "$(adopt)|$([[ -e "$ad/brew-log" ]] && echo logged || echo no-log)"
# The requirement check names an app Homebrew should have but does not manage (a failed adoption), never an App Store
# one: check_casks, extracted from the rendered darwin script, with the same stub brew and scratch APPS_DIR.
render darwin run_after_99_assert_requirements.sh.tmpl | sed -n '/^check_casks() {/,/^}/p' > "$ad/check.sh"
check_casks_out() { AD="$ad" PATH="$ad/bin:$PATH" bash -c 'note() { echo "NOTE: $1"; }; source "$0"; check_casks "$1"' "$ad/check.sh" "$ad/Applications" 2>&1 | paste -sd'|' -; }
rm -rf "$ad/Applications/"* "$ad/brew-has"; mkdir -p "$ad/Applications/Cursor.app/Contents" "$ad/Applications/Slack.app/Contents/_MASReceipt"
check "requirement check: an app Homebrew does not manage goes on the to-do list with the fix; App Store ones never" \
    "NOTE: Cursor.app is not managed by Homebrew (taking it over failed?). Fix: brew install --cask --adopt cursor" "$(check_casks_out)"
echo cursor > "$ad/brew-has"
check "requirement check: managed apps say nothing" "" "$(check_casks_out)"
check "only Apple-silicon Macs check the casks" "1 0" \
    "$(render darwin run_after_99_assert_requirements.sh.tmpl | grep -c '^check_casks /Applications$') $(render intel run_after_99_assert_requirements.sh.tmpl | grep -c '^check_casks /Applications$')"
check "the package script drops skipped casks from the Brewfile" 1 \
    "$(render darwin run_onchange_before_00_install_packages.sh.tmpl | grep -c 'drop_casks "$brewfile" $skipped_casks')"
check "darwin casks include Hammerspoon" 1 "$(render darwin run_onchange_before_00_install_packages.sh.tmpl | grep -cx 'cask "hammerspoon"')"
check "the Mac requirement check names Hammerspoon; only Intel points to INTEL_MACS.md" "1 0 1" \
    "$(render darwin run_after_99_assert_requirements.sh.tmpl | grep -c 'cask hammerspoon"$') $(render darwin run_after_99_assert_requirements.sh.tmpl | grep -c 'hammerspoon (docs/INTEL_MACS.md)') $(render intel run_after_99_assert_requirements.sh.tmpl | grep -c 'hammerspoon (docs/INTEL_MACS.md)')"
check "the Mac requirement check names all Hammerspoon runs: window keys, Caps Lock prefix, window rescue" 3 \
    "$(render darwin run_after_99_assert_requirements.sh.tmpl | grep -c 'window keys, the Caps Lock prefix and the Cmd+Ctrl+U window rescue')"
# Hammerspoon opened once after install (check_hammerspoon): stubs open and pgrep, HAMMERSPOON_APP and XDG_STATE_HOME
# pointed at scratch dirs.
render darwin run_after_99_assert_requirements.sh.tmpl | sed -n '/^check_hammerspoon() {/,/^}/p' > "$work/hs.sh"
hsd="$work/hsd"
mkdir -p "$hsd/bin" "$hsd/Hammerspoon.app"
printf '#!/bin/sh\necho "open $*" >> "$HSD/log"\n' > "$hsd/bin/open"
printf '#!/bin/sh\nexit "$(cat "$HSD/running")"\n' > "$hsd/bin/pgrep"
printf '#!/bin/sh\necho "xattr $*" >> "$HSD/log"\n' > "$hsd/bin/xattr"
chmod +x "$hsd/bin/"*
hs_check() { HSD="$hsd" HAMMERSPOON_APP="$hsd/Hammerspoon.app" XDG_STATE_HOME="$hsd/state" PATH="$hsd/bin:$PATH" bash -c 'note() { echo "NOTE: $1"; }; source "$0"; check_hammerspoon' "$work/hs.sh" 2>&1 | paste -sd'|' -; }
echo 1 > "$hsd/running"
check "Hammerspoon installed, never opened: opened once, command printed, the note says what to click" "1|1|open -a $hsd/Hammerspoon.app" \
    "$(hs_check > "$hsd/out"; grep -c "^\\$ open -a $hsd/Hammerspoon.app" "$hsd/out")|$(grep -c 'choose Open' "$hsd/out")|$(cat "$hsd/log")"
rm -f "$hsd/log"
check "Hammerspoon opened before and still not running: not opened again, only the note" "1|no-open" \
    "$(hs_check | grep -c '^NOTE: Hammerspoon is installed but not running')|$([[ -e "$hsd/log" ]] && echo opened || echo no-open)"
echo 0 > "$hsd/running"
check "Hammerspoon running: OK, nothing opened, never xattr" "1|no-open" \
    "$(hs_check | grep -c '^OK:   Hammerspoon is running')|$([[ -e "$hsd/log" ]] && echo opened || echo no-open)"
check "Linux requirement checks never mention Hammerspoon" "0 0" \
    "$(render omarchy run_after_99_assert_requirements.sh.tmpl | grep -ci hammerspoon.app) $(render ubuntu run_after_99_assert_requirements.sh.tmpl | grep -ci hammerspoon.app)"
if command -v luac > /dev/null 2>&1; then
    check "Hammerspoon's Lua files compile" ok "$(luac -p dot_hammerspoon/*.lua 2>&1 && echo ok)"
fi
# Caps Lock as F18 is Hammerspoon's to set (window_keys.lua) while it runs: no login agent, and the macOS settings
# script never sets it, so Caps Lock is never a dead key while Hammerspoon is not running.
check "no Mac gets a Caps Lock login agent" "no no" "$(manages darwin Library/LaunchAgents/dotfiles.caps-lock-f18.plist) $(manages intel Library/LaunchAgents/dotfiles.caps-lock-f18.plist)"
check "the macOS settings script never sets the Caps Lock remap" 0 "$(render darwin run_after_97_macos_defaults.sh.tmpl | grep -c 'hidutil')"
# Window keys (Ctrl+Option+Cmd): every Mac, no Linux host; a template fed by .chezmoidata/macos.toml.
for host in darwin intel; do
    check "$host manages the window keys" yes "$(manages "$host" .hammerspoon/window_keys.lua)"
done
for host in omarchy arch ubuntu debian; do
    check "$host has no window keys" no "$(manages "$host" .hammerspoon/window_keys.lua)"
done
render darwin dot_hammerspoon/window_keys.lua.tmpl > "$work/wk.lua"
lua_bin="$(command -v lua5.4 || command -v lua || true)"
luac_bin="$(command -v luac5.4 || command -v luac || true)"
if [[ -n "${CI:-}" ]]; then
    check "CI has lua and luac for the window-keys tests" "yes yes" "$([[ -n "$lua_bin" ]] && echo yes || echo no) $([[ -n "$luac_bin" ]] && echo yes || echo no)"
fi
check "the hidden mask is the sum of the hidden modifiers" "$(chezmoi execute-template '{{ .desktop_shortcuts.mask }}')" \
    "$(chezmoi execute-template '{{ range .desktop_shortcuts.hs_modifiers }}{{ . }} {{ end }}' | awk '{ for (i = 1; i <= NF; i++) s += ($i == "cmd" ? 1048576 : $i == "ctrl" ? 262144 : $i == "alt" ? 524288 : $i == "shift" ? 131072 : 1e9) } END { print s }')"
check "window keys bind on Ctrl+Option+Cmd" 1 "$(grep -cxF 'local PREFIX = { "cmd", "ctrl", "alt" }' "$work/wk.lua")"
check "init.lua never asks for Accessibility (macOS 27 shows the dialog on every reload, even when allowed)" 0 \
    "$(grep -c 'accessibilityState' dot_hammerspoon/init.lua)"
check "init.lua starts the window keys right after the rescue" 'require("window_keys").start()' \
    "$(grep -A1 -xF 'require("window_rescue").start()' dot_hammerspoon/init.lua | tail -1)"
if [[ -n "$luac_bin" ]]; then
    check "window keys render and compile" ok "$("$luac_bin" -p "$work/wk.lua" 2>&1 && echo ok)"
fi
if [[ -n "$lua_bin" ]]; then
    # globalDesktop: macOS numbers desktops across screens in Mission Control's order; full-screen apps (type 4) are
    # not desktops; the main display may be listed as "Main"; macOS has shortcuts for Desktop 1-16 only.
    check "window keys: hidden desktop keys (by key code) and modifiers come from macos.toml" "16|18 19 29 39|ctrl alt shift" "$("$lua_bin" - "$work/wk.lua" << 'EOF_LUA'
hs = {}
local M = dofile(arg[1])
io.write(#M.HIDDEN.keys, "|", M.HIDDEN.keys[1], " ", M.HIDDEN.keys[2], " ", M.HIDDEN.keys[10], " ", M.HIDDEN.keys[16], "|", table.concat(M.HIDDEN.mods, " "))
EOF_LUA
)"
    check "window keys: per-screen desktop N to macOS's global Desktop number" \
        "2 8 6|10 2 98|nil 2 nil|1 8 1|nil 8 nil|16 8 306" "$("$lua_bin" - "$work/wk.lua" << 'EOF_LUA'
hs = {}
local M = dofile(arg[1])
local function display(id, ids)
  local spaces = {}
  for _, x in ipairs(ids) do spaces[#spaces + 1] = { ManagedSpaceID = math.abs(x), type = x < 0 and 4 or 0 } end
  return { ["Display Identifier"] = id, Spaces = spaces }
end
local laptop = { 1, 6, 8, 4, 7, 5, 9, 10 }
local d = { display("A", laptop), display("B", { 89, -200, 98 }) }
local main = { display("Main", laptop), display("B", { 89, 98 }) }
local three = { display("A", laptop), display("B", { 89, 98 }), display("C", { 301, 302, 303, 304, 305, 306, 307, 308 }) }
local out = {}
local function add(...) local r = table.pack(...); out[#out + 1] = tostring(r[1]) .. " " .. tostring(r[2]) .. " " .. tostring(r[3]) end
add(M.globalDesktop(d, "A", true, 2))
add(M.globalDesktop(d, "B", false, 2))
add(M.globalDesktop(d, "B", false, 3))
add(M.globalDesktop(main, "A", true, 1))
add(M.globalDesktop(three, "C", false, 7))
add(M.globalDesktop(three, "C", false, 6))
io.write(table.concat(out, "|"))
EOF_LUA
)"
    # Caps Lock (F18) as a one-key prefix: M.capsKey(kind, key, shift, isRepeat, now) -> action, consume. Each step is
    # "kind:key[:shift][:repeat][@seconds]" (time defaults to 50 ms after the step before); the result lists each
    # step's action (or -) and c/p (consumed/passed).
    caps() { "$lua_bin" - "$work/wk.lua" "$@" << 'EOF_LUA'
hs = {}
local M = dofile(arg[1])
local out, t = {}, 0
for i = 2, #arg do
  local step, at = arg[i]:match("^([^@]+)@?(.*)$")
  t = at ~= "" and tonumber(at) or t + 0.05
  local kind, key, a, b = step:match("^(%a+):([^:]+):?(%a*):?(%a*)$")
  local action, consume = M.capsKey(kind, key, a == "shift" or b == "shift", a == "repeat" or b == "repeat", t)
  out[#out + 1] = (action or "-") .. "/" .. (consume and "c" or "p")
end
io.write(table.concat(out, " "))
EOF_LUA
    }
    check "caps: a lone tap toggles capitals" "-/c toggle-caps/c" "$(caps down:f18 up:f18)"
    check "caps: auto-repeat while held still toggles once" "-/c -/c -/c toggle-caps/c" "$(caps down:f18 down:f18:repeat down:f18:repeat up:f18)"
    check "caps: held with a window key focuses and never toggles" "-/c focus left/c -/c -/c" "$(caps down:f18 down:left up:left up:f18)"
    check "caps: Shift+arrow swaps, digits go and send, L tiles, U rescues" "-/c swap right/c go 3/c send 3/c tile/c rescue/c -/c -/c" \
        "$(caps down:f18 down:right:shift down:3 down:3:shift down:l down:u down:a up:f18)"
    check "caps: outside the layer nothing is touched" "-/p -/p" "$(caps down:left up:left)"
    check "caps: a held arrow's auto-repeat keeps moving focus" "-/c focus left/c focus left/c" "$(caps down:f18 down:left down:left:repeat)"
    check "caps: auto-repeat never repeats go, send, tile or rescue" "-/c go 3/c -/c send 3/c -/c tile/c -/c" \
        "$(caps down:f18 down:3 down:3:repeat down:3:shift down:3:shift:repeat down:l down:l:repeat)"
    check "caps: a key pressed before Caps is released normally" "-/p -/c -/p" "$(caps down:h down:f18 up:h)"
    check "caps: a window key held past Caps's release stays swallowed until it comes up" "-/c focus left/c -/c -/c -/c" \
        "$(caps down:f18 down:left up:f18 down:left:repeat up:left)"
    check "caps: rolling fast from Caps onto a letter is a Caps tap, and the letter is typed" "-/c toggle-caps/p -/c -/p" \
        "$(caps down:f18@0 down:n@0.1 up:f18@0.15 up:n@0.2)"
    check "caps: a letter while Caps is really held does nothing" "-/c -/c -/c" "$(caps down:f18@0 down:a@0.5 up:a@0.6)"
    check "caps: a layer stuck after a missed Caps release lets typing through after 3 s" "-/c -/p" "$(caps down:f18@0 down:a@5)"
    # Send and go to desktop under a stand-in Hammerspoon (tests/hammerspoon-stub.lua): key codes, never key names;
    # the mouse button always comes back up; nothing is clicked while keys are held or on a button.
    stub() { "$lua_bin" tests/hammerspoon-stub.lua "$work/wk.lua" "$1"; }
    check "send: waits for released keys, holds the title bar, presses Desktop 2 by key code, lets go, mouse back" \
        "move | mouse-down | mouse-drag | key-down 19 ctrl+alt+shift tagged | key-up 19 ctrl+alt+shift tagged | mouse-up | move" "$(stub send)"
    check "send: keys still held after 2 s: refused, nothing clicked" "alert: Let go of the keys to send the window" "$(stub held)"
    check "send: the grab spot is a button: refused, nothing clicked" \
        "alert: No empty title-bar spot to hold this window by (hammerspoon://window-keys-probe)" "$(stub button)"
    check "send: a failing key press still lets go of the mouse button" "move | mouse-down | mouse-drag | mouse-up | move | alert: Could not press macOS's desktop shortcut" "$(stub key-fails)"
    remap='/usr/bin/hidutil property --set {"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":30064771129,"HIDKeyboardModifierMappingDst":30064771181}]}'
    clear='/usr/bin/hidutil property --set {"UserKeyMapping":[]}'
    check "Hammerspoon owns the Caps Lock remap: set at start, after a USB device, wake and unlock; cleared when it quits" \
        "$remap | $remap | $remap | $remap | $clear" "$(stub remap-watch)"
    check "go: presses Desktop 2 by key code at once, while the prefix is still held" "key-down 19 ctrl+alt+shift tagged | key-up 19 ctrl+alt+shift tagged" "$(stub go-held)"
    check "go: keys held for good: still presses, no refusal" "key-down 19 ctrl+alt+shift tagged | key-up 19 ctrl+alt+shift tagged" "$(stub go-held-long)"
fi
kv() { render "$1" "$2" > "$work/kv.sh"; printf '%b' "$3" | bash "$work/kv.sh" | grep -v '^# Set by chezmoi' | paste -sd'|' -; }
check "kitty on macOS: keeps the rest, sets copy on select and left Option as Alt" "include t.conf|font_size 11||copy_on_select clipboard|macos_option_as_alt left" \
    "$(kv darwin dot_config/kitty/modify_kitty.conf.tmpl 'include t.conf\ncopy_on_select no\nfont_size 11\n')"
check "kitty on Omarchy: copy on select only" "include t.conf||copy_on_select clipboard" "$(kv omarchy dot_config/kitty/modify_kitty.conf.tmpl 'include t.conf\n')"
check "Ghostty on macOS: copy on select and left Option as Alt, comments kept" "# copy-on-select = false|font-size = 11||copy-on-select = clipboard|macos-option-as-alt = left|confirm-close-surface = true" \
    "$(kv darwin dot_config/ghostty/modify_config.tmpl '# copy-on-select = false\ncopy-on-select = true\nfont-size = 11\n' | tr '|' '\n' | grep -vE '^keybind = (cmd\+b|term|chain=)' | paste -sd'|' -)"
render omarchy dot_config/ghostty/modify_config.tmpl > "$work/ghostty.sh"
check "Ghostty: second run changes nothing" "$(printf 'a = 1\n' | bash "$work/ghostty.sh")" "$(printf 'a = 1\n' | bash "$work/ghostty.sh" | bash "$work/ghostty.sh")"
# Ghostty on Omarchy gives Ctrl+Enter (Claude Code), Alt+1..9 and Ctrl+Alt+arrows (Herdr) to the program; a keybind
# line is matched by its trigger, so Omarchy's other bindings stay.
ghostty_out="$(printf 'keybind = shift+enter=csi:13;2u\nkeybind = ctrl+enter=toggle_fullscreen\n' | bash "$work/ghostty.sh")"
check "Ghostty on Omarchy: Omarchy's own key bindings kept" 1 "$(grep -cxF 'keybind = shift+enter=csi:13;2u' <<< "$ghostty_out")"
check "Ghostty on Omarchy: one Ctrl+Enter line, handed to the program" "keybind = ctrl+enter=unbind" "$(grep -F 'ctrl+enter' <<< "$ghostty_out")"
check "Ghostty on Omarchy: Alt+1..9 (both forms) and Ctrl+Alt+arrows handed to the program" "18 4" \
    "$(grep -cE '^keybind = alt\+(digit_)?[1-9]=unbind$' <<< "$ghostty_out") $(grep -cE '^keybind = ctrl\+alt\+arrow_(up|down|left|right)=unbind$' <<< "$ghostty_out")"
check "Ghostty on Omarchy: second run changes nothing, key bindings included" "$ghostty_out" "$(bash "$work/ghostty.sh" <<< "$ghostty_out")"
check "Ghostty on macOS: keys left to Ghostty (it uses Cmd)" 0 "$(render darwin dot_config/ghostty/modify_config.tmpl > "$work/ghostty-mac.sh"; printf 'a = 1\n' | bash "$work/ghostty-mac.sh" | grep -c '^keybind = [^t].*=unbind')"
# The terminal leader: Cmd-b (macOS) / Super-b (Omarchy), then tmux's letters for Ghostty's own tabs and splits.
ghostty_lead="$(printf 'config-file = ?"~/.local/state/omarchy/current/theme/ghostty.conf"\nconfirm-close-surface=false\nkeybind = shift+enter=csi:13;2u\n' | bash "$work/ghostty.sh")"
check "Ghostty on Omarchy: Super-b opens the term table" 1 "$(grep -cxF 'keybind = super+b=activate_key_table:term' <<< "$ghostty_lead")"
check "Ghostty on Omarchy: any other key after the leader closes it, swallowed" 1 "$(grep -cxF 'keybind = term/catch_all=deactivate_key_table' <<< "$ghostty_lead")"
# A bare Shift press is a key event too: it must not reach catch_all and close the table before Shift+5 (%) arrives.
check "Ghostty on Omarchy: bare Shift presses keep the leader open" 4 "$(grep -cxE 'keybind = term/(shift\+)?shift_(left|right)=ignore' <<< "$ghostty_lead")"
check "Ghostty on Omarchy: bare Alt / Option presses keep the leader open for Alt+arrows" 4 "$(grep -cxE 'keybind = term/(alt\+)?alt_(left|right)=ignore' <<< "$ghostty_lead")"
check "Ghostty on Omarchy: shifted tmux keys spelled with Shift (Ghostty matches modifiers exactly)" "4 0" \
    "$(grep -cE '^keybind = term/shift\+(digit_5|quote|digit_7|slash)=' <<< "$ghostty_lead") $(grep -cE '^keybind = term/[%"&?]=' <<< "$ghostty_lead")"
check "Ghostty on Omarchy: every leader action closes the table after it" "" \
    "$(awk '/^keybind = term\// && !/=(ignore|deactivate_key_table|deactivate_all_key_tables)$/ { getline nxt; if (nxt != "keybind = chain=deactivate_key_table") print }' <<< "$ghostty_lead")"
# Plan A (2026-11-21): r reloads, as after tmux's and Herdr's prefix; Alt+arrows resize a step and stay in resize mode
# (tmux and Herdr resize on prefix Alt+arrows); Shift+e equalizes (tmux E), = kept.
check "Ghostty on Omarchy: leader r reloads the config" "keybind = term/r=reload_config|keybind = chain=deactivate_key_table" \
    "$(grep -A1 -xF 'keybind = term/r=reload_config' <<< "$ghostty_lead" | paste -sd'|' -)"
check "Ghostty on Omarchy: leader Alt+arrows resize 40 px, then resize mode" 4 \
    "$(for d in left down up right; do grep -A2 -xF "keybind = term/alt+arrow_$d=resize_split:$d,40" <<< "$ghostty_lead" | paste -sd'|' -; done | grep -cxE 'keybind = term/alt\+arrow_[a-z]+=resize_split:[a-z]+,40\|keybind = chain=deactivate_key_table\|keybind = chain=activate_key_table:term_resize')"
check "Ghostty on Omarchy: resize mode keeps Alt+arrows at 40 px, h j k l at 20" "4 4" \
    "$(grep -cE '^keybind = term_resize/alt\+arrow_(left|down|up|right)=resize_split:(left|down|up|right),40$' <<< "$ghostty_lead") $(grep -cE '^keybind = term_resize/[hjkl]=resize_split:[a-z]+,20$' <<< "$ghostty_lead")"
check "Ghostty on Omarchy: leader Shift+e and = equalize" "2" "$(grep -cE '^keybind = term/(shift\+e|equal)=equalize_splits$' <<< "$ghostty_lead")"
check "Ghostty on Omarchy: resize table swallows the rest too" 1 "$(grep -cxF 'keybind = term_resize/catch_all=ignore' <<< "$ghostty_lead")"
check "Ghostty on Omarchy: Omarchy's theme include and own keys kept" "1 1" "$(grep -cF 'config-file = ?' <<< "$ghostty_lead") $(grep -cxF 'keybind = shift+enter=csi:13;2u' <<< "$ghostty_lead")"
check "Ghostty on Omarchy: closing asks first, one line" "confirm-close-surface = true" "$(grep -E '^confirm-close-surface' <<< "$ghostty_lead")"
check "Ghostty on Omarchy: leader block is idempotent" "$ghostty_lead" "$(bash "$work/ghostty.sh" <<< "$ghostty_lead")"
check "Ghostty on Omarchy: tmux's letters after the leader" "new_tab new_split:right new_split:down goto_split:left toggle_split_zoom goto_tab:9 close_tab" \
    "$(for t in c shift+digit_5 shift+quote h z digit_9 shift+digit_7; do grep -F "keybind = term/$t=" <<< "$ghostty_lead" | sed 's/^[^=]*=[^=]*=//'; done | xargs)"
check "Ghostty on Omarchy: every leader binding is distinct (awk kept all)" \
    "$(grep -cE '^keybind = (term|term_resize)/' <<< "$ghostty_lead")" "$(grep -E '^keybind = (term|term_resize)/' <<< "$ghostty_lead" | sort -u | wc -l | tr -d ' ')"
ghostty_mac_lead="$(printf 'a = 1\n' | bash "$work/ghostty-mac.sh")"
check "Ghostty on macOS: Cmd-b opens the term table, no Super-b" "1 0" \
    "$(grep -cxF 'keybind = cmd+b=activate_key_table:term' <<< "$ghostty_mac_lead") $(grep -c 'super+b' <<< "$ghostty_mac_lead")"
# chain= lines belong to the binding above them: the awk keeps a user's own chain with its binding, drops an old block's
# chains with their bindings, and never merges two chain lines into one setting.
ghostty_chain="$(printf 'keybind = ctrl+x=new_tab\nkeybind = chain=goto_tab:1\nfont-size = 11\n' | bash "$work/ghostty.sh")"
check "Ghostty: a user's chain line stays right after its binding" "keybind = chain=goto_tab:1" "$(grep -A1 -xF 'keybind = ctrl+x=new_tab' <<< "$ghostty_chain" | tail -1)"
check "Ghostty: chain lines survive a second run unchanged" "$ghostty_chain" "$(bash "$work/ghostty.sh" <<< "$ghostty_chain")"
check "Ghostty: an old block's chains go with their bindings" 0 \
    "$(printf 'keybind = term/c=new_window\nkeybind = chain=toggle_fullscreen\n' | bash "$work/ghostty.sh" | grep -cE 'new_window|toggle_fullscreen')"
check "Ghostty on macOS: closing asks first" 1 "$(grep -cxF 'confirm-close-surface = true' <<< "$ghostty_mac_lead")"
check "Ghostty: both platforms bind the same term letters" \
    "$(grep -E '^keybind = term' <<< "$ghostty_lead")" "$(grep -E '^keybind = term' <<< "$ghostty_mac_lead")"
if command -v jq > /dev/null 2>&1; then
    check "Herdr app on macOS: left Option as Alt, rest kept" '{"x":1,"option_as_alt":"left"}' "$(printf '{"x":1}' | bash dot_config/herdr-app/modify_settings.json | jq -c .)"
fi
check "darwin casks include kitty, Ghostty and the Herdr app" 3 "$(render darwin run_onchange_before_00_install_packages.sh.tmpl | grep -cE '^cask "(kitty|ghostty|herdr-app)"$')"
check "omarchy packages include kitty, Ghostty and the Herdr app" 3 "$(render omarchy run_onchange_before_00_install_packages.sh.tmpl | grep -oE '"(kitty|ghostty|herdr-app)"' | sort -u | wc -l | tr -d ' ')"

# ls: the system's own ls with colour only, on every host (replaces Omarchy's eza ls on purpose).
check "every host's ~/.aliases sets ls only to ls --color=auto" "alias ls='ls --color=auto'" "$(grep -E '^ *alias ls=' dot_aliases | xargs -0 | sed 's/^ *//' | tr -d '\n')"
for host in $hosts; do
    check "$host requirement check is valid bash" "" "$(render "$host" run_after_99_assert_requirements.sh.tmpl | bash -n 2>&1)"
done
check "omarchy requirement check leaves the zsh plugins to the package check" 0 \
    "$(render omarchy run_after_99_assert_requirements.sh.tmpl | grep -c 'for zsh_plugin in')"
check "darwin requirement check warns about missing zsh plugins" 1 \
    "$(render darwin run_after_99_assert_requirements.sh.tmpl | grep -c 'for zsh_plugin in zsh-autosuggestions zsh-syntax-highlighting')"

# ssh: the public config names no own machine. They come from ~/.ssh/config.d/*.conf in the private ~/.cfg repo
# (checked there by ~/guides/ssh-reachability/check.sh); this one only includes that folder, first.
for host in $hosts; do
    render "$host" private_dot_ssh/private_config.tmpl > "$work/$host.ssh_config"
    cfg="$work/$host.ssh_config.resolve"
    grep -v 'UseKeychain' "$work/$host.ssh_config" > "$cfg" # ssh -G here may not know macOS's UseKeychain
    check "$host ~/.ssh/config includes config.d/*.conf before any Host block" "Include config.d/*.conf" \
        "$(grep -m1 -E '^(Include|Host) ' "$work/$host.ssh_config")"
    check "$host ~/.ssh/config names no own machine, tailnet, DDNS name or home address" 0 \
        "$(grep -ciE 'ts\.net|ddns|tplinkdns|192\.168\.|\.local\b|HostKeyAlias|ProxyJump|^Host .*(works|mbp|macstudio)' "$work/$host.ssh_config")"
    check "$host ~/.ssh/config never forwards the agent" 0 "$(grep -ci 'ForwardAgent yes' "$work/$host.ssh_config")"
    check "$host ssh github.com goes to ssh.github.com:443 as git" "ssh.github.com 443 git" \
        "$(ssh -G -F "$cfg" github.com 2> /dev/null | awk '$1=="hostname"{h=$2} $1=="port"{p=$2} $1=="user"{u=$2} END{print h, p, u}')"
done
check "omarchy ~/.ssh/config has no work stanza" 0 "$(render omarchy private_dot_ssh/private_config.tmpl | grep -c 'internal')"

# tailscale wrapper: the Macs only (finds the CLI of whichever Tailscale variant is installed); Linux has the real one.
for host in darwin intel; do
    check "$host gets the tailscale wrapper" yes "$(manages "$host" .local/bin/tailscale)"
done
for host in omarchy arch ubuntu debian; do
    check "$host gets no tailscale wrapper (it would shadow /usr/bin/tailscale)" no "$(manages "$host" .local/bin/tailscale)"
done
check "tailscale wrapper is valid sh" "" "$(sh -n dot_local/bin/executable_tailscale 2>&1)"

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
# gh clones over SSH: the requirement check sets it (ensure_gh_ssh), printing the command; a stub gh keeps the setting
# in a file.
sed -n '/^ensure_gh_ssh() {/,/^}/p' "$work/omarchy.requirements" > "$work/gh_ssh.sh"
mkdir -p "$work/ghs/bin"
printf '#!/bin/sh\ncase "$1 $2" in "config get") cat "$GHS/proto" ;; "config set") echo "$4" > "$GHS/proto"; echo set >> "$GHS/log" ;; esac\n' > "$work/ghs/bin/gh"
chmod +x "$work/ghs/bin/gh"
gh_ssh() { GHS="$work/ghs" PATH="$work/ghs/bin:$PATH" bash -c 'note() { echo "NOTE: $1"; }; source "$0"; ensure_gh_ssh' "$work/gh_ssh.sh" 2>&1 | paste -sd'|' -; }
echo https > "$work/ghs/proto"; rm -f "$work/ghs/log"
check "gh on https: the apply sets SSH, printing the command" '$ gh config set git_protocol ssh|OK:   gh clones over SSH (set now)|ssh|set' \
    "$(gh_ssh)|$(cat "$work/ghs/proto")|$(cat "$work/ghs/log")"
rm -f "$work/ghs/log"
check "gh already on SSH: nothing set" "OK:   gh clones over SSH|no-set" "$(gh_ssh)|$([[ -e "$work/ghs/log" ]] && echo set || echo no-set)"
check "darwin requirement check uses the same gh step" 1 "$(render darwin run_after_99_assert_requirements.sh.tmpl | grep -c '^ensure_gh_ssh() {')"
# Ghostty's terminal leader on Omarchy needs Super+B free in Hyprland: the check warns when a SUPER-only B bind appears.
sed -n '/^check_super_b() {/,/^}/p' "$work/omarchy.requirements" > "$work/super_b.sh"
mkdir -p "$work/hypr-taken" "$work/hypr-free"
printf '#!/bin/sh\necho %s\n' "'[{\"modmask\":64,\"key\":\"B\",\"description\":\"Some app\"}]'" > "$work/hypr-taken/hyprctl"
printf '#!/bin/sh\necho %s\n' "'[{\"modmask\":65,\"key\":\"B\",\"description\":\"Browser\"}]'" > "$work/hypr-free/hyprctl"
chmod +x "$work/hypr-taken/hyprctl" "$work/hypr-free/hyprctl"
super_b() { PATH="$work/$1:$PATH" bash -c 'report() { echo "WARN: $2"; }; source "$0"; check_super_b' "$work/super_b.sh" 2>&1; }
check "omarchy requirement check warns when Hyprland takes Super+B" 1 "$(super_b hypr-taken | grep -c '^WARN: Hyprland binds Super+B (Some app)')"
mkdir -p "$work/hypr-undescribed"
printf '#!/bin/sh\necho %s\n' "'[{\"modmask\":64,\"key\":\"b\",\"description\":\"\",\"dispatcher\":\"exec\",\"arg\":\"foo\"}]'" > "$work/hypr-undescribed/hyprctl"
chmod +x "$work/hypr-undescribed/hyprctl"
check "omarchy requirement check warns about an undescribed Super+B bind, naming its dispatcher" 1 "$(super_b hypr-undescribed | grep -c '^WARN: Hyprland binds Super+B (exec foo)')"
check "omarchy requirement check: Super+Shift+B leaves Super+B free" "OK:   Super+B is free in Hyprland (terminal leader)" "$(super_b hypr-free)"
# A new Ghostty window joins the running Ghostty process, and on 2026-11-20 a reload (Ctrl+Shift+,) did not pick up new
# key bindings there: the hint says to quit Ghostty and start it again.
for host in darwin omarchy; do
    check "$host Ghostty reload hint says to quit and restart, not to open a window" "1 0" \
        "$(render "$host" run_after_99_assert_requirements.sh.tmpl | grep -F 'ghostty/config" ghostty' | grep -c 'quit Ghostty') $(render "$host" run_after_99_assert_requirements.sh.tmpl | grep -F 'ghostty/config" ghostty' | grep -c 'open a new window')"
done
check "darwin requirement check has no Hyprland check" 0 "$(render darwin run_after_99_assert_requirements.sh.tmpl | grep -c 'check_super_b')"
check "omarchy requirement check warns when another file overrides the version-file setting" 1 "$(grep -c 'not $want_idiomatic, so projects' "$work/omarchy.requirements")"
check "omarchy option A requirement check skips that warning" 0 "$(chezmoi --override-data "$omarchy_a" execute-template < "$requirements" | grep -c want_idiomatic)"
for host in darwin intel arch ubuntu; do
    check "$host requirement check has no Omarchy version-file check" 0 "$(grep -c want_idiomatic "$work/$host.requirements")"
done
check "omarchy requirement check never mentions mise-audit" 0 "$(grep -c 'mise-audit' "$work/omarchy.requirements")"
# ssh-key-remember --check on Linux: a locked login keyring is "cannot tell" (2), never "not saved" (1).
mkdir -p "$work/lockstub"
printf '#!/bin/sh\necho "b true"\n' > "$work/lockstub/busctl"
printf '#!/bin/sh\nexit 0\n' > "$work/lockstub/secret-tool"
printf '#!/bin/sh\nexit 0\n' > "$work/lockstub/systemctl"
chmod +x "$work/lockstub/"*
if [[ "$(uname -s)" == Linux ]]; then
    check "ssh-key-remember --check reports a locked keyring as cannot tell" 2 \
        "$(PATH="$work/lockstub:$PATH" bash dot_local/bin/executable_ssh-key-remember --check > /dev/null 2>&1; echo $?)"
fi
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

# The "To do on this machine" list at the end of every apply (.chezmoitemplates/after-apply.sh): the run_after_ scripts
# add to it, run_after_99 prints it last. A stub pgrep says whether the app "runs" (PGREP_EXIT).
aa="$work/after-apply"
mkdir -p "$aa/bin" "$aa/home"
printf '#!/bin/sh\nexit "${PGREP_EXIT:-0}"\n' > "$aa/bin/pgrep"
chmod +x "$aa/bin/pgrep"
aa_run() { HOME="$aa/home" CHEZMOI_CACHE_DIR="$aa/cache" XDG_STATE_HOME="$aa/state" PATH="$aa/bin:$PATH" bash -c "source .chezmoitemplates/after-apply.sh; $1" | paste -sd'|' -; }
nothing="==> Nothing to do on this machine after this apply."
check "after apply: an empty list says so" "$nothing" "$(aa_run print_todo)"
check "after apply: items numbered, a repeated one listed once" "==> To do on this machine after this apply:|    1. a|    2. b" "$(aa_run 'todo a; todo b; todo a; print_todo')"
check "after apply: the list is removed once printed" 0 "$(find "$aa/cache" -name 'after-apply.*' | wc -l | tr -d ' ')"
printf 'one\n' > "$aa/home/app.conf"
check "reload hint: the first apply only records the file" "$nothing" "$(aa_run 'reload_hint "$HOME/app.conf" app "reload app"; print_todo')"
check "reload hint: unchanged file, nothing to do" "$nothing" "$(aa_run 'reload_hint "$HOME/app.conf" app "reload app"; print_todo')"
printf 'two\n' > "$aa/home/app.conf"
check "reload hint: changed file, app running" "==> To do on this machine after this apply:|    1. reload app" "$(aa_run 'reload_hint "$HOME/app.conf" app "reload app"; print_todo')"
printf 'three\n' > "$aa/home/app.conf"
check "reload hint: changed file, app not running" "$nothing" "$(PGREP_EXIT=1 aa_run 'reload_hint "$HOME/app.conf" app "reload app"; print_todo')"
printf 'four\n' > "$aa/home/app.conf"
check "reload hint: no process to test" "==> To do on this machine after this apply:|    1. reload shells" "$(PGREP_EXIT=1 aa_run 'reload_hint "$HOME/app.conf" "" "reload shells"; print_todo')"
for host in darwin omarchy arch; do
    check "$host requirement check prints the to-do list last" "print_todo" "$(render "$host" run_after_99_assert_requirements.sh.tmpl | grep -E '^[a-z_]' | tail -1)"
done
check "omarchy Ghostty reload key is Ctrl+Shift+," 1 "$(render omarchy run_after_99_assert_requirements.sh.tmpl | grep -c 'Ctrl+Shift+, reloads most settings')"
check "darwin Ghostty reload key is Cmd+Shift+," 1 "$(render darwin run_after_99_assert_requirements.sh.tmpl | grep -c 'Cmd+Shift+, reloads most settings')"
check "darwin checks the dotfiles-local links; omarchy does not" "1 0" \
    "$(render darwin run_after_99_assert_requirements.sh.tmpl | grep -c 'for local_file in zshrc.local aliases.local') $(render omarchy run_after_99_assert_requirements.sh.tmpl | grep -c 'for local_file in')"
check "darwin iTerm2 script checks the default profile and the Claude Code integration" 2 \
    "$(render darwin run_after_96_macos_iterm2.sh.tmpl | grep -cE 'defaults read com.googlecode.iterm2 "Default Bookmark Guid"|handle-agent-hook')"
check "omarchy stock-drift notes go on the to-do list" 2 "$(render omarchy run_after_95_omarchy_stock_drift.sh.tmpl | grep -c '^        todo ')"

# chezmoi init answers -> [data.work] (rendered as `chezmoi init` would, against throwaway configs, so this machine's
# own answers never leak in). Work names never appear in this repository: example-org and other-org stand in.
printf '' > "$work/cfg-empty.toml"
printf '[data]\n    email = "me@example.com"\n    name = "Test User"\n[data.work]\n    email = "work@example.com"\n    orgs = "example-org, other-org"\n    enabled = true\n    org_list = ["example-org", "other-org"]\n' > "$work/cfg-work.toml"
p_email='Work email for your work GitHub orgs (none if this machine has no work repositories)'
p_orgs='Work GitHub orgs (separate with commas)'
init_render() { # init_render CONFIG [--promptString K=V ...]: the config `chezmoi init` would write, or its error
    chezmoi --config "$1" --source "$repo" execute-template --init --no-tty "${@:2}" "$(cat "$repo/.chezmoi.toml.tmpl")" < /dev/null 2>&1
}
work_block() { sed -n '/^\[data\.work\]/,/^$/p' | grep . | sed 's/^ *//' | paste -sd'|' -; }
on='[data.work]|email = "work@example.com"|orgs = "example-org, other-org"|enabled = true|org_list = ["example-org", "other-org"]'
check "init: answers become [data.work]" "$on" \
    "$(init_render "$work/cfg-empty.toml" --promptString "$p_email=work@example.com" --promptString "$p_orgs=example-org, other-org" | work_block)"
check "init: a messy org list is cleaned" 'org_list = ["example-org", "other-org"]' \
    "$(init_render "$work/cfg-empty.toml" --promptString "$p_email=work@example.com" --promptString "$p_orgs= example-org ,, other-org, example-org " | work_block | tr '|' '\n' | grep '^org_list')"
check "init: none turns work off, without orgs" 'email = "none"|enabled = false' \
    "$(init_render "$work/cfg-empty.toml" --promptString "$p_email= NONE " | work_block | tr '|' '\n' | grep -E '^(email|enabled) ' | paste -sd'|' -)"
check "init: default answers (--promptDefaults) leave work unset" 'email = ""|enabled = false' \
    "$(init_render "$work/cfg-empty.toml" | work_block | tr '|' '\n' | grep -E '^(email|enabled) ' | paste -sd'|' -)"
check "init: existing answers are kept without a prompt" "$on" \
    "$(init_render "$work/cfg-work.toml" --promptString "$p_orgs=zzz" | work_block)"
check "init: an email without orgs fails" 1 \
    "$(init_render "$work/cfg-empty.toml" --promptString "$p_email=work@example.com" | grep -c 'list at least one work GitHub org')"
check "init: a bad org name fails" 1 \
    "$(init_render "$work/cfg-empty.toml" --promptString "$p_email=work@example.com" --promptString "$p_orgs=bad org!" | grep -c 'is not a GitHub org name')"
check "init: a non-address email fails" 1 \
    "$(init_render "$work/cfg-empty.toml" --promptString "$p_email=work" --promptString "$p_orgs=example-org" | grep -c 'is not an email address')"
# A stored answer is checked too, so a bad work email in the config file stops the next init. TOML literal strings
# ('…') carry the characters as they are.
for bad in 'a b@example.com' 'a"b@example.com' 'a#b@example.com' 'a;b@example.com' 'a\b@example.com' 'a@b@example.com' 'a@example'; do
    printf '[data]\n    email = "me@example.com"\n    name = "Test User"\n[data.work]\n    email = '"'%s'"'\n    orgs = "example-org"\n' "$bad" > "$work/cfg-bad.toml"
    check "init: rejects the work email [$bad]" 1 "$(init_render "$work/cfg-bad.toml" | grep -c 'is not an email address')"
done
check "init: no is_work any more" 0 "$(init_render "$work/cfg-empty.toml" | grep -c 'is_work')"
printf '[data]\n    email = "me@example.com"\n    name = "Test User"\n[data.work]\n    email = ""\n    orgs = ""\n    enabled = false\n    org_list = []\n' > "$work/cfg-blank-work.toml"
check "init: a blank stored by --promptDefaults is asked again" "$on" \
    "$(init_render "$work/cfg-blank-work.toml" --promptString "$p_email=work@example.com" --promptString "$p_orgs=example-org, other-org" | work_block)"

# Work rules: rendered with a throwaway config, then resolved by git itself in a throwaway HOME
wdata='{"email":"me@example.com","name":"Test User","work":{"enabled":true,"email":"work@example.com","org_list":["example-org","other-org"]}}'
odata='{"email":"me@example.com","name":"Test User","work":{"enabled":false,"email":"none","org_list":[]}}'
ndata='{"email":"me@example.com","name":"Test User"}'
render_cfg() { chezmoi --config "$work/cfg-empty.toml" --source "$repo" --override-data "$1" execute-template < "$repo/$2"; } # DATA FILE
check "gitconfig: three rules per work org, all to ~/.gitconfig.work" "6 6" \
    "$(render_cfg "$wdata" dot_gitconfig.tmpl | grep -c '^\[includeIf ') $(render_cfg "$wdata" dot_gitconfig.tmpl | grep -c '^    path = ~/.gitconfig.work$')"
check "gitconfig: work rules come before ~/.gitconfig.local" yes \
    "$(render_cfg "$wdata" dot_gitconfig.tmpl | awk '/^\[includeIf /{w=NR} /path = ~\/.gitconfig.local/{l=NR} END{print (w && w<l) ? "yes" : "no"}')"
check "gitconfig: no work rules when off or never answered" "0 0" \
    "$(render_cfg "$odata" dot_gitconfig.tmpl | grep -c includeIf) $(render_cfg "$ndata" dot_gitconfig.tmpl | grep -c includeIf)"
for d in wdata odata ndata; do
    case "$d" in wdata) data="$wdata" ;; odata) data="$odata" ;; *) data="$ndata" ;; esac
    managed_work="$(chezmoi --config "$work/cfg-empty.toml" --source "$repo" --override-data "$data" managed --include=files | grep -cx '.gitconfig.work')"
    check ".gitconfig.work managed only when work is on ($d)" "$([[ $d == wdata ]] && echo 1 || echo 0)" "$managed_work"
done
gh_home="$(cd "$work" && pwd -P)/githome" # the real path: gitdir: compares against it (macOS /var -> /private/var)
mkdir -p "$gh_home"
render_cfg "$wdata" dot_gitconfig.tmpl > "$gh_home/.gitconfig"
render_cfg "$wdata" dot_gitconfig.work.tmpl > "$gh_home/.gitconfig.work" 2> /dev/null
check ".gitconfig.work holds the work email" work@example.com "$(git config -f "$gh_home/.gitconfig.work" user.email)"
for odd in 'a#b@example.com' 'a;b@example.com' 'a"b@example.com' 'a\b@example.com'; do
    render_cfg "$(jq -cn --arg e "$odd" '{email: "me@example.com", name: "Test User", work: {enabled: true, email: $e, org_list: ["example-org"]}}')" \
        dot_gitconfig.work.tmpl > "$work/odd.gitconfig"
    check ".gitconfig.work quotes the email, so git reads [$odd] exactly" "$odd" "$(git config -f "$work/odd.gitconfig" user.email 2>&1)"
done
gitenv() { HOME="$gh_home" GIT_CONFIG_GLOBAL="$gh_home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 git "$@"; }
email_in() { # email_in DIR ORIGIN: the user.email git resolves in a new repository at DIR with that origin
    mkdir -p "$1" && gitenv -C "$1" init -q && gitenv -C "$1" remote add origin "$2" && gitenv -C "$1" config user.email
}
check "git: ssh remote in a work org" work@example.com "$(email_in "$gh_home/src/a" git@github.com:example-org/a.git)"
check "git: https remote in a work org" work@example.com "$(email_in "$gh_home/src/b" https://github.com/other-org/b.git)"
check "git: fork under ~/example-org/" work@example.com "$(email_in "$gh_home/example-org/fork" git@github.com:someone/fork.git)"
check "git: personal repository" me@example.com "$(email_in "$gh_home/src/c" git@github.com:someone/c.git)"
check "git: a lookalike org is not a work org" me@example.com "$(email_in "$gh_home/src/d" git@github.com:example-org-two/d.git)"
printf '[user]\n    email = local@example.com\n' > "$gh_home/.gitconfig.local"
check "git: ~/.gitconfig.local still wins" local@example.com "$(email_in "$gh_home/src/e" git@github.com:example-org/e.git)"
rm -f "$gh_home/.gitconfig.local"

# The requirement check: a to-do while this machine has no work email answer
r99() { render_cfg "$1" run_after_99_assert_requirements.sh.tmpl; } # DATA
check "requirements: work on is OK" 1 "$(r99 "$wdata" | grep -c 'OK:   work email for 2 work GitHub orgs')"
check "requirements: one org reads \"1 work GitHub org\"" 1 \
    "$(r99 '{"email":"me@example.com","name":"Test User","work":{"enabled":true,"email":"work@example.com","org_list":["example-org"]}}' | grep -c 'OK:   work email for 1 work GitHub org (')"
check "requirements: none is OK and no to-do" "1 0" "$(r99 "$odata" | grep -c 'answered none at chezmoi init') $(r99 "$odata" | grep -c 'chezmoi has no work email')"
check "requirements: never answered is a to-do that claims no more than chezmoi knows" 1 \
    "$(r99 "$ndata" | grep -c '^note "chezmoi has no work email for this machine, so work repositories get your personal email unless a repository or ~/.gitconfig.local sets one\.')"
for d in wdata odata ndata; do
    case "$d" in wdata) data="$wdata" ;; odata) data="$odata" ;; *) data="$ndata" ;; esac
    check "requirements with work data ($d) is valid bash" "" "$(r99 "$data" | bash -n 2>&1)"
done

echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
