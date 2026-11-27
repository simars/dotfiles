{{- /* Body of every chezmoi modify_ script for a JSON settings file that an agent writes itself. The caller sets `filter`
  (a jq program) and `args` (a bash array of `--argjson name value` pairs, never empty: bash 3.2 fails on an empty array
  under `set -u`) just before `{{ template "modify-json.sh" . }}`. The stdout of a modify_ script IS the file, so this
  prints nothing else: a missing or blank file becomes {}, and input jq cannot parse, or a missing jq, passes through; a failed read exits non-zero. */ -}}
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
# The trailing x keeps the final newlines, which $(...) would strip: a file that is passed through comes back byte for byte.
# `cat && printf x`, not `cat; printf x`: a failed read (a directory as stdin) must fail the script with nothing on stdout,
# or the keys-only file it would print replaces the real one.
input="$(cat && printf x)"
input="${input%x}"
current="$input"
[[ -n "${current//[[:space:]]/}" ]] || current='{}'
if command -v jq > /dev/null 2>&1 && updated="$(printf '%s\n' "$current" | jq --indent 2 "${args[@]}" "$filter" 2> /dev/null)"; then
    printf '%s\n' "$updated"
else
    # No jq, or not JSON: leave the file exactly as it is.
    printf '%s' "$input"
fi
