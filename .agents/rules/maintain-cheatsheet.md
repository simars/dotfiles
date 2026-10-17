---
description: Maintain workstation cheatsheet whenever shell aliases, packages, or run_onchange scripts are modified
globs:
  - "dot_aliases"
  - ".chezmoidata/packages.toml"
  - "dot_zshrc.tmpl"
  - "run_onchange_*"
---

# Rule: Maintain Workstation Cheatsheet

> **Scope & Triggers:** This rule is automatically triggered whenever referencing, adding, modifying, or removing configurations in:
> - `dot_aliases`
> - `.chezmoidata/packages.toml`
> - `dot_zshrc.tmpl`
> - `run_onchange_*` (e.g. bootstrap scripts, package installers, runtime hooks)

Whenever modifying any of the triggered files above, the agent **MUST** adhere to the following mandatory workflow:

1. **Update `docs/CHEATSHEET.md`:**
   - Add, update, or remove the corresponding tool, CLI utility, shell alias, keybinding, or workflow in [`docs/CHEATSHEET.md`](file:///Users/simars/.local/share/chezmoi/docs/CHEATSHEET.md).
   - Maintain consistent table formatting, column alignment, and clear explanations.

2. **Verify Rendering:**
   - Verify that the cheatsheet renders properly and without syntax or formatting issues using:
     ```bash
     zsh -c 'source dot_aliases && cheat | head -n 30'
     ```
   - Ensure `bat`, `less`, and fallback `cat` output modes are respected and work without errors.

3. **Atomic Commits:**
   - Ensure both configuration/code changes and documentation updates in `docs/CHEATSHEET.md` are committed together in the same atomic commit or task.
   - Never submit code changes that alter available utilities, packages, or aliases without updating the documentation.
