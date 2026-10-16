# Cross-Platform Dotfiles (`chezmoi` + `mise` + `age`)

Deterministic workstation setup for **macOS (Apple Silicon & Intel)** and **Ubuntu Linux 26.04 LTS**.

## Fresh Machine Bootstrap

### 1. Provision Age Secret Key (Optional if using encrypted files)
```bash
mkdir -p ~/.config/chezmoi
nano ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt
```

### 2. Initialize & Apply Dotfiles
```bash
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply git@github.com:<your-username>/dotfiles.git
```

### 3. Activate Docker Group on Ubuntu (Without Logging Out)
```bash
newgrp docker
```

## Day-to-Day Operations
* **Edit a managed file:** `chezmoi edit ~/.zshrc`
* **Add a new file:** `chezmoi add ~/.config/some-tool/config.toml`
* **Add an encrypted secret:** `chezmoi add --encrypt ~/.ssh/id_ed25519`
* **Pull & apply latest changes:** `chezmoi update`
