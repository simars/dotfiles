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

