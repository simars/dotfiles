# Future Considerations & Platform Roadmap

This document outlines key future considerations, platform lifecycle changes, and automated remediation strategies using **`chezmoi`**.

**How to read it.** Sections 1 to 8 describe what was considered and how it was handled, and each carries a status. Section 9 is the backlog of systemic improvements that remain: changes to this repository, its scripts or its conventions. Steps that concern one particular machine are tracked in private notes, not here.

| Section | Topic | Status (2026-10-18) |
|---|---|---|
| 1 | Intel macOS lifecycle and Homebrew Tier 3 | Implemented; the bottle-only guard was rewritten |
| 2 | Command Line Tools automation | Implemented inside the package script |
| 3 | Homebrew pruning | Automatic prune implemented; declarative prune open (§9, B9) |
| 4 | Keychain SSH passphrase | Implemented; headless Intel hosts still cannot unlock the key (§9, B2 and B3) |
| 5 | `zoxide` and `fzf` | Implemented |
| 6 | Apple Silicon invariants | Implemented |
| 7 | Matrix of automated handling | Updated |
| 8 | Deferred items from the 2026-10-17 migration | All resolved; leftovers moved to §9 |
| 9 | Backlog of systemic improvements | Open |

---

## 1. Intel macOS (x86_64) Lifecycle & Homebrew Tier 3 Transition (implemented, guard rewritten 2026-10-18)

### 1.1 Platform Context
* **Apple Transition:** Intel x86_64 support is discontinued in macOS Golden Gate (macOS 27).
* **GitHub Actions:** Deprecating Intel macOS runners in 2027.
* **Homebrew Support Tier 3:** As of September 2026, Homebrew officially categorized macOS on Intel x86_64 as **Tier 3** (best-effort, no official maintenance, discontinued new bottle builds).
* **Source Fallback Hazard:** When a formula lacks an x86_64 bottle, Homebrew by default attempts to compile the entire dependency tree (LLVM, Rust, CMake, OpenSSL) from source. If Xcode or Command Line Tools (CLT) are outdated, the build crashes after downloading gigabytes of source code.

### 1.2 Chezmoi Handling & Mitigation
* **Bottle-only installs (rewritten 2026-10-18):** `HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK` does not exist in Homebrew 7 (it only ever covered failed bottle downloads), and Homebrew 7 on Intel builds anything that has no bottle, so one apply compiled 30 formulae in 7 hours. On Intel the package script now runs `brew bundle --no-upgrade` through `brew_bundle_bottled_only`: it passes only formulae that are installed or whose whole runtime dependency closure is bottled, prints each skip with its reason, and installs only what is already present if Homebrew cannot be queried (details in §8.2).
* **Resilient Standalone Binaries:**
  For critical CLI tools and editors that must always exist regardless of Homebrew's state, chezmoi auto-provisions precompiled binaries into `~/.local/bin`:
  * `age` (via official GitHub tarball)
  * `mise` (via official install script)
  * `starship` (via starship.rs installer)
  * `zoxide` (via official install script)
  * `fzf` (via official GitHub tarball)
  * `herdr` (via official GitHub release standalone binary)
  * `neovim` (via official GitHub release archive into `~/.local`)
  * `lunarvim` (via official unattended bootstrap installer once `neovim` is present)

---

## 2. Xcode Command Line Tools Automation (implemented inside the package script)

### 2.1 The Issue
On older Intel machines running newer macOS releases (such as macOS 26 Tahoe/Sequoia), existing Command Line Tools (e.g. from Xcode 14.3.1) fail with:
```text
Error: Your Command Line Tools (CLT) does not support macOS 26.
```
This blocks any local compilation (native gems, pip wheels, or local C tools).

### 2.2 Chezmoi Handling
> **Status:** implemented as a check near the top of `run_onchange_before_00_install_packages.sh.tmpl`, not as the separate `run_once` script sketched below. On Intel the standalone git build also needs the Command Line Tools.

Chezmoi can automate detection and installation in a lifecycle script (`run_once_before_05_darwin_clt.sh.tmpl`):
```bash
{{ if eq .chezmoi.os "darwin" -}}
#!/usr/bin/env bash
set -euo pipefail

if ! xcode-select -p &>/dev/null; then
    echo "==> Xcode Command Line Tools missing. Triggering installation..."
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    PROD=$(softwareupdate -l 2>&1 | awk -F"*" '/Command Line Tools/ {print $2}' | sed -e 's/^ *//' | tr -d '\n')
    if [[ -n "$PROD" ]]; then
        softwareupdate -i "$PROD" --verbose
    else
        xcode-select --install || true
    fi
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
fi
{{ end -}}
```

### 2.3 Manual Workstation Command
To perform a complete system-level update when at the workstation:
```bash
softwareupdate --all --install --force
```
Or to cleanly reset Command Line Tools:
```bash
sudo rm -rf /Library/Developer/CommandLineTools
sudo xcode-select --install
```

---

## 3. Homebrew Formula Pruning & Cellar Hygiene (automatic prune implemented; declarative prune open)

### 3.1 The Issue
Over time, workstations accumulate obsolete packages, legacy databases (e.g., `mysql@5.7`, `adoptopenjdk8`), and abandoned utilities that consume gigabytes of disk space and slow down `brew update`.

### 3.2 Chezmoi Handling
Chezmoi can handle cleanup at two distinct levels:

1. **Automated Pruning in Package Hook (`run_onchange_before_00_install_packages.sh.tmpl`):**
   Run non-destructive autoremove and cache cleanup automatically after package installs:
   ```bash
   echo "==> Pruning orphaned Homebrew dependencies and clearing cache..."
   brew autoremove || true
   brew cleanup -s || true
   ```

2. **Declarative State Enforcement (`brew bundle cleanup`):**
   `brew bundle` natively supports pruning any formula, cask, or tap not declared in `.chezmoidata/packages.toml`:
   ```bash
   brew bundle cleanup --force --file=/path/to/Brewfile
   ```
   *Caution: This removes all packages not explicitly listed in `packages.toml`. It is recommended as an opt-in script (`cz-brew-prune`) rather than an unconditional automatic hook.*

---

## 4. macOS Keychain SSH Passphrase Automation (implemented; headless Intel hosts still cannot unlock the key)

### 4.1 The Issue
If an SSH private key (`~/.ssh/id_rsa`) is protected with a passphrase:
* In GUI sessions, macOS Keychain can store the passphrase.
* In headless SSH sessions (e.g., managing the Intel Mac from the Mac Studio), the session does not have access to an interactive GUI prompt, causing SSH commands (such as GitHub access or remote `chezmoi update`) to fail or hang unless `-A` (agent forwarding) is passed.

### 4.2 Chezmoi Handling
Chezmoi solves this end-to-end:

1. **Declarative SSH Client Configuration (`private_dot_ssh/private_config.tmpl`):**
   ```sshconfig
   Host *
       AddKeysToAgent yes
       IdentitiesOnly yes
       StrictHostKeyChecking accept-new
   {{- if eq .chezmoi.os "darwin" }}
       UseKeychain yes
   {{- end }}
   ```
   *Note: `StrictHostKeyChecking accept-new` automatically trusts and records new host keys (e.g. GitHub/GitLab) into `known_hosts` while still blocking unexpected host key changes, eliminating `Host key verification failed` during headless tool bootstrapping.*
2. **Automatic Keychain Identity Loading (`dot_zprofile.tmpl`):**
   Ensure keys saved in Keychain are automatically loaded into `ssh-agent` on shell startup:
   ```bash
   if [[ "$(uname -s)" == "Darwin" ]]; then
       ssh-add --apple-load-keychain 2>/dev/null || true
   fi
   ```
3. **One-Time Keychain Registration Hook (`run_once_after_10_ssh_keychain.sh.tmpl`):**
   Chezmoi can run an interactive hook once:
   ```bash
   {{ if eq .chezmoi.os "darwin" -}}
   #!/usr/bin/env bash
   SSH_KEY="$HOME/.ssh/id_rsa"
   if [[ -f "$SSH_KEY" ]] && [[ -t 0 ]]; then
       if ! ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf "$SSH_KEY" | awk '{print $2}')"; then
           echo "==> Enrolling SSH key into macOS Keychain..."
           ssh-add --apple-use-keychain "$SSH_KEY" 2>/dev/null || true
       fi
   fi
   {{ end -}}
   ```
   Once enrolled, headless sessions on that machine have full GitHub access without needing `-A`.

---

## 5. Shell Navigation & Package Registry Completeness (`zoxide` & `fzf`) (implemented)

### 5.1 The Issue
`dot_zshrc.tmpl` activates `zoxide` (`eval "$(zoxide init zsh)"`) and `fzf` (`eval "$(fzf --zsh)"`).
The interactive jump command `zi` relies on both `zoxide` and `fzf`. If either is omitted from `.chezmoidata/packages.toml`, `zi: command not found` occurs.

### 5.2 Chezmoi Handling
1. **Explicit Inclusion in Registry (`.chezmoidata/packages.toml`):**
   Ensure `zoxide` and `fzf` are declared under `[darwin.brew].formulae` and `[ubuntu.apt].packages`.
2. **Binary Fallback in Installer:**
   If Homebrew is unable to install `zoxide` on older architectures, `run_onchange_before_00_install_packages.sh.tmpl` installs `zoxide` into `~/.local/bin`:
   ```bash
   if ! command -v zoxide &> /dev/null; then
       curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
   fi
   ```

---

## 6. Apple Silicon (`arm64`) Workstation Invariants & Lifecycle (implemented)

### 6.1 Native Architecture & Homebrew (`/opt/homebrew`)
* **Prefix Isolation:** Unlike Intel (`/usr/local`), Apple Silicon Homebrew lives strictly in `/opt/homebrew`. `dot_zprofile.tmpl` and `dot_zshrc.tmpl` dynamically test `[[ -x "/opt/homebrew/bin/brew" ]]` before falling back to `/usr/local`.
* **Tier 1 Bottle Availability:** Apple Silicon on contemporary macOS versions receives precompiled official bottles for almost all formulae and casks, making source compilation fallbacks unnecessary.
* **Pre-existing Cask Adoptions:** Applications installed prior to chezmoi adoption (e.g. manual downloads in `/Applications/`) must be adopted using `brew install --cask --force <app>` to avoid bundle install collisions.
* **Metadata Keg Tab Hygiene:** If Homebrew flags circular dependencies (e.g. `libtiff`, `webp`) caused by stale local bottle tabs, run `brew reinstall <formulae>` to refresh local dependency receipts.

### 6.2 External Age Binary & SSH RSA Recipient Handling
* **Native Homebrew Age:** On Apple Silicon, `age` is installed via Homebrew to `/opt/homebrew/bin/age`.
* **Format-Preserving Decryption:** Setting `useBuiltin = false` under `[age]` ensures chezmoi delegates directly to `/opt/homebrew/bin/age`, which parses SSH RSA keys and Ed25519 keys without error.
* **Passphrase Lifecycle:** When decrypting with passphrase-protected SSH keys (`~/.ssh/id_rsa`), macOS Keychain integration via `ssh-add --apple-load-keychain` and `ssh-add --apple-use-keychain` provides persistent credentials across login sessions.

### 6.3 Thoughtbot RCM Retirement & Asset Adoption
* **Legacy Directory Retirement:** The historical `~/dotfiles` repository (managed by thoughtbot's `rcm`) was fully retired and deleted after essential assets were promoted directly into chezmoi:
  * `dot_gitignore`: Global git ignore (`~/.gitignore`).
  * `dot_gitmessage`: Commit message template (`~/.gitmessage`).
  * `dot_aliases`: Core development aliases (`~/.aliases`).
  * `dot_vimrc`: Standalone classic vim configuration (`~/.vimrc`).
  * `dot_psqlrc`, `dot_gemrc`, `dot_rspec`: Database and language tool preferences.
  * Migration specs and design plans preserved in `docs/superpowers/`.
* **Zero Broken Symlinks:** All dangling thoughtbot symlinks (`~/.rcrc`, `~/.bin`, `~/.git_template`, `~/.zsh`, `~/.vimrc.bundles`) were cleanly pruned.
* **Safety Archive:** A full tarball backup of the legacy repository was created at `~/.dotfiles.legacy.*.tar.gz` before removal.

---

## 7. Matrix Summary of Automated Chezmoi Handling

| Consideration | Managed By Chezmoi | Implementation Mechanism |
|---|---|---|
| **CLT Outdated / Missing** | ✅ Detection & Prompt | `xcode-select -p` check in pre-package hook; fallback warnings |
| **Homebrew Cleanup** | ✅ Automated Hook & Alias | `brew autoremove && brew cleanup -s` in package installer hook |
| **Keychain Passphrase** | ✅ SSH Config + Shell Startup | `UseKeychain yes` in `~/.ssh/config` + `ssh-add --apple-load-keychain` in `.zprofile` |
| **`zi` & `zoxide` Availability** | ✅ Package Registry + Fallback | Added to `packages.toml` + fallback binary curl installer |
| **Intel Source Builds** | ✅ Bottle-only guard | `brew_bundle_bottled_only` in the package script (installed or fully bottled closure only) + `--no-upgrade`; `HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK` no longer exists |
| **Git 2.54+ for the secret-scan hook** | ✅ Assert + Intel build | `run_after_99_assert_requirements` (fails on Apple silicon, warns for `/usr/bin/git` on Intel) + a pinned git built into `~/.local` on Intel |
| **`EDITOR` / `VISUAL`** | ✅ Default editor | First of `nvim`, `vim`, `vi` in `.zshrc`, set before `.aliases` is read |
| **Apple Silicon Prefix & Bottles**| ✅ Native Resolution | Dynamic `/opt/homebrew` shellenv + Tier 1 native bottle pouring |
| **SSH-RSA Mixed Case Error** | ✅ External Binary Engine | `useBuiltin = false` delegates to native `age` binary |

---

## 8. Deferred Items from the `Simars-MacBook-Work` Migration (2026-10-17; all resolved, leftovers moved to §9)

### 8.1 Native Homebrew Changeover (`Simars-MacBook-Work`) (resolved 2026-10-17)
* **Kickoff prompt:** [`NATIVE_HOMEBREW_KICKOFF.md`](NATIVE_HOMEBREW_KICKOFF.md) holds the session prompt with the ordered steps; results are in `TESTING_AND_VERIFICATION_GUIDE.md` §9.6.
* Resolved: native Homebrew 7.0.9 runs from `/opt/homebrew`. The blocker was never a real "CLT 11.7" install but a stale 2019-2020 `/Library/Developer/CommandLineTools` directory that overrode Xcode 27.1; it was removed and replaced with CLT 26.6.
* Resolved: `mise` and its Go, Node and Python runtimes are native arm64, and the `~/.local/bin` fallbacks (`bat`, `dust`, `fx`, `duf`, `gitleaks`, `age`, `age-keygen`, `herdr`, `mise`) are gone.
* Resolved: `rcm` was uninstalled from all four hosts on 2026-10-17, so a stray `rcup` cannot recreate the thoughtbot symlinks.
* Resolved: `gh auth login -h github.com` renewed the invalid token; the native `gh` is logged in.
* Resolved: the `wave` cask was adopted by the later `chezmoi apply` (Caskroom symlink only; `Wave.app` untouched), and all 20 `~/go/bin` tools are native arm64 (`gopls` and `staticcheck` moved to their latest releases because the pinned versions no longer compile on Go 1.27).
* Resolved (2026-10-18): Redis and the MySQL server were uninstalled from both Homebrew prefixes together with their data, config and logs, plus a stale `mysql@5.7` launch agent whose binary no longer existed; `mysql-client@8.4` stays. `copilot` and `op` now come from native casks (`copilot-cli`, `1password-cli`), and the Intel `copilot-cli` and `1password-cli@beta` casks are gone.
* Resolved (2026-10-18): the Intel Homebrew on `Simars-MacBook-Work` is gone. `/usr/local/Homebrew`, `Cellar` and `Caskroom` are empty, `/usr/local/bin/brew` and `/usr/local/etc/gitconfig` no longer exist, and `simar-mbp` has no Homebrew under `/usr/local` either. The apps of the native casks (`Wave`, `iTerm`, `Warp`, `Visual Studio Code`, `DBeaver`, `Antigravity IDE`) are intact. The `~/Brewfile` entries that only the Intel brew carried (`asdf`, `go`, `nvm`, `rbenv`, `python@3.8`, `python@3.9`, `python@3.10`, `v8@3.15`) were dropped in `.cfg` `4a5efdc`. `~/.zprofile` and `~/.zshrc` keep an `elif` for `/usr/local/bin/brew`; it never matches on Work and is what serves the Intel hosts.
* Not Homebrew, left alone on Work (nothing was deleted; ask before cleaning up): 49 entries in `/usr/local/bin` (gem executables from 2022 such as `rails`, `rake` and `bundle`; links for `code`, `cursor`, `docker`, `kubectl`, `tsh`, `multipass` and `keybase` into their apps; `lerna` and `verdaccio` into `../lib/node_modules`), and the config folders `clang`, `openssl@1.1`, `openssl@3`, `ca-certificates`, `mercurial` and `fonts` in `/usr/local/etc`.

### 8.2 Install Script Gaps (resolved; remaining gaps are backlog items in §9)
* **Homebrew on Intel compiles anything without a bottle (resolved 2026-10-18).** `simars-macbook-16i` compiled 30 formulae from source in 7.1 hours of build time during one apply (`TESTING_AND_VERIFICATION_GUIDE.md` §9.8). Cause: `HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1`, which the script exports, never guarded this and no longer exists in either brew (it became the default and only concerned failed bottle downloads). What refused unbottled formulae on 32i was Homebrew 6.0.12's `fresh_install?` check (`no bottle available!`); Homebrew 7.0.9, on 16i, restricts that check to arm64 CPUs (`extend/os/mac/formula_installer.rb`), so on Intel it builds from source. 32i would have done the same as soon as its brew updated to 7.x. The script now runs `brew_bundle_bottled_only` on Intel: it asks `brew deps` and `brew info --json=v2` (read with Homebrew's own portable Ruby, no `jq` and no developer mode) and gives `brew bundle` only the formulae that are installed or whose whole runtime closure is bottled, and prints each skip with its reason; any query failure keeps only what is already installed. The Intel list therefore skips what cannot be bottled instead of compiling it (`age`, `dust`, `fx`, `git`, `mise`, `herdr`, `neovim`, `vim` and `docker` among others). Do not use `brew ruby` for such probes: it switches on developer mode (`brew developer off` undoes it).
* **`brew update` could not update Homebrew itself on 32i (resolved 2026-10-18).** The global `url.insteadOf` rule in `~/.gitconfig` (https to ssh) made the fetch of `/usr/local/Homebrew` fail with `Permission denied (publickey)` because 32i cannot unlock the SSH key non-interactively, so its brew stayed on 6.0.12 while the taps updated. `GIT_CONFIG_GLOBAL=/dev/null` does not help, because `bin/brew` re-launches itself with an environment filtered to `HOME`, `SSH_AUTH_SOCK`, `TERM` and `HOMEBREW_*`. The script now runs `brew update` with `HOME` pointing at an empty temporary directory and `HOMEBREW_CACHE`/`HOMEBREW_LOGS` kept at their real locations. 32i is now on Homebrew 7.0.9, like 16i. The same rule also breaks any other plain-HTTPS clone of a public repo on hosts without an unlocked key; it is a deliberate setting, so it was left as is.
* `gitleaks` and `duf` have no darwin standalone fallback in `run_onchange_before_00_install_packages.sh.tmpl` (backlog B11). Note that any edit to that script changes its hash and re-runs it on every host that renders a different script.
* Resolved: the script's `#!/usr/bin/env bash` used to resolve to `/usr/local/bin/bash` (x86_64) on a Rosetta-Homebrew Mac, so runtime-detecting installers such as `mise.run` picked x86_64. That Homebrew was removed on 2026-10-18, so it no longer applies.

### 8.3 Per-Repo Exclude Lists on Other Hosts (resolved 2026-10-17)
* Every git dir on `simar-mbp` (38), `simars-macbook-32i` (92) and `simars-macbook-16i` (252) now links `.git/info/exclude` to `~/.config/git/info-exclude`, as does `~/.cfg` on all four hosts. Before, the mbp and 16i links dangled into the deleted `~/dotfiles`, and 32i's pointed to git's stock template with no patterns, so those hosts gained about 166 ignore patterns. §6.3's "zero broken symlinks" had covered home-level links only.
* The thoughtbot hook shims (3,456 across the three hosts) were removed. On 32i the template `pre-commit` had been rewritten to run `gitleaks --config "$REPO_ROOT/.gitleaks.toml"`; no repo had that file, so it aborted every commit in 93 git dirs.

### 8.4 Identity and Legacy Leftovers (resolved)
* Resolved: the work identity lives in `~/.gitconfig.local` (machine-local, not managed by chezmoi) on all four hosts. It includes `~/.gitconfig.work` (the work email) for remotes in the work GitHub orgs and for clones under the matching `~/<org>/` directories. A repo's own `user.email` still wins.
* Resolved: thoughtbot leftovers retired on 32i and 16i with tarballs in `~/.dotfiles.legacy.*.tar.gz`. 16i's `~/dotfiles` was not thoughtbot but a clean clone of an old commit of this repo (the `legacy-backup` branch, deleted from GitHub on 2026-10-18), and `~/symlinks.dotfiles.thoughtbot` held 20 saved links; both are archived and removed.
* Resolved (2026-10-18): retiring the thoughtbot `zsh/configs` had left `EDITOR`/`VISUAL` unset, so `alias e="$EDITOR"` expanded to nothing; `.zshrc` now sets both to the first of `nvim`, `vim` and `vi` (`22cffa2`). The thoughtbot shell functions (`mcd`, `envup`, `change-extension`) and `~/.bin` scripts (`git-up`, `tat`, `replace`) were dropped on purpose and are no longer kept in this repository.
* Resolved: a global gitleaks pre-commit hook (config-defined, Git 2.54+) now replaces the per-repo thoughtbot template; see §8.5 for the git versions it depends on.
* Resolved: `rcm` uninstalled from all four hosts (Homebrew, no dependents).

### 8.5 Git 2.54+ for the Global Secret Scan (resolved, with an accepted residual gap)
The gitleaks hook is a config-defined hook, which git before 2.54 ignores without any warning. `run_after_99_assert_requirements` checks the terminal git and Apple's `/usr/bin/git` (used by GUI apps) after every apply. On Apple silicon both are hard requirements; on Intel only the terminal git is, and `/usr/bin/git` is a `WARN`. Option (a) below was chosen and implemented in `62b3a21` (2026-10-18). As of 2026-10-18:

| Host | Terminal git | `/usr/bin/git` | Remaining step |
|---|---|---|---|
| `Simars-MacBook-Work` | 2.56.0 (Homebrew, native) | 2.54.0 (Xcode 27.1) | None: the requirement check passes. |
| `simar-mbp` | 2.56.0 (Homebrew) | 2.54.0 (Xcode 27.1 selected) | None: the requirement check passes. |
| `simars-macbook-32i` | 2.56.0 (standalone, `~/.local/bin/git`, x86_64, built from source by `chezmoi apply`) | 2.50.1 (Xcode 26.2; CLT 26.6 is also installed) | None: `chezmoi apply` exits 0 with a `WARN` for `/usr/bin/git`. A synthetic `ghp_` token commit was blocked by the live hook. |
| `simars-macbook-16i` | 2.56.0 (standalone, as on 32i) | 2.50.1 (CLT 26.6 selected; Xcode 14.3.1 stopped running on it, so CLT was installed) | None: `chezmoi apply` exits 0 with the same `WARN`. A live test with a random fake `ghp_` token was blocked on both Intel hosts (16i on 2026-10-18, after the guard rollout). |

* Xcode 27.1 ships Apple Git-157 (2.54.0). Command Line Tools 26.6, installed on all four hosts, bundle Apple Git-155 (2.50.1), so a CLT alone cannot meet the requirement. Verify `/usr/bin/git --version` after any toolchain change.
* **Xcode 27 runs only on Apple silicon.** Apple's release notes, as quoted in the developer forums, say so, and a beta failed on an Intel MacBook under Tahoe 26.5. The Intel hosts therefore cannot reach Apple git 2.54 through Xcode, and Intel Homebrew has no git bottle for macOS 26.
* **Chosen (a):** on Intel Macs the install script builds a pinned git (2.56.0, sha256 verified, `NO_RUST=YesPlease NO_GETTEXT=YesPlease NO_TCLTK=YesPlease`) into `~/.local`, plus the `git-credential-osxkeychain` helper and a `~/.local/etc/gitconfig` that sets `credential.helper = osxkeychain`, so HTTPS credentials behave as with Apple's git. `~/.local/bin` leads PATH, so terminals use it. The Apple-git check on Intel is a `WARN`, not a `FAIL`; on Apple silicon it still fails. The arm64 render of the script is byte-identical to before, so Apple silicon hosts do not re-run it.
* **Residual gap:** GUI apps launched from the Dock (minimal PATH, `/usr/bin/git`) still use Apple's 2.50.1 on both Intel hosts and skip the hook. That is why the check warns instead of passing silently. The only fix would be an Apple toolchain with git 2.54+, which Intel Macs cannot run. Commit from a terminal on those hosts.
* The other options were (b) leave the Intel check failing as a permanent reminder and (c) drop the global hook on Intel and rely on per-repo hooks. Neither was needed.
* Bump `ver` and `sha` together in `install_standalone_git` to move the pinned git. The function skips the build when `~/.local/bin/git` already meets `requirements.git.min`, so a bump only matters for hosts below the minimum, and any edit to the script re-runs it on every Intel host.

### 8.6 After the 2026-10-18 Rollout (resolved)
Results are in `TESTING_AND_VERIFICATION_GUIDE.md` §9.9 to §9.12. Everything found was fixed or recorded: the dead and unmet `~/Brewfile` entries, the leftover build tools and `brew doctor` warnings on the Intel hosts, the explicit installs outside `packages.toml`, `nvm`, `gemini-cli` and OpenClaw (removed from all four Macs), and the broken casks on one host. What remains is either an accepted gap (below), a backlog item in §9, or a step for one machine that is tracked in private notes.

| Item | Where | Detail |
|---|---|---|
| Apple git for GUI apps on Intel | the two Intel hosts | See §8.5: GUI apps that use `/usr/bin/git` skip the hook; commit from a terminal. Accepted. |
| Xcode 26.2 outdated | one Intel host | App Store, optional. Xcode 27 does not run on Intel, and updating does not change Apple's git (2.50.1). |
| `pcre2` stays | all hosts | `ripgrep` and `zsh` (both in `packages.toml`) depend on it, and on Apple silicon so do `git` and others. Only the old `pcre` was removed. |

---

## 9. Backlog of Systemic Improvements

Changes to this repository that came out of the 2026-10-17/18 migration. Nothing here is broken today; each item removes a manual step or a failure that was actually hit. **Decision** marks items that need the owner's choice before any work.

| # | Improvement | Evidence | Priority |
|---|---|---|---|
| B1 | **Verify the templates automatically.** A `make verify` (or CI job) that renders the install and assert scripts for arm64 and amd64 (`chezmoi execute-template --override-data '{"chezmoi":{"arch":"amd64"}}'`), runs `bash -n` and `shellcheck`, and compares the arm64 render with the previous commit's, so Apple silicon hosts never re-run the install script by accident. | Done by hand for each of five script commits. | High, small |
| B2 | **Narrow the `url.insteadOf` https-to-ssh rewrite** to private orgs, or use `pushInsteadOf`, so public clones and fetches (Homebrew's own repositories, this repository) work without an unlocked key. | `brew update` could not update Homebrew on an Intel host until the script worked around it, and the Intel hosts cannot `git pull` this repository, so every rollout used git bundles. Fetching private repositories over https would need credentials. | Decision |
| B3 | **Non-interactive GitHub access for the Intel hosts**, as the alternative to B2: a read-only deploy key per host without a passphrase, or a working keychain enrolment (§4). | Same evidence as B2. | Decision |
| B4 | **Apply-time check for broken casks.** In `run_after_99_assert_requirements`, warn on interrupted upgrades (`Caskroom/*/*.upgrading` markers) and on apps whose bundle has no `Contents`. | A MacBook Pro lost VS Code, Slack and Docker Desktop to an interrupted `brew upgrade` on 2026-10-16 and it went unnoticed for two days; `brew doctor` flagged it. | Medium, small |
| B5 | **Make the upgrade alias safer.** `brews` runs `brew upgrade` on formulae and casks together; split it (formulae first, casks separately, skipping `auto_updates` casks and running apps). | The cause of the interrupted upgrade is not proven; this removes the likely path. | Medium |
| B6 | **Declare global CLI tools after nvm**: mise's npm backend or `default-npm-packages` in the chezmoi mise config, for the few tools that lived under nvm (`@figma/code-connect`, the `neovim` provider, `vsce`, `yarn`). | nvm was removed on all four Macs and nothing declares where such tools now live. | Low |
| B7 | **Pre-removal impact checklist** in `AGENTS.md`: before uninstalling, check Homebrew dependents and non-Homebrew consumers (launchd plists, MCP configs, wrapper scripts, editor settings). | Removing one formula autoremoved `node` and left three MCP wrapper scripts without it; a launchd service pointed into `~/.nvm`. | Medium, small |
| B8 | **One package source of truth.** The personal `~/Brewfile` (private repository) and `.chezmoidata/packages.toml` overlap and drift; dead and unmet entries were found on three hosts. Generate the Brewfile from `packages.toml` plus per-host extras, or retire it. | `brew bundle check --file=~/Brewfile` failed on two Apple silicon hosts. | Medium |
| B9 | **Opt-in declarative prune**: `brew bundle cleanup` against `packages.toml`, as a `cz-brew-prune --declared` helper (§3). Depends on B8. | Removing leftovers on four hosts was done by hand. | Low |
| B10 | **Requirement-check fidelity.** The check builds its own `PATH` (`~/.local/bin` first); an interactive shell on an Intel host that also has a Homebrew-built git resolves `/usr/local/bin/git` first. Resolve git through a pseudo-terminal login shell. | Both gits were 2.56.0, so no harm yet. | Low |
| B11 | **Tidy the install script at its next arm64-affecting change:** drop the no-op `export HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1` from the arm64 render (removing it now would re-run the script on arm64 hosts), and add standalone fallbacks for `gitleaks` and `duf` on Intel (bottled today; the hook's requirement check would fail if Homebrew dropped `gitleaks`). | §8.2. | Low |
| B12 | **Test a clean bootstrap.** The whole flow was exercised only on existing machines. Add a periodic run on a clean Apple silicon VM and an Ubuntu container (`CHEZMOI_CI` already skips the system steps). | The first run on a fresh machine would be the first real test of the package order and the fallbacks. | Medium |
| B13 | **Plan the end of the Intel Macs.** macOS 27 drops Intel, Homebrew treats it as Tier 3 and GitHub Actions removes Intel runners in 2027; decide by when the two Intel hosts move to Linux or retire. The bottle-only guard and the standalone git hold until then. | §1.1. | Decision |
| B14 | **Work-specific identifiers in this public repository (done 2026-10-18).** Work organisation names, a work email address and the paths of machine-local secret files appeared in twelve tracked files, the commit history and one commit message, against the rule in the private notes. All three were removed: the wording is neutral and the work env files are now sourced from the machine-local `~/.zshrc.local` instead of `dot_zshrc.tmpl`; the history of every ref was rewritten (`git-filter-repo`) to remove those identifiers and the tailnet name; and the GitHub repository was deleted and recreated, because a force-push alone leaves the old commits fetchable by hash. The `legacy-backup` branch was not restored. `AGENTS.md` §3.3 now states the rule. **Every other clone must be reset to the new history** (`git fetch origin && git reset --hard origin/main`); pushing from an old clone would bring the removed history back. | Found while reorganising these documents on 2026-10-18; verified by a zero-hit scan of a fresh mirror clone. | Done |
