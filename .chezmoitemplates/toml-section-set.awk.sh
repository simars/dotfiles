# shellcheck shell=bash
# Shared body of the Codex modify script (included by its template): set a few keys in one section of a TOML file that
# the app also writes, keep everything else. SECTION is the table name (for example tui) and BLOCK is newline-separated
# "key = value" lines. Lines inside [SECTION] that set one of BLOCK's keys are dropped, and BLOCK goes directly after
# the [SECTION] header, so running it again changes nothing. Without a [SECTION] header, a blank line, the header and
# BLOCK are appended (blank or whitespace-only input gives just the header and BLOCK).
# A header is any line whose first non-blank character is "[": [SECTION.sub] and [[array]] are other sections, and they
# end this one. Quoted dotted headers such as [hooks.state."/path:x"] are just other headers. Not handled: a line that
# starts with "[" inside a multi-line array or string is read as a header.
# Values go through the environment, not -v: macOS's awk rejects a newline inside a -v value. POSIX awk only.
SECTION="$SECTION" BLOCK="$BLOCK" awk '
function header(line) {
    sub(/^[[:space:]]+/, "", line)
    if (line !~ /^\[/) return ""
    sub(/[[:space:]]*#.*$/, "", line)
    gsub(/[[:space:]]+/, "", line)
    return line
}
function keyof(line,    key) {
    sub(/^[[:space:]]+/, "", line)
    if (line ~ /^#/) return ""
    key = line
    sub(/[[:space:]]*=.*$/, "", key)
    gsub(/^["\047]|["\047]$/, "", key)
    return key
}
BEGIN {
    target = "[" ENVIRON["SECTION"] "]"
    block = ENVIRON["BLOCK"]
    n = split(block, wanted, "\n")
    for (i = 1; i <= n; i++) {
        k = keyof(wanted[i])
        if (k != "") want[k] = 1
    }
}
{
    h = header($0)
    if (h != "") {
        inside = (h == target)
        lines[++count] = $0
        if (inside && !found) {
            found = 1
            for (i = 1; i <= n; i++) lines[++count] = wanted[i]
        }
        next
    }
    if (inside && keyof($0) in want) next
    lines[++count] = $0
}
END {
    if (!found) {
        while (count > 0 && lines[count] ~ /^[[:space:]]*$/) count--
        if (count > 0) lines[++count] = ""
        lines[++count] = target
        for (i = 1; i <= n; i++) lines[++count] = wanted[i]
    }
    for (i = 1; i <= count; i++) print lines[i]
}'
