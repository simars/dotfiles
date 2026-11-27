{{- /* Body of every chezmoi modify_ script for a JSON settings file that an agent writes itself. The caller sets `filter`
  (a jq program) and `args` (a bash array of `--argjson name value` pairs, never empty: bash 3.2 fails on an empty array
  under `set -u`) just before `{{ template "modify-json.sh" . }}`. The stdout of a modify_ script IS the file, so this
  prints nothing else: a missing or blank file becomes {}, and input jq cannot parse, or a missing jq, passes through. */ -}}
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
current="$(cat)"
[[ -n "${current//[[:space:]]/}" ]] || current='{}'
if command -v jq > /dev/null 2>&1 && updated="$(printf '%s\n' "$current" | jq --indent 2 "${args[@]}" "$filter" 2> /dev/null)"; then
    printf '%s\n' "$updated"
else
    # No jq, or not JSON: leave the file exactly as it is.
    printf '%s' "$current"
fi
