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
for line in 'window_title = "{hostname}: {workspace}"' 'panel_bg = "reset"' 'surface_dim = "black"' 'prefix = "ctrl+b"'; do
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
check "shared look: no per-Mac or left-Option keys" "" \
    "$(shared_look repo | jq -r '.Profiles[0] | keys[] | select(IN("Description","Default Bookmark","Shortcut","Tags","Working Directory","Option Key Sends"))')"
check "shared look: names no font that isn't installed (Hack)" 0 "$(shared_look repo | grep -c Hack)"
check "shared look: triggers off in full-screen apps by default" false "$(shared_look repo | jq '.Profiles[0]."Enable Triggers in Interactive Apps"')"
check "shared look: switch on writes true" true "$(shared_look true | jq '.Profiles[0]."Enable Triggers in Interactive Apps"')"
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
        case "$4 $5" in "-bool true") v=1 ;; "-bool false") v=0 ;; *) v="$5" ;; esac
        printf '%s\n' "$v" > "$IT/defaults/$3"
        printf '%s\n' "$3" >> "$IT/defaults/written" ;;
esac
EOF
printf '#!/bin/sh\nexit "$(cat "$IT/running")"\n' > "$it/bin/pgrep"
chmod +x "$it/bin/defaults" "$it/bin/pgrep"
render darwin "$it96" > "$it/script.sh"
it_reset() { # the all-OK state, iTerm2 not running ($it/running holds pgrep's exit code)
    rm -rf "$it/defaults" "$it/cache"
    mkdir -p "$it/defaults"
    for k in AllowClipboardAccess CopySelection DoubleClickPerformsSmartSelection "Print In Black And White"; do echo 1 > "$it/defaults/$k"; done
    for k in ShowFullScreenTabBar HapticFeedbackForEsc SoundForEsc VisualIndicatorForEsc; do echo 0 > "$it/defaults/$k"; done
    echo 4 > "$it/defaults/PasteTabToStringTabStopSize"
    echo chezmoi-left-option-as-alt > "$it/defaults/Default Bookmark Guid"
    printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\\"/Users/x/.config/iterm2/it2\\" handle-agent-hook"}]}]}}\n' > "$it/home/.claude/settings.json"
    printf '#!/bin/sh\n' > "$it/home/.config/iterm2/it2"
    chmod +x "$it/home/.config/iterm2/it2"
    printf '' | bash "$iterm_modify" > "$it_profile"
    echo 1 > "$it/running"
}
iterm_after() { # the script's output in the stub Mac, then exit=<code>
    local out rc
    out="$(IT="$it" HOME="$it/home" PATH="$it/bin:$PATH" ITERM2_APP="${it_app:-$it/iTerm.app}" CHEZMOI_CACHE_DIR="$it/cache" XDG_STATE_HOME="$it/state" bash "$it/script.sh" 2>&1)"
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
    check "iTerm2 script: default profile [$guid] is not chezmoi's" 1 "$(iterm_after | grep -c "^NOTE: iTerm2's default profile is not chezmoi's")"
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
it_reset
printf 'not json' > "$it_profile"
check "iTerm2 script: a profile that is not JSON gives no local-changes line, exit 0" "0|exit=0" "$(iterm_after | grep -c 'changed on this Mac only')|$(iterm_after | tail -1)"
it_reset
check "iTerm2 script: silent without iTerm2" "|exit=0" "$(it_app="$it/none" iterm_after | paste -sd'|' -)"

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
check "setup-guides lists the guides" 'guides=("zsh" "terminals-clipboard" "wave-keys" )' "$(grep '^guides=' "$work/setup-guides")"
check "omarchy requirement check reports guides with setup-guides apply" 1 "$(render omarchy run_after_99_assert_requirements.sh.tmpl | grep -c 'Fix: setup-guides apply')"
check "omarchy packages include omarchy-zsh" 1 "$(render omarchy run_onchange_before_00_install_packages.sh.tmpl | grep -c '"omarchy-zsh"')"

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
kv() { render "$1" "$2" > "$work/kv.sh"; printf '%b' "$3" | bash "$work/kv.sh" | grep -v '^# Set by chezmoi' | paste -sd'|' -; }
check "kitty on macOS: keeps the rest, sets copy on select and left Option as Alt" "include t.conf|font_size 11||copy_on_select clipboard|macos_option_as_alt left" \
    "$(kv darwin dot_config/kitty/modify_kitty.conf.tmpl 'include t.conf\ncopy_on_select no\nfont_size 11\n')"
check "kitty on Omarchy: copy on select only" "include t.conf||copy_on_select clipboard" "$(kv omarchy dot_config/kitty/modify_kitty.conf.tmpl 'include t.conf\n')"
check "Ghostty on macOS: copy on select and left Option as Alt, comments kept" "# copy-on-select = false|font-size = 11||copy-on-select = clipboard|macos-option-as-alt = left" \
    "$(kv darwin dot_config/ghostty/modify_config.tmpl '# copy-on-select = false\ncopy-on-select = true\nfont-size = 11\n')"
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
check "Ghostty on macOS: keys left to Ghostty (it uses Cmd)" 0 "$(render darwin dot_config/ghostty/modify_config.tmpl > "$work/ghostty-mac.sh"; printf 'a = 1\n' | bash "$work/ghostty-mac.sh" | grep -c 'unbind')"
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
check "omarchy Ghostty reload key is Ctrl+Shift+," 1 "$(render omarchy run_after_99_assert_requirements.sh.tmpl | grep -c 'press Ctrl+Shift+, in Ghostty')"
check "darwin Ghostty reload key is Cmd+Shift+," 1 "$(render darwin run_after_99_assert_requirements.sh.tmpl | grep -c 'press Cmd+Shift+, in Ghostty')"
check "darwin checks the dotfiles-local links; omarchy does not" "1 0" \
    "$(render darwin run_after_99_assert_requirements.sh.tmpl | grep -c 'for local_file in zshrc.local aliases.local') $(render omarchy run_after_99_assert_requirements.sh.tmpl | grep -c 'for local_file in')"
check "darwin iTerm2 script checks the default profile and the Claude Code integration" 2 \
    "$(render darwin run_after_96_macos_iterm2.sh.tmpl | grep -cE 'Default Bookmark Guid|handle-agent-hook')"
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
check "requirements: none is OK and no to-do" "1 0" "$(r99 "$odata" | grep -c 'answered none at chezmoi init') $(r99 "$odata" | grep -c 'no work email set')"
check "requirements: never answered is a to-do" 1 "$(r99 "$ndata" | grep -c '^note "no work email set')"
for d in wdata odata ndata; do
    case "$d" in wdata) data="$wdata" ;; odata) data="$odata" ;; *) data="$ndata" ;; esac
    check "requirements with work data ($d) is valid bash" "" "$(r99 "$data" | bash -n 2>&1)"
done

echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
