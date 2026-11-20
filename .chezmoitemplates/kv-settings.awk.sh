# shellcheck shell=bash
# Shared body of the kitty and Ghostty modify scripts (included by their templates): set a few settings in a config
# file the app or Omarchy also writes, keep everything else. Each line of BLOCK is "key<sep>value"; existing lines that
# set the same thing (and an earlier block from this script) are dropped, then the block is appended, so it wins (both
# apps let a later line override an earlier one). Running it again changes nothing.
# "The same thing" is the key, except for Ghostty's `keybind`, which repeats once per key: there it is the key plus
# the trigger ("keybind = ctrl+enter=..." matches only other ctrl+enter lines), so the app's other bindings stay.
# A Ghostty `keybind = chain=...` line adds an action to the binding just above it, so it is never a setting of its own:
# it is kept or dropped with that binding, and the block's chain lines stay where the block puts them.
# Values go through the environment, not -v: macOS's awk rejects a newline inside a -v value.
MARKER="$MARKER" BLOCK="$BLOCK" awk '
function setting(line,    key, trigger) {
    sub(/^[[:space:]]+/, "", line)
    if (line ~ /^#/) return ""
    key = line
    sub(/[[:space:]=].*$/, "", key)
    if (key != "keybind") return key
    trigger = line
    sub(/^keybind[[:space:]]*=[[:space:]]*/, "", trigger)
    sub(/=.*$/, "", trigger)
    return key " " trigger
}
BEGIN {
    marker = ENVIRON["MARKER"]
    block = ENVIRON["BLOCK"]
    n = split(block, wanted, "\n")
    for (i = 1; i <= n; i++) {
        s = setting(wanted[i])
        if (s != "" && s != "keybind chain") want[s] = 1
    }
}
$0 == marker { next }
{
    s = setting($0)
    if (s == "keybind chain") {
        if (!dropped) lines[++count] = $0
        next
    }
    if (s in want) { dropped = 1; next }
    if (s != "") dropped = 0
    lines[++count] = $0
}
END {
    while (count > 0 && lines[count] ~ /^[[:space:]]*$/) count--
    for (i = 1; i <= count; i++) print lines[i]
    if (count > 0) print ""
    print marker
    printf "%s\n", block
}'
