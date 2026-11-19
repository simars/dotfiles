# Design: The same iTerm2 on every Mac

**Date:** 2026-11-19
**Status:** Approved (approach A, mbp-work's look with JetBrains Mono, plus the Claude hook check and copy on select)
**Size:** medium change

## Intent

The user wants iTerm2 to look and behave the same on every Mac that runs these dotfiles. Today it doesn't. chezmoi's
profile, "Default (Left Option as Alt)", sets only left Option and the Claude Code workgroup triggers. Everything else
comes from each Mac's own "Default" profile and global settings, which chezmoi doesn't touch, and those differ (checked
2026-11-19):

| Setting | mbp | mbp-work |
|---|---|---|
| Font | Monaco 12, no icons | Hack Nerd Font Mono 12 (`HackNFM-Regular`), installed on mbp-work only |
| Separate non-ASCII font | off | on (Hack Nerd Font Mono 11) |
| Ligatures | off | on (no visible effect: Hack has none) |
| Colours | iTerm2's original palette: black background, bright classic colours | the "Atom" preset (all 23 colour keys equal) |
| Bell | sound | silent, screen flashes |
| Global settings | iTerm2's defaults | double-click selects smartly, no tab bar in full screen, no Touch Bar Esc feedback, prints in black and white, pasted tabs become 4 spaces |

The same on both: window 80×25, scrollback 1000 lines, key mappings, no transparency, bold font. The other global
differences are per-Mac state (window frames, `NoSync*` keys, update checks) and stay per Mac.

The same change also does what the earlier plan did:
- It stops iTerm2 running the Claude triggers inside full-screen apps (the "triggers are pretty slow" warning on mbp).
- It checks the default profile.
- It reports settings saved on one Mac only.

## Goals

- One shared look and one set of global settings, kept in the repo, given to every Mac by `chezmoi apply`.
- A repo switch for triggers in full-screen apps, off.
- Each apply says, with `OK:` or `NOTE:`:
  - whether the global settings match;
  - whether the chezmoi profile is the default;
  - whether the Claude Code integration is installed;
  - which settings were changed in iTerm2 on this Mac only.

## Non-goals and anti-goals

- No iTerm2 "load settings from a folder" (approach C). No editing of iTerm2's main preferences file except
  individual global keys with `defaults write`.
- chezmoi does not install the Claude Code integration, and does not set the default profile. It checks both and says
  how.
- `ToolbeltTools`, window frames and other per-Mac state stay per Mac. Setting `ToolbeltTools` to mbp's
  `["Session Status"]` would replace mbp-work's toolbelt (recent directories, history).
- No change to the profile file name `chezmoi-option-as-alt.json` or the profile name "Default (Left Option as Alt)".
- Anti-goals:
  - A check that fails or blocks an apply.
  - Anything work-related in the public repo.

## Approaches

**A, chosen: a shared look profile owned by chezmoi.**
- A second dynamic profile, never rewritable, holds the look and the trigger switch.
- The existing rewritable profile takes it as its parent instead of each Mac's "Default".
- Global settings are written key by key from a list in `.chezmoidata/macos.toml`.
- iTerm2 never saves into the shared file, so nothing flip-flops.
- Local edits land in the child profile, and the report names them.

**B, rejected: put the look into the existing profile.** iTerm2 drops keys equal to the parent when it rewrites a
rewritable profile. mbp-work's "Default" already has this look, so there the look would be stripped and re-added on
every apply. Local edits and shared settings would also mix in one file.

**C, rejected: iTerm2's own settings sync from a folder.** It shares the whole preferences file, so the last Mac to
save wins. It would fight chezmoi's own iTerm2 handling, and the file cannot live in the public repository.

## The shared look (the picks)

| Setting | Pick | Why |
|---|---|---|
| Font | JetBrains Mono Nerd Font Mono 12 (`JetBrainsMonoNFM-Regular 12`) | chezmoi already installs it on every Apple-silicon Mac (`font-jetbrains-mono-nerd-font`, all variants), and Omarchy's terminals use JetBrains Mono. The Nerd Font icons (eza, prompts, lazygit, Neovim) show instead of boxes. The Mono variant keeps icons one column wide, as mbp-work's Hack Nerd Font Mono did, so full-screen apps line up. |
| Separate non-ASCII font | off (`Use Non-ASCII Font` false; `Non Ascii Font` set to the same font so it names nothing missing) | The Nerd Font already carries the icons. |
| Ligatures | off (ASCII and non-ASCII) | iTerm2 turns off GPU rendering in a session with ligatures on ("GPU rendering is off in the current session because ligatures are enabled"), the opposite of what mbp needs. mbp-work's ligature setting did nothing visible with Hack. |
| Colours | mbp-work's (the "Atom" preset), including badge, cursor guide and link colours | A deliberate choice, unlike mbp's out-of-the-box palette. |
| Bell | silent, screen flashes | Agents and full-screen apps ring the bell often. |
| Size, scrollback, keys, everything else | mbp-work's "Default" values, which equal mbp's | Already the same. |

The shared profile is mbp-work's "Default" profile, captured once, without identity and per-Mac keys (`Name`, `Guid`,
`Description`, `Default Bookmark`, `Shortcut`, `Tags`, `Working Directory`), without `Option Key Sends` (the child
sets left Option), and with the picks above applied. Its parent is "Default" by name, so it never inherits from
itself through the default profile.

## Global settings (in `.chezmoidata/macos.toml`)

`AllowClipboardAccess` true (moved from the clipboard script, behaviour unchanged), `CopySelection` true (copy on
select, iTerm2's default, now pinned), `DoubleClickPerformsSmartSelection` true, `ShowFullScreenTabBar` false,
`HapticFeedbackForEsc` false, `SoundForEsc` false, `VisualIndicatorForEsc` false, `Print In Black And White` true,
`PasteTabToStringTabStopSize` 4.

## Design

**Files (macOS only; `Library` is already ignored elsewhere):**

1. `.chezmoidata/macos.toml`:
   - `iterm2_triggers_in_interactive_apps = false`.
   - An `[iterm2_globals]` table with the settings above.
   - Comments in the style of `.chezmoidata/omarchy.toml`: switch for good, or try without a commit.
2. `…/iTerm2/DynamicProfiles/chezmoi-0-shared-look.json.tmpl`: a plain file chezmoi owns entirely, with one profile:
   - `Name`: "Shared Look (chezmoi)".
   - `Guid`: `chezmoi-shared-look`.
   - `Dynamic Profile Parent Name`: "Default".
   - The captured settings.
   - `"Enable Triggers in Interactive Apps": {{ .iterm2_triggers_in_interactive_apps }}`. Writing `true` is safe here,
     because iTerm2 never rewrites this file.

   Its name sorts before `chezmoi-option-as-alt.json`, because iTerm2 loads dynamic profiles in alphabetical order by
   filename and a parent must load before its children.
3. `…/modify_chezmoi-option-as-alt.json` stays a plain modify script, not a template. It:
   - sets `Dynamic Profile Parent GUID` to `chezmoi-shared-look` (iTerm2 3.4.9 and later; the GUID beats the name);
   - deletes `Dynamic Profile Parent Name`, `Right Option Key Sends` (now from the shared look) and
     `Enable Triggers in Interactive Apps`, so the repo's switch always wins;
   - keeps `Name`, `Guid`, left `Option Key Sends` 2, `Rewritable` true and the two Claude triggers as today;
   - passes everything else through, and leaves non-JSON alone.
4. `run_after_96_macos_terminal_clipboard.sh.tmpl` becomes `run_after_96_macos_iterm2.sh.tmpl`. It is informational,
   always exits 0, and is silent without iTerm2 (`ITERM2_APP`, default `/Applications/iTerm.app`, is the only test
   hook). In order:
   1. Global settings: write each key from `iterm2_globals` that differs (`-bool` / `-int` by type). Print `OK:` when
      none differ. Otherwise list the ones written, with "reopen iTerm2" when it is running.
   2. Default profile: `OK:` or `NOTE:` with the steps, as before.
   3. Claude Code integration: `OK:` when `~/.config/iterm2/it2` exists and `~/.claude/settings.json` has a hook
      command containing `iterm2/it2`. Otherwise `NOTE:` with "iTerm2 > Install Claude Code Integration".
   4. Local changes: list the keys in the child profile beyond `Name`, `Guid`, `Dynamic Profile Parent GUID`,
      `Option Key Sends`, `Rewritable`, `Triggers`, plus any trigger other than the two Claude ones. Print `OK:` when
      there are none. Otherwise `NOTE:` naming them as changed on this Mac only, with how to share them (move them
      into the shared look) or drop them.
5. Cheatsheet: the iTerm2 row and a short "Same iTerm2 on every Mac" block covering:
   - what is shared, and where it lives;
   - how to change it;
   - the switch;
   - the checks;
   - what stays manual.

**First, a spike (throwaway):** on mbp-work, check that iTerm2 3.7.7 resolves a dynamic profile whose
`Dynamic Profile Parent GUID` names a dynamic profile from an earlier-sorting file. Use two temporary files, and
delete them afterwards. If it fails, stop and come back to the user: the fallback is approach B, with its
flip-flop.

## What stays manual

- Once per new Mac:
  - Install the Claude Code integration from iTerm2's menu (the check reminds you).
  - Set the chezmoi profile as the default (the check reminds you).
  - Reopen iTerm2 after the first apply, so global settings load.
  - Warp's Option setting, if Warp is used. Warp syncs it through its account.
- This rollout:
  - Reopen iTerm2 once on each Mac after the apply. herdr sessions on works survive; reattach.
  - Glance at both Macs to confirm they look the same, and that `claude` in a local tab still opens the workgroup.
- Ongoing:
  - The look changes in the repo, then push, then `chezmoi update` on each Mac.
  - Changes made in iTerm2's Settings stay on that Mac, and the report says so.
- Not covered:
  - macstudio (not on chezmoi).
  - An Intel Mac's font (tools are installed by hand there).
  - Per-Mac state.

## Side effects

- mbp's look changes completely (font, colours, bell) on the next apply. mbp-work's changes only in font and
  ligatures, and its GPU rendering comes back.
- A second profile, "Shared Look (chezmoi)", appears in iTerm2's profile list, and cannot be hidden. Editing it in
  iTerm2 lasts only until the file reloads.
- Each Mac's own "Default" profile matters only for keys neither profile sets. Those are iTerm2's built-in values
  today, so they are the same everywhere unless someone edits a "Default" profile by hand.
- The repo overrides iTerm2's checkboxes for the shared settings and the trigger switch at the next apply.
- A few more lines on every apply on a Mac.

## Left to the builder

- Exact `NOTE:` wording within the constraints above.
- How the capture is done: a one-off command whose output becomes the template. It is not kept in the repo.
- The test layout (render templates through `chezmoi --override-data`, plus stub `defaults` and `pgrep`, as in the
  plan).
