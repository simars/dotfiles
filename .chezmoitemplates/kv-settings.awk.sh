# shellcheck shell=bash
# Shared body of the kitty and Ghostty modify scripts (included by their templates): set a few settings in a config
# file the app or Omarchy also writes, keep everything else. Each line of BLOCK is "key<sep>value"; existing lines that
# set the same thing (and an earlier block from this script) are dropped, then the block is appended, so it wins (both
# apps let a later line override an earlier one). Running it again changes nothing.
# "The same thing" is the key, except for Ghostty's `keybind`, which repeats once per key: there it is the key plus
# the trigger ("keybind = ctrl+enter=..." matches only other ctrl+enter lines), so the app's other bindings stay.
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
    for (i = 1; i <= n; i++) if (setting(wanted[i]) != "") want[setting(wanted[i])] = 1
}
$0 == marker { next }
{
    if (setting($0) in want) next
    lines[++count] = $0
}
END {
    while (count > 0 && lines[count] ~ /^[[:space:]]*$/) count--
    for (i = 1; i <= count; i++) print lines[i]
    if (count > 0) print ""
    print marker
    printf "%s\n", block
}'
