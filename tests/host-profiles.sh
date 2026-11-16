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
check "shared helpers drop open, zd, compress, a, cd and r" 2 "$(grep -cE '^(unalias a cd r|unfunction zd open compress) 2> /dev/null$' "$work/helpers.zsh")"
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
check "iTerm2 profile: left Option Esc+, right Normal, rewritable" "2 0 true" \
    "$(printf '' | bash "$iterm_modify" | jq -r '.Profiles[0] | "\(."Option Key Sends") \(."Right Option Key Sends") \(.Rewritable)"')"
check "iTerm2 profile: keeps what iTerm2 wrote into it" '[{"regex":"x"}]' \
    "$(printf '{"Profiles": [{"Triggers": [{"regex": "x"}], "Option Key Sends": 0}]}' | bash "$iterm_modify" | jq -c '.Profiles[0].Triggers')"
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

# iTerm2 may set the Mac clipboard (OSC 52) for copies in tmux, herdr and Neovim: macOS only.
check "darwin turns on iTerm2 clipboard access" 1 "$(render darwin run_after_96_macos_terminal_clipboard.sh.tmpl | grep -c '^defaults write com.googlecode.iterm2 AllowClipboardAccess -bool true$')"
check "darwin iTerm2 clipboard script is valid bash" "" "$(render darwin run_after_96_macos_terminal_clipboard.sh.tmpl | bash -n 2>&1)"
for host in omarchy arch ubuntu; do
    check "$host gets no iTerm2 clipboard script" "" "$(render "$host" run_after_96_macos_terminal_clipboard.sh.tmpl | tr -d '[:space:]')"
done

# Wave pane commands: only inside Wave (WAVETERM_BLOCKID set and wsh on PATH), in bash and zsh.
check "Wave pane commands are not defined outside Wave" "" "$(bash -c 'source dot_aliases; type -t wt wr wsplit wsr wsd 2> /dev/null')"
check "Wave pane commands are defined inside Wave (bash)" "function function function function function" \
    "$(PATH="$work/fakebin:$PATH" WAVETERM_BLOCKID=x bash -c 'mkdir -p "$0/fakebin"; printf "#!/bin/sh\n" > "$0/fakebin/wsh"; chmod +x "$0/fakebin/wsh"; source dot_aliases; type -t wt wr wsplit wsr wsd | xargs' "$work")"
if command -v zsh > /dev/null 2>&1; then
    check "Wave pane commands parse in zsh" "" "$(zsh -n dot_aliases 2>&1)"
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

# ls: the system's own ls with colour only, on every host (replaces Omarchy's eza ls on purpose).
check "~/.aliases sets ls only to ls --color=auto" "alias ls='ls --color=auto'" "$(grep -E '^ *alias ls=' dot_aliases | xargs -0 | sed 's/^ *//' | tr -d '\n')"
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
