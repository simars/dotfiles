# adopt_casks APPS_DIR: before brew bundle, take over apps Homebrew did not install (.chezmoidata/packages.toml,
# darwin.brew.cask_apps). An app in APPS_DIR from the App Store (Contents/_MASReceipt) is left alone, and its cask goes
# into $skipped_casks so brew bundle does not try to install it over that copy. Every command is printed before it runs.
skipped_casks=""
adopt_casks() {
    local apps_dir="$1" cask app have
    have="$(brew list --cask 2> /dev/null || true)"
    while IFS=$'\t' read -r cask app; do
        [[ -n "$cask" ]] || continue
        grep -qxF "$cask" <<< "$have" && continue
        [[ -d "$apps_dir/$app" ]] || continue
        if [[ -d "$apps_dir/$app/Contents/_MASReceipt" ]]; then
            echo "skipped: $app is from the App Store; Homebrew leaves it alone"
            skipped_casks="${skipped_casks:+$skipped_casks }$cask"
            continue
        fi
        echo "\$ brew install --cask --adopt $cask"
        brew install --cask --adopt "$cask" < /dev/null || echo "FAILED: Homebrew could not take over $app; brew bundle will try to install it"
    done << 'CASK_APPS'
{{ range $cask, $app := (index . "packages" | default .).darwin.brew.cask_apps -}}
{{ $cask }}	{{ $app }}
{{ end -}}
CASK_APPS
}

# drop_casks BREWFILE CASK...: remove those casks' lines from the Brewfile.
drop_casks() {
    local brewfile="$1" cask
    shift
    for cask in "$@"; do
        grep -vxF "cask \"$cask\"" "$brewfile" > "$brewfile.tmp" || true
        mv "$brewfile.tmp" "$brewfile"
    done
}
