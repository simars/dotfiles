# Shared body of the kitty and Ghostty modify scripts (included by their templates): set a few settings in a config
# file the app or Omarchy also writes, keep everything else. Each setting line is "key<sep>value"; existing lines for
# the same keys (and an earlier block from this script) are dropped, then the block is appended, so it wins (both
# apps let a later line override an earlier one). Running it again changes nothing.
awk -v marker="$MARKER" -v keys="$KEYS" -v block="$BLOCK" '
BEGIN {
    n = split(keys, k, " ")
    for (i = 1; i <= n; i++) want[k[i]] = 1
}
$0 == marker { next }
{
    line = $0
    sub(/^[[:space:]]+/, "", line)
    key = line
    sub(/[[:space:]=].*$/, "", key)
    if (line !~ /^#/ && (key in want)) next
    lines[++count] = $0
}
END {
    while (count > 0 && lines[count] ~ /^[[:space:]]*$/) count--
    for (i = 1; i <= count; i++) print lines[i]
    if (count > 0) print ""
    print marker
    printf "%s\n", block
}'
