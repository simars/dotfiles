# Intel Macs: Installing Tools by Hand

`chezmoi apply` installs no packages on an Intel Mac: it writes the dotfiles and runs the requirement check, nothing more. Homebrew compiles every formula that has no Intel bottle (one apply built `llvm`, `rust` and `node` for 7 hours), so tools there are installed by hand, with the steps below. Apple silicon Macs still get everything from `.chezmoidata/packages.toml` automatically.

The commands and pinned versions are the ones the package script used before 2026-10-30, when it still automated this. A newer release installs the same way; check its release page for the file name.

## 1. Find what Homebrew can install without compiling

Run this on the Intel Mac itself: Homebrew reports bottles only for the platform it runs on. It takes about 5 minutes. It runs under `bash`, because zsh does not split `$list` into words.

```bash
bash <<'EOF'
export HOMEBREW_NO_AUTO_UPDATE=1
list=$(sed -n '/^formulae = \[/,/^\]/p' ~/.local/share/chezmoi/.chezmoidata/packages.toml | grep -o '"[^"]*"' | tr -d '"')
bottled() { brew info --json=v2 --formula "$1" 2>/dev/null | jq -r '.formulae[0].bottle.stable.files // {} | keys[]' | grep -qvE '^(arm64_.*|.*_linux)$'; }
installed() { brew list --formula "$1" > /dev/null 2>&1; }
for f in $list; do
  missing=""
  for d in $f $(brew deps --formula "$f" 2>/dev/null); do bottled "$d" || installed "$d" || missing="$missing $d"; done
  if installed "$f"; then echo "$f: installed"; elif [ -z "$missing" ]; then echo "$f: pour"; else echo "$f: compile:$missing"; fi
done
EOF
```

- `pour`: install it with `brew install <name>`. A bottle for an older Intel macOS (`sonoma`, say) pours on newer ones.
- `compile:` lists the formulae Homebrew would have to build. Do not `brew install` these; use section 3, or go without.

## 2. Result on `simars-macbook-32i` (2026-10-30, Homebrew 7.0.10, macOS 26.7.1)

| State | Formulae |
| :--- | :--- |
| Installed with Homebrew | `btop`, `duf`, `fd`, `findutils`, `fzf`, `gitleaks`, `gnu-sed`, `jq`, `make`, `pstree`, `ripgrep`, `starship`, `tmux`, `watch`, `zoxide`, `zsh` |
| Pours | `grep` |
| Standalone binary instead (section 3) | `age`, `bat`, `dust`, `fx`, `herdr`, `mise`, `neovim`, `git` (built, section 4), plus `timeout` in place of `coreutils` and `ip` in place of `iproute2mac` |
| Go without, or another source | `bash` (Apple's `/bin/bash` 3.2 is enough: Claude Code uses it there), `bitwarden-cli`, `colima`, `coreutils`, `curl` (Apple's works), `docker`, `docker-compose` (Docker Desktop brings both), `eza` (`ll` falls back to `ls -lah`), `gawk`, `gnu-tar`, `httpie` (mise's Python installs it, from `~/.config/mise/default-python-packages`), `rsync` (Apple's `openrsync`), `shellcheck`, `vim` (Apple's), `wget` |

Casks are prebuilt apps, so `brew install --cask <name>` does not compile; install the ones whose app still ships an Intel build (`1password-cli`, `font-jetbrains-mono-nerd-font`, `iterm2`, `warp`, `wave`).

## 3. Standalone binaries

Each goes into `~/.local/bin`, which `~/.zprofile` puts on `PATH`. Run `mkdir -p ~/.local/bin` first.

| Tool | Command |
| :--- | :--- |
| mise | `curl https://mise.run \| sh` |
| starship (if not from Homebrew) | `curl -sS https://starship.rs/install.sh \| sh -s -- --yes --bin-dir ~/.local/bin` |
| zoxide (if not from Homebrew) | `curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh \| bash` |
| age 1.3.2 | `curl -fsSL https://github.com/FiloSottile/age/releases/download/v1.3.2/age-v1.3.2-darwin-amd64.tar.gz \| tar -xz -C ~/.local/bin --strip-components=1 age/age age/age-keygen` |
| fzf 0.56.3 (if not from Homebrew) | `curl -fsSL https://github.com/junegunn/fzf/releases/download/v0.56.3/fzf-0.56.3-darwin_amd64.tar.gz \| tar -xz -C ~/.local/bin fzf` |
| herdr 0.9.5 | `curl -fsSL https://github.com/herdrdev/herdr/releases/download/v0.9.5/herdr-macos-x86_64 -o ~/.local/bin/herdr && chmod +x ~/.local/bin/herdr` |
| Neovim 0.12.6 | `curl -fsSL https://github.com/neovim/neovim/releases/download/v0.12.6/nvim-macos-x86_64.tar.gz \| tar -xz -C ~/.local --strip-components=1` |
| bat 0.26.1 | `curl -fsSL https://github.com/sharkdp/bat/releases/download/v0.26.1/bat-v0.26.1-x86_64-apple-darwin.tar.gz \| tar -xz -C ~/.local/bin --strip-components=1 bat-v0.26.1-x86_64-apple-darwin/bat` |
| dust 1.2.6 | `curl -fsSL https://github.com/bootandy/dust/releases/download/v1.2.6/dust-v1.2.6-x86_64-apple-darwin.tar.gz \| tar -xz -C ~/.local/bin --strip-components=1 dust-v1.2.6-x86_64-apple-darwin/dust` |
| fx 40.0.0 | `curl -fsSL https://github.com/antonmedv/fx/releases/download/40.0.0/fx_darwin_amd64 -o ~/.local/bin/fx && chmod +x ~/.local/bin/fx` |
| lazygit and tree-sitter-cli | Needed by Neovim's LazyVim config (the `lazygit` window, and compiling Treesitter parsers on first launch). Apple silicon gets them from `packages.toml`. On Intel take the macOS x86_64 binaries from their GitHub releases into `~/.local/bin`; `brew install` them only if section 2's check does not report `compile` |
| LunarVim (optional; not managed by chezmoi) | `bash <(curl -fsSL https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh) --yes --no-install-dependencies` (after Neovim) |

**`timeout`**, from uutils coreutils 0.12.0, one multicall binary that runs as whatever it is called:

```bash
tmp="$(mktemp -d)"
curl -fsSL -o "$tmp/uutils.tar.gz" https://github.com/uutils/coreutils/releases/download/0.12.0/coreutils-0.12.0-x86_64-apple-darwin.tar.gz &&
echo "a845b274f91c23b779f097e15045f4bf7cbcf99d6e62e6878d9db816e6887586  $tmp/uutils.tar.gz" | shasum -a 256 -c - &&
tar -xzf "$tmp/uutils.tar.gz" -C "$tmp" --strip-components=1 coreutils-0.12.0-x86_64-apple-darwin/coreutils &&
mv "$tmp/coreutils" ~/.local/bin/coreutils && ln -sfn coreutils ~/.local/bin/timeout
rm -rf "$tmp"
```

**`ip`, `bridge` and `ss`**, from iproute2mac 1.7.6. They are Python scripts that need Python 3.10 or newer (Apple's `/usr/bin/python3` is 3.9), so the wrappers run them on mise's Python:

```bash
tmp="$(mktemp -d)" home="$HOME/.local/share/iproute2mac"
curl -fsSL -o "$tmp/ir.tar.gz" https://github.com/brona/iproute2mac/releases/download/v1.7.6/iproute2mac-1.7.6.tar.gz &&
echo "a5b8e4ec28e38232d5b9b149d824598fd561336e5456af39dfa21a75d707dfde  $tmp/ir.tar.gz" | shasum -a 256 -c - &&
tar -xzf "$tmp/ir.tar.gz" -C "$tmp" --strip-components=1 iproute2mac-1.7.6/src &&
rm -rf "$home" && mv "$tmp/src" "$home" &&
for cmd in ip bridge ss; do
  printf '#!/bin/sh\nif command -v mise > /dev/null 2>&1; then exec mise exec python -- python3 "%s/%s.py" "$@"; fi\nexec python3 "%s/%s.py" "$@"\n' "$home" "$cmd" "$home" "$cmd" > ~/.local/bin/$cmd
  chmod +x ~/.local/bin/$cmd
done
rm -rf "$tmp"
```

## 4. git 2.54 or newer, for the global hooks (optional)

The global hooks in `~/.gitconfig` (the gitleaks secret scan and the identity guard) are defined in config, which git runs only from 2.54. Apple's git on an Intel Mac stops at 2.50.1 (Xcode 27 is Apple silicon only) and Intel Homebrew has no git bottle, so without this build commits on the Intel Mac are not scanned; the requirement check says so with a `WARN`. The build takes about a minute and needs the Command Line Tools (`xcode-select --install`):

```bash
work="$(mktemp -d)" && cd "$work" &&
curl -fsSL -o git.tar.xz https://mirrors.edge.kernel.org/pub/software/scm/git/git-2.56.0.tar.xz &&
echo "26c56c296b38c0695b26fa95f475f1d01704d2d38e73465ca30b0b2f5dc789d3  git.tar.xz" | shasum -a 256 -c - &&
tar -xJf git.tar.xz && cd git-2.56.0 &&
make -j"$(sysctl -n hw.ncpu)" prefix="$HOME/.local" NO_RUST=YesPlease NO_GETTEXT=YesPlease NO_TCLTK=YesPlease all &&
make prefix="$HOME/.local" NO_RUST=YesPlease NO_GETTEXT=YesPlease NO_TCLTK=YesPlease install &&
make -C contrib/credential/osxkeychain prefix="$HOME/.local" NO_RUST=YesPlease NO_GETTEXT=YesPlease NO_TCLTK=YesPlease &&
install -m 755 contrib/credential/osxkeychain/git-credential-osxkeychain ~/.local/libexec/git-core/
cd ~ && rm -rf "$work"
# Apple's git takes its keychain credential helper from its own system config; give this git the same.
[ -e ~/.local/etc/gitconfig ] || { mkdir -p ~/.local/etc && printf '[credential]\n\thelper = osxkeychain\n' > ~/.local/etc/gitconfig; }
```

Without `NO_RUST` the build stops at `cargo: command not found`, and the keychain helper must be built with the same flags or it fails to link. GUI apps that call `/usr/bin/git` still skip the hooks.

## 5. Check

`chezmoi apply` ends with the requirement check: `OK` for git and gitleaks when both are in place, `WARN` for a git older than 2.54, and `FAIL` without gitleaks (`brew install gitleaks` pours on Intel).
