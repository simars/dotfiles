# Future Considerations & Platform Roadmap

This document outlines key future considerations, platform lifecycle changes, and automated remediation strategies using **`chezmoi`**.

---

## 1. Intel macOS (x86_64) Lifecycle & Homebrew Tier 3 Transition

### 1.1 Platform Context
* **Apple Transition:** Intel x86_64 support is discontinued in macOS Golden Gate (macOS 27).
* **GitHub Actions:** Deprecating Intel macOS runners in 2027.
* **Homebrew Support Tier 3:** As of September 2026, Homebrew officially categorized macOS on Intel x86_64 as **Tier 3** (best-effort, no official maintenance, discontinued new bottle builds).
* **Source Fallback Hazard:** When a formula lacks an x86_64 bottle, Homebrew by default attempts to compile the entire dependency tree (LLVM, Rust, CMake, OpenSSL) from source. If Xcode or Command Line Tools (CLT) are outdated, the build crashes after downloading gigabytes of source code.

### 1.2 Chezmoi Handling & Mitigation
* **Bottle Fallback Suppression:**
  In `run_onchange_before_00_install_packages.sh.tmpl`, we set:
  ```bash
  export HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1
  brew bundle --no-upgrade --file=/dev/stdin
  ```
  This skips unbottled formulae instead of locking the system into endless source compilation.
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

## 2. Xcode Command Line Tools Automation

### 2.1 The Issue
On older Intel machines running newer macOS releases (such as macOS 26 Tahoe/Sequoia), existing Command Line Tools (e.g. from Xcode 14.3.1) fail with:
```text
Error: Your Command Line Tools (CLT) does not support macOS 26.
```
This blocks any local compilation (native gems, pip wheels, or local C tools).

### 2.2 Chezmoi Handling
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

## 3. Homebrew Formula Pruning & Cellar Hygiene

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

## 4. macOS Keychain SSH Passphrase Automation

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

## 5. Shell Navigation & Package Registry Completeness (`zoxide` & `fzf`)

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

## 6. Apple Silicon (`arm64`) Workstation Invariants & Lifecycle

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
| **Intel Source Fallback Hangs**| ✅ Build Protection | `HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1` + `--no-upgrade` |
| **Apple Silicon Prefix & Bottles**| ✅ Native Resolution | Dynamic `/opt/homebrew` shellenv + Tier 1 native bottle pouring |
| **SSH-RSA Mixed Case Error** | ✅ External Binary Engine | `useBuiltin = false` delegates to native `age` binary |

---

## 8. Deferred Items from the `Simars-MacBook-Work` Migration (2026-10-17)

### 8.1 Native Homebrew Changeover (`Simars-MacBook-Work`) (resolved 2026-10-17)
* **Kickoff prompt:** [`NATIVE_HOMEBREW_KICKOFF.md`](NATIVE_HOMEBREW_KICKOFF.md) holds the session prompt with the ordered steps; results are in `TESTING_AND_VERIFICATION_GUIDE.md` §9.6.
* Resolved: native Homebrew 7.0.9 runs from `/opt/homebrew`. The blocker was never a real "CLT 11.7" install but a stale 2019-2020 `/Library/Developer/CommandLineTools` directory that overrode Xcode 27.1; it was removed and replaced with CLT 26.6.
* Resolved: `mise` and its Go, Node and Python runtimes are native arm64, and the `~/.local/bin` fallbacks (`bat`, `dust`, `fx`, `duf`, `gitleaks`, `age`, `age-keygen`, `herdr`, `mise`) are gone.
* Resolved: `rcm` was uninstalled from all four hosts on 2026-10-17, so a stray `rcup` cannot recreate the thoughtbot symlinks.
* Resolved: `gh auth login -h github.com` renewed the invalid token; the native `gh` is logged in.
* Resolved: the `wave` cask was adopted by the later `chezmoi apply` (Caskroom symlink only; `Wave.app` untouched), and all 20 `~/go/bin` tools are native arm64 (`gopls` and `staticcheck` moved to their latest releases because the pinned versions no longer compile on Go 1.27).
* Still open: the Intel brew in `/usr/local` is installed and cannot be retired as a plain uninstall. It still hosts a running Redis 8.8.0 launchd service (44 keys), MySQL data for `work_development` and `work_test` in `/usr/local/var/mysql` (91 MB, written by Intel `mysql` 9.3.0), and CLI casks whose `/usr/local/bin` links (`copilot`, `op`) point into the Intel Caskroom. Intel-only leaves with no native twin: `go`, `nvm`, `nvtop`, `python@3.8`, `python@3.9`, `python@3.10`, `rbenv`, `rc`, `v8@3.15` (superseded or dead). Brew also left `/usr/local/etc/gitconfig`, which nothing reads.

### 8.2 Install Script Gaps
* `gitleaks` and `duf` have no darwin standalone fallback in `run_onchange_before_00_install_packages.sh.tmpl`. Note that any edit to that script changes its hash and re-runs `brew bundle` on every host.
* The script's `#!/usr/bin/env bash` resolves to `/usr/local/bin/bash` (x86_64) on a Rosetta-brew Mac, so runtime-detecting installers such as `mise.run` pick x86_64. `#!/bin/bash` runs natively on Apple Silicon and exists on Ubuntu.

### 8.3 Per-Repo Exclude Lists on Other Hosts (resolved 2026-10-17)
* Every git dir on `simar-mbp` (38), `simars-macbook-32i` (92) and `simars-macbook-16i` (252) now links `.git/info/exclude` to `~/.config/git/info-exclude`, as does `~/.cfg` on all four hosts. Before, the mbp and 16i links dangled into the deleted `~/dotfiles`, and 32i's pointed to git's stock template with no patterns, so those hosts gained about 166 ignore patterns. §6.3's "zero broken symlinks" had covered home-level links only.
* The thoughtbot hook shims (3,456 across the three hosts) were removed. On 32i the template `pre-commit` had been rewritten to run `gitleaks --config "$REPO_ROOT/.gitleaks.toml"`; no repo had that file, so it aborted every commit in 93 git dirs.

### 8.4 Identity and Legacy Leftovers
* Resolved: the work identity lives in `~/.gitconfig.local` (machine-local, not managed by chezmoi) on all four hosts. It includes `~/.gitconfig.work` (`simar.singh@work.example`) for remotes in the `work`, `WORK-ORG-2` and `WORK-ORG-3` orgs and for clones under `~/work/`, `~/WORK-ORG-2/` and `~/WORK-ORG-3/`. A repo's own `user.email` still wins.
* Resolved: thoughtbot leftovers retired on 32i and 16i with tarballs in `~/.dotfiles.legacy.*.tar.gz`. 16i's `~/dotfiles` was not thoughtbot but a clean clone of this repo at `672f6ff` (the `legacy-backup` branch), and `~/symlinks.dotfiles.thoughtbot` held 20 saved links; both are archived and removed.
* Retiring the thoughtbot `zsh/configs` left `EDITOR`/`VISUAL` unset, so `alias e="$EDITOR"` expands to nothing; thoughtbot shell functions (`mcd`, `envup`, `change-extension`) and `~/.bin` scripts (`git-up`, `tat`, `replace`) are gone.
* Resolved: a global gitleaks pre-commit hook (config-defined, Git 2.54+) now replaces the per-repo thoughtbot template; see §8.5 for the git versions it depends on.
* Resolved: `rcm` uninstalled from all four hosts (Homebrew, no dependents).

### 8.5 Git 2.54+ for the Global Secret Scan
The gitleaks hook is a config-defined hook, which git before 2.54 ignores without any warning. `run_after_99_assert_requirements` checks the terminal git and Apple's `/usr/bin/git` (used by GUI apps) after every apply. As of 2026-10-17:

| Host | Terminal git | `/usr/bin/git` | Remaining step |
|---|---|---|---|
| `Simars-MacBook-Work` | 2.56.0 (Homebrew, native) | 2.54.0 (Xcode 27.1) | None: the requirement check passes. |
| `simar-mbp` | 2.56.0 (Homebrew) | 2.54.0 (Xcode 27.1 selected) | None: the requirement check passes. |
| `simars-macbook-32i` | 2.50.1 | 2.50.1 (Xcode 26.2; CLT 26.6 is also installed) | macOS is now 26.7.1. Not reachable with Apple tooling (see below); needs a decision. |
| `simars-macbook-16i` | 2.50.1 | 2.50.1 (CLT 26.6 selected) | macOS is now 26.7.1. Xcode 14.3.1 stopped running on it (git crashed while it was selected), so CLT 26.6 was installed and selected. Same open decision as 32i. |

* Xcode 27.1 ships Apple Git-157 (2.54.0). Command Line Tools 26.6, installed on all four hosts, bundle Apple Git-155 (2.50.1), so a CLT alone cannot meet the requirement. Verify `/usr/bin/git --version` after any toolchain change.
* **Xcode 27 runs only on Apple silicon.** Apple's release notes, as quoted in the developer forums, say so, and a beta failed on an Intel MacBook under Tahoe 26.5. The Intel hosts therefore cannot reach Apple git 2.54 through Xcode, and Intel Homebrew has no git bottle for macOS 26. The "Fix" text printed by `run_after_99_assert_requirements` for these hosts (install Xcode 27.1) is wrong for Intel.
* Options for the Intel hosts: (a) a standalone git 2.54+ ahead of `/usr/bin/git` on PATH, built from source because no bottle exists, which fixes terminal commits but leaves GUI apps (minimal PATH, `/usr/bin/git`) unscanned, together with relaxing the Apple-git assertion on Intel; (b) leave the check failing as a visible reminder; (c) drop the global hook on Intel hosts and rely on per-repo hooks.
* Intel Homebrew has no git bottle for macOS 26, so on the Intel hosts the Apple toolchain is the upgrade path.

