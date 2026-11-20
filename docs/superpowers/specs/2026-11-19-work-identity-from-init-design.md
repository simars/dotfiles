# Work git identity from `chezmoi init` answers

## Why

Work repositories must be committed with the work email on every machine, and the
work org names and email must never be in this public repository (AGENTS.md 3.3).
Until now the rules lived in two hand-made files, `~/.gitconfig.local` (the
`includeIf` rules) and `~/.gitconfig.work` (the email), copied by hand to each Mac.
works never got them: from 2026-11-17 to 2026-11-19, 48 commits in a work repository
on works went out with the personal email (46 pushed), and nothing reported the gap.

## Goals

- `chezmoi init` asks for the work email and the work GitHub orgs once per machine.
  The answers stay in that machine's `~/.config/chezmoi/chezmoi.toml` (never
  committed), and chezmoi builds the git rules from them.
- The rules are the same on every machine. There is no "work machine" switch.
- A machine without answers is told so after every apply, until it has them.
- Applies stay non-interactive: no prompts, passphrases or `op` sign-in.

## Non-goals and anti-goals

- No org name, work email or work path in any tracked file, test or commit (tests
  use `example-org`).
- `~/.gitconfig.local` stays the user's own file for one-machine extras; chezmoi
  never writes it.
- Not covered: a repository in a new work org that isn't in the list. You add the
  org with `chezmoi init --prompt`.
- 1Password as the source of the answers is a possible later addition, not part
  of this work.

## Approaches considered

1. **Prompt once per machine (chosen).** It follows the existing `email`/`name`
   prompts and needs nothing at apply time. The cost: changing the org list means
   running `chezmoi init --prompt` on each machine.
2. **An age-encrypted file in the repo.** Rejected. Every apply would ask for the
   `~/.ssh/id_rsa` passphrase, which breaks applies over SSH and by agents. The
   alternative is a second key without a passphrase, copied by hand to each
   machine, which is the same kind of manual step that failed.
3. **1Password read at init.** Deferred. It needs `op` signed in at init, and a
   change still needs a re-init on each machine.

## Design

- **Prompts:** `.chezmoi.toml.tmpl` adds two `promptStringOnce` questions,
  stored under `[data.work]`:
  - `work.email`: "Work email for repositories in your work GitHub orgs (none if
    you have no work repositories)".
  - `work.orgs`: "Work GitHub orgs, comma-separated".

  The default shown is the machine's current answer. The orgs are split on
  commas, trimmed, and empty entries are dropped. Init fails with a clear message
  if an email is given without orgs.
- **Removed:** the `is_work` prompt, which today is true on works and
  false on the work Mac. The CI init flags and the README change with it.
  (Correction after review: it was not unused. A work prompt symbol in
  `starship.toml` and a placeholder SSH host read it. Neither rendered on any
  of the three machines, so both were removed with it.)
- **`~/.gitconfig`:** when a work email is set (not blank, not `none`), it gets
  three `includeIf` blocks per org, each pointing at `~/.gitconfig.work`:
  - `hasconfig:remote.*.url:git@github.com:<org>/**`;
  - `hasconfig:remote.*.url:https://github.com/<org>/**`;
  - `gitdir:~/<org>/`.

  They come before the `~/.gitconfig.local` include, so a machine-local file and a
  repository's own `user.email` still win. The folder names on the Macs are the
  org names, so one list covers both kinds of rule.
- **`~/.gitconfig.work`:** now managed by chezmoi. It holds `[user] email = …`
  and is ignored when no work email is set.
- **Requirement check (`run_after_99`):** if `work.email` is blank, the to-do is
  "No work email set: git uses your personal email in every repository. Run
  `chezmoi init --prompt` (answer `none` if this machine never touches work
  repositories)". `none` clears it. After the template change, chezmoi itself also
  warns "config file template has changed, run chezmoi init" on existing machines.
- **Identity guard:** no logic change. It already resolves the expected identity
  from global-scope config, including these `includeIf` blocks. Only its comment
  changes.
- **Tests (`tests/host-profiles.sh`):**
  - Rendering with `example-org, other-org` gives 6 + 3 rules, and they come before
    the `~/.gitconfig.local` include.
  - Blank or `none` gives no rules and no `~/.gitconfig.work`.
  - The config template turns `--promptString` answers into `[data.work]`.
  - End to end, in a throwaway HOME, git itself resolves the email:
    - a remote in `example-org` gives the work email;
    - a fork in `~/example-org/` gives the work email;
    - a personal repo gives the personal email.
- **Docs:**
  - NEW_MACHINE.md: init asks two more questions; the "work Mac: create
    `~/.gitconfig.local`" step goes.
  - CHEATSHEET: the `~/.gitconfig.local` / `~/.gitconfig.work` rows.
  - AGENTS.md 3.3: the specifics live in chezmoi's local config, not in
    `~/.gitconfig.local`.
  - README: the list of prompts.

## Rollout (works, mbp-work, mbp)

1. `chezmoi update`. The new to-do and chezmoi's "run chezmoi init" warning appear.
2. Run `chezmoi init` with `--promptString` answers taken from the machine's
   current `~/.gitconfig.work` and `~/.gitconfig.local`, so nothing is retyped.
3. Move the hand-made `~/.gitconfig.local` and `~/.gitconfig.work` aside (dated
   backups; all they hold today are the old rules), then `chezmoi apply`.
4. Check on each machine with `git config --show-origin user.email`:
   - a work repository gives the work email from `~/.gitconfig.work`;
   - a personal repository gives the personal email.

## Left to the builder

- Exact prompt wording within the meaning above.
- How `none` and blank are normalised in the templates (one shared definition).
- Whether org names are validated beyond trimming.
