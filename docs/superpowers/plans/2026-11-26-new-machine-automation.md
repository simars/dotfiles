# New-Machine Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A fresh Mac or Omarchy machine is one command plus sign-ins and a few clicks; `~/.cfg` is one pasted line
that clones it and asks about the rest, printing every command it runs.

**Architecture:** Small automations inside chezmoi's existing scripts (packages, macOS settings, iTerm2, Omarchy setup,
requirement check); an interactive installer in the private `~/.cfg` (`guides/install.sh`); a public
`bootstrap/macos.sh` mirroring `bootstrap/omarchy.sh`, both handing over to the installer.

**Tech Stack:** bash (3.2-compatible on Macs), chezmoi templates, Homebrew (`brew bundle`, `--adopt`), macOS
`defaults`/`xattr`/`open`, `tests/host-profiles.sh` stubs, shellcheck.

**Spec:** `docs/superpowers/specs/2026-11-26-new-machine-automation-design.md`

## Global Constraints

- Out of scope: iTerm2's Claude Code integration, Tailscale.
- New Mac casks: `1password`, `claude`, `google-chrome`, `slack`, `visual-studio-code`, `cursor`; formula `gh`.
  Apple silicon only through `brew bundle`; Intel Macs by hand (`docs/INTEL_MACS.md`).
- An app already in `/Applications` not from Homebrew is adopted (`brew install --cask --adopt`); one from the App
  Store (`Contents/_MASReceipt`) is skipped and named.
- Transparency: a plain `==> why` line per step, every machine-changing command printed as `$ <command>` before it
  runs, then `done` / `skipped: <reason>` / `FAILED: <reason>`; questions show their command first.
- Never remove a quarantine flag; never overwrite a real file with a link; `--yes` never chooses always-on power.
- Public repo: no work identifiers; commit as `Simar Singh <simarpaulsingh@gmail.com>`, no trailers; gitleaks clean;
  cheatsheet and `docs/NEW_MACHINE.md` updated with the behaviour; `.cfg` only through `config`.
- No push and no apply on another machine without the user's go-ahead.

## Review Focus

1. The installer re-run on a fully set-up machine changes nothing and reports `done`/`skipped` for every step (Task 7).
2. A real file at `~/.zshrc.local` or `~/.aliases.local` is never replaced by a link (Task 7).
3. Run without a terminal (`< /dev/null`), the installer and bootstrap list what they would do and change nothing
   (Tasks 7, 9).
4. An App Store copy of an app (mbp-work's Slack) is skipped, never adopted or duplicated (Task 1).
5. iTerm2 running: its default profile is not written (it would overwrite it on quit); the NOTE stays (Task 4).

---

### Task 1: Mac app casks, with adoption

**Files:**
- Modify: `.chezmoidata/packages.toml` (casks, `gh` formula, new `[darwin.brew.cask_apps]` table: cask → app name)
- Create: `.chezmoitemplates/adopt-casks.sh` (function `adopt_casks APPS_DIR`, sourced by the package script)
- Modify: `run_onchange_before_00_install_packages.sh.tmpl` (call it before `brew bundle`, Apple silicon branch)
- Modify: `tests/host-profiles.sh`, `docs/INTEL_MACS.md` (new casks by hand), `docs/NEW_MACHINE.md` step 11,
  `docs/CHEATSHEET.md`

**Interfaces:**
- Produces: `adopt_casks APPS_DIR` reads the rendered `cask app` pairs; for each cask not in `brew list --cask`
  whose `APPS_DIR/<app>` exists: App Store copy → print `skipped: <app> is from the App Store`; else run (printed)
  `brew install --cask --adopt <cask>`.
- `cask_apps`: `"1password" = "1Password.app"`, `claude = "Claude.app"`, `"google-chrome" = "Google Chrome.app"`,
  `slack = "Slack.app"`, `"visual-studio-code" = "Visual Studio Code.app"`, `cursor = "Cursor.app"`.

- [ ] **Step 1: Failing tests** (stub `brew` on PATH logging its arguments; a scratch APPS_DIR):
  - `check "darwin casks include the hand-installed apps and gh"` → 6 cask lines + `brew "gh"`.
  - `check "adopt: a hand-installed app is adopted, printed first"` → output has `$ brew install --cask --adopt google-chrome` and the stub logged it.
  - `check "adopt: an App Store app is skipped and named"` (`Slack.app/Contents/_MASReceipt`) → `skipped: Slack.app is from the App Store`, nothing logged.
  - `check "adopt: an app Homebrew already has, or one not installed, is left to brew bundle"` → nothing logged.
- [ ] **Step 2:** Run the suite. Expected: the new checks FAIL.
- [ ] **Step 3:** Implement; the package script sources the template and calls `adopt_casks /Applications`.
- [ ] **Step 4:** Suite passes. Docs. Commit `feat(macos): install the hand-installed apps and gh with Homebrew, adopting existing copies`.

### Task 2: `gh` clones over SSH, set by the apply

**Files:** `run_after_99_assert_requirements.sh.tmpl` (its existing "gh clones over SSH" check), `tests/host-profiles.sh`, `docs/NEW_MACHINE.md`.

- [ ] **Step 1: Failing tests** (stub `gh`: `config get git_protocol` prints a file; `config set` writes it):
  `https` → the apply runs (printed) `gh config set git_protocol ssh` and says OK; `ssh` → nothing set; no `gh` → silent.
- [ ] **Step 2–4:** fail, implement, pass. Commit `feat: the apply sets gh to clone over SSH`.

### Task 3: macOS's Ctrl+Space input-source shortcut off

**Files:** `run_after_97_macos_defaults.sh.tmpl` (writes id 60 like the desktop shortcuts: `enabled false`, value
parameters `32, 49, 262144`), `run_after_96_macos_iterm2.sh.tmpl` (drop its id-60 NOTE/to-do), `tests/host-profiles.sh`
(the three `hotkeys()` iTerm2 checks move to the `md` stub), `docs/NEW_MACHINE.md` step 14, cheatsheet.

- [ ] **Step 1: Failing tests:** id 60 enabled or absent → written once with `enabled 0`, reported in the updated
  line (`input-source shortcut off`); already `enabled = 0` → nothing written; the iTerm2 script no longer mentions Ctrl+Space.
- [ ] **Step 2–4:** fail, implement, pass. Commit `feat(macos): the apply turns off the Ctrl+Space input-source shortcut`.

### Task 4: iTerm2's default profile set while iTerm2 is closed

**Files:** `run_after_96_macos_iterm2.sh.tmpl` (lines ~52–56), `tests/host-profiles.sh` (`it_reset`/`iterm_after` stub), `docs/NEW_MACHINE.md` step 12.

- [ ] **Step 1: Failing tests:** not running and not chezmoi's → `$ defaults write com.googlecode.iterm2 "Default Bookmark Guid" chezmoi-left-option-as-alt` printed and written, OK line; running → nothing written, existing NOTE and to-do ("quit iTerm2 and apply again"); already chezmoi's → OK, nothing written.
- [ ] **Step 2–4:** fail, implement, pass. Commit `feat(macos): the apply makes chezmoi's iTerm2 profile the default when iTerm2 is closed`.

### Task 5: LunarVim linked on Omarchy

**Files:** `run_onchange_after_91_omarchy_setup.sh.tmpl`, `run_after_99_assert_requirements.sh.tmpl` (NOTE stays as fallback), `tests/host-profiles.sh`, `docs/NEW_MACHINE.md` step 5.

- [ ] **Step 1: Failing tests:** the rendered Omarchy setup script, with a scratch HOME and a stub `lvim`, links
  `~/.local/share/lunarvim/lvim` → `/usr/share/lunarvim` (printed `$ ln -s …`) and runs `lvim --headless +qa`; an
  existing link → nothing; no `lvim` → nothing; never `init-lvim.sh`.
  Note: 91 is `run_onchange`: include `lvim`'s presence in its hash comment only if needed (builder's call).
- [ ] **Step 2–4:** fail, implement, pass. Commit `feat(omarchy): the apply links LunarVim for you`.

### Task 6: Hammerspoon opened once after install

**Files:** `run_after_99_assert_requirements.sh.tmpl` (Hammerspoon block), `tests/host-profiles.sh`, `docs/NEW_MACHINE.md` step 15.

**Interfaces:** state file `${XDG_STATE_HOME:-~/.local/state}/chezmoi/hammerspoon-opened` (opened once, never again).

- [ ] **Step 1: Failing tests** (stubs `open`, `pgrep`; `HAMMERSPOON_APP` override): installed, not running, no state
  file → `$ open -a Hammerspoon` printed and run once, state file written, NOTE says to choose Open and allow it;
  second apply → not opened again; running → OK, nothing opened; never `xattr -d`.
- [ ] **Step 2–4:** fail, implement, pass. Live check on mbp-16i or a Mac where it is not running is part of Task 10.
  Commit `feat(macos): the apply opens Hammerspoon once after it is installed`.

### Task 7: The `.cfg` installer (private repo)

**Files:** Create `~/guides/install.sh`, `~/guides/install-test.sh` (offline, stubs on PATH, scratch HOME);
modify `~/guides/README.md`.

**Interfaces:**
- Produces: `~/guides/install.sh [--yes]`; helpers `step "<why>"`, `run <cmd…>` (prints `$ <cmd…>` then runs),
  `ask "<question>" "<command shown>"` (default Yes; `--yes` accepts; no terminal → answers No and lists the
  command); exits 0 unless a step FAILED; final summary block `Summary:` with one line per step.
- Steps (spec, Piece 2): repository (clone if missing, checkout, `status.showUntrackedFiles no`, fetch refspec,
  upstream; `~/.local/bin/config` helper when no `config` exists), Mac links, Claude Code (install on Mac; login
  ask; `make setup` ask), `gh auth login` ask, guides (Omarchy `setup-guides apply`; Mac remote-access ask with
  done-ness = Remote Login on and Touch ID for sudo; power ask default normal, done-ness from `always-on/status.sh`),
  summary + the manual list.

- [ ] **Step 1: Failing test** `install-test.sh`: (a) fresh scratch HOME, `--yes`, stub `git`/`claude`/`gh`/`make`/
  `setup-guides`/`uname` → every step's command printed as `$ …` before its stub logs it; (b) run again → every step
  `done`/`skipped`, no stub logs; (c) real file at `.zshrc.local` → `skipped: a real file is there`, file unchanged;
  (d) `< /dev/null` → nothing logged, commands listed; (e) `--yes` on a Mac never runs `always-on/apply.sh`.
- [ ] **Step 2–4:** fail, implement, pass; `shellcheck`. Commit in `.cfg`: `feat(guides): install.sh: set up ~/.cfg and ask about the rest`.

### Task 8: Omarchy bootstrap hands over to the installer

**Files:** `bootstrap/omarchy.sh` (steps 4–5 → skip the clone if `~/.cfg` exists, else the clone; then
`bash ~/guides/install.sh`; `--with-remote-unlock` stays), its header comment, `tests/host-profiles.sh` (bash -n,
shellcheck, the hand-over line present, its `run` helper prints commands), `docs/NEW_MACHINE.md` section B.

- [ ] **Steps:** failing checks, implement (add the `run` helper so the bootstrap prints its commands too), pass, commit
  `feat(omarchy): the bootstrap runs the .cfg installer and prints its commands`.

### Task 9: `bootstrap/macos.sh`

**Files:** Create `bootstrap/macos.sh`; modify `tests/host-profiles.sh`, `docs/NEW_MACHINE.md` section A (run it, then
the manual list), `README.md` if it lists bootstraps, cheatsheet.

**Interfaces:** steps as the spec's Piece 3; same `step`/`run` helpers; `uname -m` not `arm64` → stops, pointing to
`docs/INTEL_MACS.md`; no `~/.ssh/id_rsa` → stops with the copy command (as Omarchy's).

- [ ] **Step 1: Failing tests:** valid bash, shellcheck clean; with stubs (`uname`, `xcode-select`, `brew`,
  `chezmoi`, `ssh`, `git`): Intel → stops with INTEL_MACS.md; no key → stops naming the copy command, nothing else
  run; all present → commands printed in order, ends with the `.cfg` line (or `install.sh` when `~/.cfg` exists);
  `< /dev/null` → lists, changes nothing.
- [ ] **Step 2–4:** fail, implement, pass. Commit `feat(macos): bootstrap/macos.sh, one command for a new Mac`.

### Task 10: Review and rollout

- [ ] **Step 1:** Fresh reviewer on the whole change (chezmoi range + `.cfg` installer); fix what it confirms.
- [ ] **Step 2 (user's go-ahead):** push `.cfg`, then chezmoi; `chezmoi update` twice on mbp, mbp-work, mbp-16i
  (mbp-work adopts 1Password, Claude, Chrome, Cursor and skips App Store Slack: check `brew list --cask`); works
  `chezmoi apply`; run `~/guides/install.sh` on works and one Mac (expect all done/skipped); user checks the printed
  output reads clearly.
