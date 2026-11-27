# shellcheck shell=bash
# Shared body of the Codex modify script (included by its template): set a few keys in one section of a TOML file that
# the app also writes, keep everything else. SECTION is the table name (for example tui) and BLOCK is newline-separated
# "key = value" lines. Lines inside [SECTION] that set one of BLOCK's keys are dropped, and BLOCK goes directly after
# the [SECTION] header, so running it again changes nothing. Without a [SECTION] header, a blank line, the header and
# BLOCK are appended (blank or whitespace-only input gives just the header and BLOCK).
# A header is any line whose first non-blank character is "[": [SECTION.sub] and [[array]] are other sections, and they
# end this one. Quoted dotted headers such as [hooks.state."/path:x"] are just other headers. Not handled: a line that
# starts with "[" inside a multi-line array or string is read as a header.
# If the table is already defined without a header (before the first header: a dotted key "SECTION.key = ...", or an
# inline table "SECTION = { ... }"), a second [SECTION] would make the file invalid TOML, so awk exits 1 and the caller
# leaves the file as it is.
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
function firstpart(line,    q, rest) {
    sub(/^[[:space:]]+/, "", line)
    if (line ~ /^["\047]/) {
        q = substr(line, 1, 1)
        rest = substr(line, 2)
        return substr(rest, 1, index(rest, q) - 1)
    }
    sub(/[[:space:]=.].*$/, "", line)
    return line
}
BEGIN {
    name = ENVIRON["SECTION"]
    target = "[" name "]"
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
        seen_header = 1
        inside = (h == target)
        lines[++count] = $0
        if (inside && !found) {
            found = 1
            for (i = 1; i <= n; i++) lines[++count] = wanted[i]
        }
        next
    }
    if (!seen_header && $0 !~ /^[[:space:]]*(#|$)/ && firstpart($0) == name) {
        defined_elsewhere = 1
        exit 1
    }
    if (inside && keyof($0) in want) next
    lines[++count] = $0
}
END {
    if (defined_elsewhere) exit 1
    if (!found) {
        while (count > 0 && lines[count] ~ /^[[:space:]]*$/) count--
        if (count > 0) lines[++count] = ""
        lines[++count] = target
        for (i = 1; i <= n; i++) lines[++count] = wanted[i]
    }
    for (i = 1; i <= count; i++) print lines[i]
}'
