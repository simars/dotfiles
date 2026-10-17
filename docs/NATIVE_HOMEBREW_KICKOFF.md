# Native Homebrew Changeover: Session Kickoff Prompt

`Simars-MacBook-Work` finished its first chezmoi migration on the Intel Homebrew it inherited, running under Rosetta (see `TESTING_AND_VERIFICATION_GUIDE.md` §9). Paste the prompt below into a new agent session on that machine to switch it to native `/opt/homebrew`. Fill in the two `[yes/no]` lines first: a new session does not inherit earlier push permissions.

```text
Continue the dotfiles migration on Simars-MacBook-Work (Apple M2 Max, macOS 26.6.2): switch from the Intel Homebrew running under Rosetta at /usr/local to native Homebrew at /opt/homebrew.

Read first: ~/.local/share/chezmoi/AGENTS.md, docs/FUTURE_CONSIDERATIONS.md §8, and docs/TESTING_AND_VERIFICATION_GUIDE.md §9. Backups from the first pass are in ~/.dotfiles.backup.20261017_163746/.

Current state: chezmoi is applied and ~/dotfiles is retired. The Intel brew has Command Line Tools 11.7, which refuses to install on macOS 26. mise and its go/node/python runtimes are x86_64. ~/.local/bin comes before Homebrew on PATH and holds fallback binaries: bat, dust, fx, duf, gitleaks, age and herdr (arm64) and mise (x86_64).

Rules:
- ~/.cfg and the `config` alias must keep working alongside chezmoi; check `config status` and `config fsck` after each step.
- Run gitleaks yourself before every commit (the hook passes silently if the binary is missing). Update docs/CHEATSHEET.md in the same commit as any tool, alias or package change.
- Commit as Simar Singh <simarpaulsingh@gmail.com>, no Co-Authored-By trailer. Linear history: fast-forward pushes only.
- Push authorized: [yes/no]. Propagate to simar-mbp, simars-macbook-32i and simars-macbook-16i (.example-tailnet.ts.net, ssh -A with ~/.ssh/id_rsa): [yes/no].
- Wave is my running terminal: never reinstall or force-adopt the wave cask from inside Wave.

Steps, in order. Ask me before doing anything not listed:
1. Update the Command Line Tools to a macOS 26 release; I'll run anything that needs sudo myself. Confirm with `pkgutil --pkg-info=com.apple.pkg.CLTools_Executables`.
2. I install Homebrew in my own terminal with the official installer. Then check that `/opt/homebrew/bin/brew config` shows arm64 and no Rosetta.
3. Run the package script natively without touching chezmoi's state: render it with `chezmoi execute-template < ~/.local/share/chezmoi/run_onchange_before_00_install_packages.sh.tmpl` into a scratch file, then run it with /bin/bash (not `env bash`, which resolves to the Rosetta bash). Do not delete chezmoi's state buckets.
4. Adopt the casks with native brew: `brew install --cask --force iterm2 warp alacritty`. Leave wave for me to do from a different terminal.
5. Formulae: compare `/usr/local/bin/brew leaves` with the Brewfile tracked in ~/.cfg, and show me the list before installing natively (include mysql-client@8.4, gh and openjdk if still used).
6. mise: `brew install mise`, remove ~/.local/bin/mise, then `rm -rf ~/.local/share/mise/installs && mise install` (the existing x86 install directories count as installed). Check that `file "$(mise which node)"` reports arm64.
7. Remove each ~/.local/bin fallback (bat dust fx duf gitleaks age herdr) only after /opt/homebrew/bin/<tool> exists.
8. Run `/usr/local/bin/brew uninstall rcm` and `gh auth login -h github.com`. Ask me before retiring the Intel brew itself.
9. Verify: `brew --prefix` is /opt/homebrew; `file $(whence -p eza bat btop duf dust jq fx mise git gitleaks)` all report arm64; `mise doctor`; `node -p process.arch`; `go version`; PATH order. Then re-run the full Step 5 suite (the 8 binaries, guarded aliases, config co-existence, mise ls/current, cheat, the repo-only agent checks, the age round trip, gitleaks).
10. Record the results in TESTING_AND_VERIFICATION_GUIDE.md §9 and close out §8.1 in FUTURE_CONSIDERATIONS.md.
```
