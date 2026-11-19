# shellcheck shell=bash
# Shared by the run_after_ scripts (included by their templates): the "To do on this machine" list printed at the end
# of every apply, so what needs a hand never scrolls away among the OK lines.
#   todo MESSAGE                     add one line to the list
#   reload_hint FILE PROCESS MESSAGE add MESSAGE when FILE changed since the last apply and PROCESS is running (an app
#                                    that reads its config only at start or on a reload key); PROCESS "" skips that test
#   print_todo                       print the list (or "Nothing to do"), then forget it; run_after_99 calls it last
# The scripts of one apply share chezmoi's process ID, so the list file is per apply. Checksums of the watched files
# live in ~/.local/state/chezmoi-after-apply; the first apply on a machine only records them.
after_apply_list="${CHEZMOI_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/chezmoi}/after-apply.$PPID"
after_apply_state="${XDG_STATE_HOME:-$HOME/.local/state}/chezmoi-after-apply"

todo() {
    mkdir -p "${after_apply_list%/*}" 2> /dev/null && printf '%s\n' "$1" >> "$after_apply_list"
}

reload_hint() {
    local file="$1" process="$2" message="$3" sum record old
    [[ -f "$file" ]] || return 0
    sum="$(cksum < "$file")"
    record="$after_apply_state/$(printf '%s' "${file#"$HOME"/}" | tr '/' '_')"
    old="$(cat "$record" 2> /dev/null)"
    mkdir -p "$after_apply_state" 2> /dev/null && printf '%s\n' "$sum" > "$record"
    [[ -n "$old" && "$old" != "$sum" ]] || return 0
    [[ -z "$process" ]] || pgrep -x "$process" > /dev/null 2>&1 || return 0
    todo "$message"
}

print_todo() {
    local line n=0
    if [[ -s "$after_apply_list" ]]; then
        echo "==> To do on this machine after this apply:"
        while IFS= read -r line; do
            n=$((n + 1))
            printf '    %d. %s\n' "$n" "$line"
        done < <(awk '!seen[$0]++' "$after_apply_list")
    else
        echo "==> Nothing to do on this machine after this apply."
    fi
    rm -f "$after_apply_list"
    # Lists left by an apply that stopped before this script ran.
    find "${after_apply_list%/*}" -maxdepth 1 -name 'after-apply.*' -mmin +60 -delete 2> /dev/null || true
}
