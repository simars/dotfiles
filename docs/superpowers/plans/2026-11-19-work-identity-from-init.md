# Work Git Identity from `chezmoi init` Answers: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `chezmoi init` asks for the work email and work GitHub orgs. chezmoi then writes the work `includeIf` rules into `~/.gitconfig` and manages `~/.gitconfig.work` on every machine, and every apply lists a to-do while a machine has no answer.

**Architecture:**
- `.chezmoi.toml.tmpl` turns the two answers into `[data.work]` in the machine's local config. It owns all parsing and validation.
- `dot_gitconfig.tmpl`, `dot_gitconfig.work.tmpl`, `.chezmoiignore` and `run_after_99` only read the normalised keys.
- Tests render with `example-org` data against a throwaway chezmoi config, and let git itself resolve the email in a throwaway HOME.

**Tech Stack:** chezmoi 2.73 templates (Go text/template + sprig), git ≥ 2.36 `includeIf "hasconfig:…"`, bash 3.2-compatible tests.

**Spec:** `docs/superpowers/specs/2026-11-19-work-identity-from-init-design.md`

## Global Constraints

- No work org name, work email or work path in any tracked file, test or commit message (AGENTS.md 3.3). Tests use only:
  - orgs `example-org` and `other-org`;
  - emails `work@example.com`, `me@example.com` and `local@example.com`;
  - owner `someone`.
- Applies stay non-interactive: no prompt, passphrase or `op` at apply time.
- chezmoi never writes `~/.gitconfig.local`.
- The exact prompt texts, with no commas, because `--promptString` keys are the prompt text:
  - P_EMAIL = `Work email for your work GitHub orgs (none if this machine has no work repositories)`
  - P_ORGS = `Work GitHub orgs (separate with commas)`
- Data contract in `[data.work]`, written by `.chezmoi.toml.tmpl` only:
  - `email`: `""` (not answered), `"none"`, or the trimmed address.
  - `orgs`: the trimmed raw answer.
  - `enabled`: true only when `email` is an address.
  - `org_list`: the orgs split on commas, trimmed, with empty entries and duplicates dropped.

  Templates read these with `dig "work" "<key>" <default> .` so that a config from before this change still renders.
- Tests run under bash 3.2 (macOS `/bin/bash`): no `${v,,}`, `mapfile` or associative arrays. New tests that use the source pass `--source "$repo"`, and use `--config` with a throwaway file so the machine's real answers never leak in.
- CHEATSHEET changes go in the same commit as the behaviour they describe.
- gitleaks and shellcheck stay clean.
- Conventional commits as `Simar Singh <simarpaulsingh@gmail.com>`, with no agent trailers.
- Work in `~/.local/share/chezmoi-worktrees/work-identity` on branch `feat/work-identity`. Integrate by fast-forward only.
- No push without the user's explicit OK.
- Full suite: `bash tests/host-profiles.sh` ends with `N passed, 0 failed` (639 before this plan).

## Review Focus

1. **A lookalike org** (`example-org-two` when `example-org` is a work org) must give the personal email. Test in Task 2.
2. **Re-running `chezmoi init` headless** (over SSH, `--no-tty`) on a machine with answers must keep them unchanged and never prompt. Test in Task 1.
3. **A machine whose config predates this change** (no `[data.work]`) must render every template with no work rules, no `~/.gitconfig.work`, and the to-do shown. Tests in Tasks 2 and 3.
4. **Messy answers** must normalise: ` NONE `, spaces, `,,`, a trailing comma, a repeated org. Test in Task 1.
5. **A `~/.gitconfig.local` email** must still win over the work email. Test in Task 2.

Known limitation, documented rather than handled: `hasconfig` and `gitdir:` match case-sensitively, so org names must be typed as they appear in clone URLs.

---

### Task 1: The init prompts and `[data.work]`

**Files:**
- Modify: `.chezmoi.toml.tmpl`: remove the `is_work` prompt and key; add the two prompts and `[data.work]` after the `[data]` keys, before `[age]`, followed by a blank line.
- Modify: `.github/workflows/ci.yml:86-90`: drop `--promptBool "Is this a work machine=false"`; add `--promptString "P_EMAIL=work@example.com"` and `--promptString "P_ORGS=example-org, other-org"`, using the exact texts.
- Modify: `README.md:59`: the headless defaults become "no work email", and the requirement check lists it as a to-do.
- Test: `tests/host-profiles.sh`: a new section before the final summary.

**Interfaces:**
- Produces: the `[data.work]` contract in Global Constraints, plus these failure messages from init:
  - `work.email: "<x>" is not an email address (or answer none)`
  - `work.orgs: list at least one work GitHub org when a work email is set`
  - `work.orgs: "<org>" is not a GitHub org name (letters, digits and hyphens)`

- [ ] **Step 1: Write the failing tests**

```bash
# chezmoi init answers -> [data.work] (rendered as `chezmoi init` would, against throwaway configs)
printf '' > "$work/cfg-empty.toml"
printf '[data]\n    email = "me@example.com"\n    name = "Test User"\n[data.work]\n    email = "work@example.com"\n    orgs = "example-org, other-org"\n    enabled = true\n    org_list = ["example-org", "other-org"]\n' > "$work/cfg-work.toml"
p_email='Work email for your work GitHub orgs (none if this machine has no work repositories)'
p_orgs='Work GitHub orgs (separate with commas)'
init_render() { # init_render CONFIG [--promptString K=V ...]: the config `chezmoi init` would write, or its error
    chezmoi --config "$1" --source "$repo" execute-template --init --no-tty "${@:2}" "$(cat "$repo/.chezmoi.toml.tmpl")" < /dev/null 2>&1
}
work_block() { sed -n '/^\[data\.work\]/,/^$/p' | grep . | sed 's/^ *//' | paste -sd'|' -; }
on='[data.work]|email = "work@example.com"|orgs = "example-org, other-org"|enabled = true|org_list = ["example-org", "other-org"]'
check "init: answers become [data.work]" "$on" \
    "$(init_render "$work/cfg-empty.toml" --promptString "$p_email=work@example.com" --promptString "$p_orgs=example-org, other-org" | work_block)"
check "init: a messy org list is cleaned" 'org_list = ["example-org", "other-org"]' \
    "$(init_render "$work/cfg-empty.toml" --promptString "$p_email=work@example.com" --promptString "$p_orgs= example-org ,, other-org, example-org " | work_block | tr '|' '\n' | grep '^org_list')"
check "init: none turns work off, without orgs" 'email = "none"|enabled = false' \
    "$(init_render "$work/cfg-empty.toml" --promptString "$p_email= NONE " | work_block | tr '|' '\n' | grep -E '^(email|enabled) ' | paste -sd'|' -)"
check "init: no answers (headless) leave work unset" 'email = ""|enabled = false' \
    "$(init_render "$work/cfg-empty.toml" | work_block | tr '|' '\n' | grep -E '^(email|enabled) ' | paste -sd'|' -)"
check "init: existing answers are kept without a prompt" "$on" \
    "$(init_render "$work/cfg-work.toml" --promptString "$p_orgs=zzz" | work_block)"
check "init: an email without orgs fails" 1 \
    "$(init_render "$work/cfg-empty.toml" --promptString "$p_email=work@example.com" | grep -c 'list at least one work GitHub org')"
check "init: a bad org name fails" 1 \
    "$(init_render "$work/cfg-empty.toml" --promptString "$p_email=work@example.com" --promptString "$p_orgs=bad org!" | grep -c 'is not a GitHub org name')"
check "init: a non-address email fails" 1 \
    "$(init_render "$work/cfg-empty.toml" --promptString "$p_email=work" --promptString "$p_orgs=example-org" | grep -c 'is not an email address')"
check "init: no is_work any more" 0 "$(init_render "$work/cfg-empty.toml" | grep -c 'is_work')"
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `bash tests/host-profiles.sh 2>&1 | grep -E '^FAIL init:|passed,'`
Expected: all 9 `init:` checks FAIL, because the template has no `[data.work]` yet and still has `is_work`. The other 639 pass.

- [ ] **Step 3: Implement the prompts in `.chezmoi.toml.tmpl`**

The template does the normalising and validating:
- Each prompt is `promptStringOnce . "work.email" P_EMAIL (dig "work" "email" "" .)` (and the same for `work.orgs`), so `chezmoi init --prompt` shows the current answer as the default.
- `trim` both answers, and treat a case-insensitive `none` as `none`.
- Build `org_list` with `range splitList ","`, `trim`, dropping empty entries and entries already in the list (`has`).
- When enabled, call `fail` with the exact messages above:
  - when the email has no `@`;
  - when `org_list` is empty;
  - when an org doesn't match `^[A-Za-z0-9][A-Za-z0-9-]*$`.
- Write `org_list` as a TOML array of quoted strings separated by `, `.

- [ ] **Step 4: Update the CI init flags and README line 59** as listed under Files.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `bash tests/host-profiles.sh | tail -1`
Expected: `648 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add .chezmoi.toml.tmpl .github/workflows/ci.yml README.md tests/host-profiles.sh
git commit -m "feat(init): ask for the work email and work GitHub orgs"
```

### Task 2: The work rules in `~/.gitconfig` and the managed `~/.gitconfig.work`

**Files:**
- Modify: `dot_gitconfig.tmpl:63`: insert the work block just before `[include]\n    path = ~/.gitconfig.local`.
- Create: `dot_gitconfig.work.tmpl`
- Modify: `.chezmoiignore`: ignore `.gitconfig.work` unless `dig "work" "enabled" false .`, with a one-line comment like the neighbouring blocks.
- Modify: `dot_config/git/hooks/executable_git-identity-guard:6-9`: the comment now says the identity is resolved from `~/.gitconfig` (whose work rules include `~/.gitconfig.work`) plus `~/.gitconfig.local`. No logic change.
- Modify: `docs/CHEATSHEET.md`:
  - line 264: the same wording as the guard comment;
  - lines 540-541: `~/.gitconfig.local` holds one-machine git settings only; `~/.gitconfig.work` is managed by chezmoi from the init answers, changed with `chezmoi init --prompt`, and org names must be typed as in clone URLs.
- Modify: `AGENTS.md:70` (3.3): keep the specifics in the `chezmoi init` answers (`[data.work]` in `~/.config/chezmoi/chezmoi.toml`) and in `~/.zshrc.local`; tests use `example-org`.
- Modify: `README.md`, directory tree: add `dot_gitconfig.work.tmpl` with a short comment.
- Test: `tests/host-profiles.sh`

**Interfaces:**
- Consumes: the `[data.work]` contract (Task 1).
- Produces:
  - For each org in `org_list`, in this order, each followed by `    path = ~/.gitconfig.work`:
    - `[includeIf "hasconfig:remote.*.url:git@github.com:<org>/**"]`
    - `[includeIf "hasconfig:remote.*.url:https://github.com/<org>/**"]`
    - `[includeIf "gitdir:~/<org>/"]`
  - `~/.gitconfig.work`: a comment line saying it is managed by chezmoi from the init answers, then `[user]` / `    email = <work.email>`.

- [ ] **Step 1: Write the failing tests**

```bash
# Work rules: rendered with a throwaway config, then resolved by git itself in a throwaway HOME
wdata='{"email":"me@example.com","name":"Test User","work":{"enabled":true,"email":"work@example.com","org_list":["example-org","other-org"]}}'
odata='{"email":"me@example.com","name":"Test User","work":{"enabled":false,"email":"none","org_list":[]}}'
ndata='{"email":"me@example.com","name":"Test User"}'
render_cfg() { chezmoi --config "$work/cfg-empty.toml" --source "$repo" --override-data "$1" execute-template < "$repo/$2"; } # DATA FILE
check "gitconfig: three rules per work org, all to ~/.gitconfig.work" "6 6" \
    "$(render_cfg "$wdata" dot_gitconfig.tmpl | grep -c '^\[includeIf ') $(render_cfg "$wdata" dot_gitconfig.tmpl | grep -c '^    path = ~/.gitconfig.work$')"
check "gitconfig: work rules come before ~/.gitconfig.local" yes \
    "$(render_cfg "$wdata" dot_gitconfig.tmpl | awk '/^\[includeIf /{w=NR} /path = ~\/.gitconfig.local/{l=NR} END{print (w && w<l) ? "yes" : "no"}')"
check "gitconfig: no work rules when off or never answered" "0 0" \
    "$(render_cfg "$odata" dot_gitconfig.tmpl | grep -c includeIf) $(render_cfg "$ndata" dot_gitconfig.tmpl | grep -c includeIf)"
for d in wdata odata ndata; do
    eval "data=\$$d"
    managed_work="$(chezmoi --config "$work/cfg-empty.toml" --source "$repo" --override-data "$data" managed --include=files | grep -cx '.gitconfig.work')"
    check ".gitconfig.work managed only when work is on ($d)" "$([[ $d == wdata ]] && echo 1 || echo 0)" "$managed_work"
done
gh_home="$(cd "$work" && pwd -P)/githome" # the real path: gitdir: compares against it (macOS /var -> /private/var)
mkdir -p "$gh_home"
render_cfg "$wdata" dot_gitconfig.tmpl > "$gh_home/.gitconfig"
render_cfg "$wdata" dot_gitconfig.work.tmpl > "$gh_home/.gitconfig.work"
check ".gitconfig.work holds the work email" work@example.com "$(git config -f "$gh_home/.gitconfig.work" user.email)"
gitenv() { HOME="$gh_home" GIT_CONFIG_GLOBAL="$gh_home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 git "$@"; }
email_in() { # email_in DIR ORIGIN: the user.email git resolves in a new repository at DIR with that origin
    mkdir -p "$1" && gitenv -C "$1" init -q && gitenv -C "$1" remote add origin "$2" && gitenv -C "$1" config user.email
}
check "git: ssh remote in a work org" work@example.com "$(email_in "$gh_home/src/a" git@github.com:example-org/a.git)"
check "git: https remote in a work org" work@example.com "$(email_in "$gh_home/src/b" https://github.com/other-org/b.git)"
check "git: fork under ~/example-org/" work@example.com "$(email_in "$gh_home/example-org/fork" git@github.com:someone/fork.git)"
check "git: personal repository" me@example.com "$(email_in "$gh_home/src/c" git@github.com:someone/c.git)"
check "git: a lookalike org is not a work org" me@example.com "$(email_in "$gh_home/src/d" git@github.com:example-org-two/d.git)"
printf '[user]\n    email = local@example.com\n' > "$gh_home/.gitconfig.local"
check "git: ~/.gitconfig.local still wins" local@example.com "$(email_in "$gh_home/src/e" git@github.com:example-org/e.git)"
rm -f "$gh_home/.gitconfig.local"
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `bash tests/host-profiles.sh 2>&1 | grep -E '^FAIL (gitconfig|\.gitconfig\.work|git):|passed,'`
Expected FAILs:
- `gitconfig: three rules…` and `…come before…`;
- `.gitconfig.work managed only when work is on (wdata)`;
- `.gitconfig.work holds…`;
- the three work-email `git:` checks.

Already passing: "no work rules", the two `(odata)`/`(ndata)` managed checks, personal, lookalike and
`~/.gitconfig.local still wins`. The local include already exists, so these guard against regressions.

- [ ] **Step 3: Implement** the template block, the new file and the ignore rule exactly as in Interfaces. The block is gated by `dig "work" "enabled" false .` and loops over `dig "work" "org_list" list .`. Then update the guard comment, CHEATSHEET, AGENTS.md 3.3 and the README tree.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `bash tests/host-profiles.sh | tail -1`
Expected: `661 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add dot_gitconfig.tmpl dot_gitconfig.work.tmpl .chezmoiignore dot_config/git/hooks/executable_git-identity-guard docs/CHEATSHEET.md AGENTS.md README.md tests/host-profiles.sh
git commit -m "feat(git): work identity rules from the chezmoi init answers"
```

### Task 3: The to-do while a machine has no answer, and the new-machine guide

**Files:**
- Modify: `run_after_99_assert_requirements.sh.tmpl`: in the once-per-machine section, right after the `gh` block, add three render-time branches:
  - enabled: `echo "OK:   work email for <len org_list> work GitHub orgs (~/.gitconfig.work)"`;
  - `email` is `none`: `echo "OK:   no work email on this machine (answered none at chezmoi init)"`;
  - otherwise: `note "no work email set, so git uses your personal email in every repository, work ones included. Fix: chezmoi init --prompt (answer none if this machine never has work repositories)"`.
- Modify: `docs/NEW_MACHINE.md`:
  - line 41: init asks four questions; describe the two new ones and `none`;
  - line 70: drop the "On a work Mac, also create `~/.gitconfig.local`…" sentence, but keep the work env files part;
  - the Omarchy bootstrap step: the same two questions;
  - the "After every apply" table: a row for the new to-do;
  - one line saying that changing the work email or orgs later is `chezmoi init --prompt`, then `chezmoi apply`.
- Test: `tests/host-profiles.sh`

**Interfaces:**
- Consumes: the `[data.work]` contract (Task 1); `note` and `todo` from `run_after_99` and `.chezmoitemplates/after-apply.sh`.

- [ ] **Step 1: Write the failing tests**

```bash
r99() { render_cfg "$1" run_after_99_assert_requirements.sh.tmpl; } # DATA (render_cfg from Task 2)
check "requirements: work on is OK" 1 "$(r99 "$wdata" | grep -c 'OK:   work email for 2 work GitHub orgs')"
check "requirements: none is OK and no to-do" "1 0" "$(r99 "$odata" | grep -c 'answered none at chezmoi init') $(r99 "$odata" | grep -c 'no work email set')"
check "requirements: never answered is a to-do" 1 "$(r99 "$ndata" | grep -c '^note "no work email set')"
for d in wdata odata ndata; do
    eval "data=\$$d"
    check "requirements with work data ($d) is valid bash" "" "$(r99 "$data" | bash -n 2>&1)"
done
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `bash tests/host-profiles.sh 2>&1 | grep -E '^FAIL requirements|passed,'`
Expected: the first three FAIL; the `valid bash` ones pass.

- [ ] **Step 3: Implement** the three branches and the guide changes as listed under Files.

- [ ] **Step 4: Run the tests, shellcheck and gitleaks**

Run: `bash tests/host-profiles.sh | tail -1`
Expected: `667 passed, 0 failed`. gitleaks already ran on each commit through the global pre-commit hook.

Then run `git diff main..HEAD | grep -c -i -E '<each real org name>|<work email domain>'`, with the patterns typed in the shell only and never written to a file. Expected: `0`.

- [ ] **Step 5: Commit**

```bash
git add run_after_99_assert_requirements.sh.tmpl docs/NEW_MACHINE.md tests/host-profiles.sh
git commit -m "feat(requirements): list a to-do while a machine has no work email answer"
```

### Task 4: Rollout to works, mbp-work and mbp (done by the controller, not a subagent)

The controller runs this after the branch is fast-forwarded into `main`, the user has OK'd the push, the iTerm2 session has been told, and CI is green on the pushed commit (`gh run watch`).

- [ ] **Step 1: Per machine, read the current answers from its hand-made files.**
  - Email: `git config -f ~/.gitconfig.work user.email`.
  - Orgs: `grep -oE 'hasconfig:remote\.\*\.url:git@github\.com:[^/]+' ~/.gitconfig.local | sed 's/.*://' | sort -u | paste -sd, - | sed 's/,/, /g'`.

  Print only counts and domains in the transcript.
- [ ] **Step 2: Get the new source.** On works, the local source is already current. On the Macs, run `chezmoi git -- pull --ff-only`.
- [ ] **Step 3: Answer the new questions.** Run `chezmoi init --no-tty --promptString "P_EMAIL=<email>" --promptString "P_ORGS=<orgs>" < /dev/null`.

  Expected: `[data.work]` in `~/.config/chezmoi/chezmoi.toml` with `enabled = true` and the same number of orgs as before (3 on the Macs).
- [ ] **Step 4: Move the hand-made files aside.** Do this only if `~/.gitconfig.local` holds nothing but comments, the work `includeIf` lines and their `path = ~/.gitconfig.work` lines; otherwise stop and ask.

  Rename it to `~/.gitconfig.local.bak-2026-11-19`, and `~/.gitconfig.work` to `~/.gitconfig.work.bak-2026-11-19`.
- [ ] **Step 5: Apply.** Run `chezmoi apply`.

  Expected: exit 0, and the end-of-apply list has no work-email item.
- [ ] **Step 6: Verify.** Run `git config --show-origin user.email` in one work repository and in `~/.local/share/chezmoi`.
  - Expected: the work one shows `file:~/.gitconfig.work` and the work domain; the personal one shows `file:~/.gitconfig` and `gmail.com`.
  - Then run `~/.config/git/hooks/git-identity-guard --pre-commit` in the work repository; it should exit 0.

  The work repository to use on each machine is any clone whose origin is in a work org. On works, use the one
  whose commits were re-authored on 2026-11-19. Its path stays out of this file (AGENTS.md 3.3).
- [ ] **Step 7: Report to the user.**
  - The per-machine results.
  - The backups, kept until the user says to delete them.
  - Any to-dos the applies printed.
