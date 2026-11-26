# Mac Window Keys: Omarchy's Window Keys on Cmd+Ctrl, Beside Swish

Date: 2026-11-26. Status: draft, awaiting the user's approval. Reviewed by a builder check; the user settled the
Mission Control question (below) on 2026-11-26.

## Intent

Moving between works (Omarchy, Hyprland) and the Macs (mbp, mbp-work, and the Intel Macs 16i and 32i) should feel like
one way of handling windows. On works the user focuses, swaps and moves windows and switches workspaces from the
keyboard. The Macs get the same keys, with **Cmd+Ctrl standing in for Super**, the pattern already set by the window
rescue (Omarchy Super+Ctrl+U, Mac Cmd+Ctrl+U).

**Keys on top, not an auto-tiler.** The user arranges Mac windows mostly with Swish's gestures (its counters on mbp:
fill the screen 182, halves 91, move to another screen 71, move to another desktop 20, full screen 32). A tiling
manager that re-lays windows by itself would undo every Swish snap. So the keys act only when pressed, macOS's own
desktops (Spaces) stay the workspaces, and Swish keeps working exactly as before.

## Goals

- The Omarchy window keys the user relies on, on every Mac, through Hammerspoon (already installed by chezmoi for the
  window rescue; its config is `dot_hammerspoon/`).
- Desktop numbers **per screen**, like Omarchy's workspaces: "desktop 2" is the second desktop of the screen you are
  on.
- One on-demand key that lays out the windows of a screen the way Hyprland's dwindle layout does.

## Non-goals

- Automatic tiling, and any new window-manager app (AeroSpace, yabai, Amethyst).
- Omarchy keys beyond the table below: resize (Super+minus/equal), toggle floating, split direction (Super+J), pop out
  (Super+O), next/previous workspace (Super+Tab; macOS already has Ctrl+Left/Right), moving silently
  (Super+Shift+Alt+N; on macOS the window always takes you with it, see "How sending works").

## Anti-goals (a failure even if it works)

- Taking a macOS shortcut. Checked on mbp (Hammerspoon's `hs.hotkey.systemAssigned`): Cmd+Ctrl+Shift+3, 4, 5 and 6 are
  macOS's screenshot keys, so "send to desktop" does **not** use Cmd+Ctrl+Shift+N. Cmd+Ctrl+F (full screen) and
  Cmd+Ctrl+Q (lock screen) stay macOS's.
- Breaking or second-guessing Swish (its gestures, its snapping, its move-to-desktop).
- Turning off System Integrity Protection, or osascript.
- Option (Alt) alone as the modifier: chezmoi makes left Option the terminals' Alt.

## The keys

| Omarchy (works) | Mac | What it does on the Mac |
| :--- | :--- | :--- |
| Super+arrows | **Cmd+Ctrl+arrows** | Focus the nearest window in that direction, across screens too |
| Super+Shift+arrows | **Cmd+Ctrl+Shift+arrows** | Swap the focused window with the nearest one in that direction (they trade frames) |
| Super+1–9 | **Cmd+Ctrl+1–9** | Show desktop N of the screen under the mouse |
| Super+Shift+1–9 | **Cmd+Ctrl+Option+1–9** | Send the focused window to desktop N of its screen, and go there with it |
| (automatic) | **Cmd+Ctrl+T** | Lay out this screen's windows once, dwindle style (below). Omarchy's Super+T toggles floating; on the Mac, T means tile |
| Super+F | Cmd+Ctrl+F | macOS's own full screen, unchanged |
| Super+Ctrl+U | Cmd+Ctrl+U | The window rescue, unchanged |

All verified free on mbp (macOS 27.2.1, 2026-11-26) apart from Cmd+Ctrl+F and Cmd+Ctrl+U, which are listed because
they are the Mac's existing counterparts.

## Desktops stay in a fixed order (user's decision, 2026-11-26)

Desktop numbers mean something only while macOS keeps desktops in order. On mbp, mbp-work and 16i,
`com.apple.dock mru-spaces` ("Automatically rearrange Spaces based on most recent use") was unset, which is macOS's
default, **on**: desktops reorder as they are used, so "desktop 2" drifts. Omarchy's workspaces never move. The user
chose to turn it **off** on every Mac. chezmoi sets, through `[[macos_defaults]]` in `.chezmoidata/macos.toml`:

- `com.apple.dock` `mru-spaces = false` (Dock group, takes effect with the Dock restart the script already does).
  Mission Control and Swish's desktop swipes then show desktops in the order the user arranged them.
- `com.apple.spaces` `spans-displays = false` ("Displays have separate Spaces" **on**, macOS's default and what every
  Mac has now; `same_when_unset`, takes effect at logout). The per-screen numbering depends on it.

Before adding them, the builder confirms macOS 27.2 still reads these keys the way CLAUDE.md 3.5 requires (the user
flips each in System Settings on one Mac while the builder compares `defaults read` before and after), and applies
twice: the second apply must say "match the repo".

## How it works (proven in a throwaway test on mbp, 2026-11-26)

**Focus and swap** use Hammerspoon's directional window search (`focusWindowWest` and friends, `windowsToWest` and
friends, frontmost only, strict angle). Swap exchanges the two windows' frames and keeps focus on the moved one.

**Desktops are numbered across screens by macOS.** Its "Switch to Desktop N" shortcuts count every screen's desktops
in Mission Control's display order (`hs.spaces.data_managedDisplaySpaces()`, the main display first): on mbp the laptop
has Desktop 1–8 and the ultrawide Desktop 9–10. Hammerspoon's own space switching (`hs.spaces.gotoSpace`) fails on
macOS 27 ("unable to get Mission Control data from the Dock"), and moving a window between spaces through the API
(`hs.spaces.moveWindowToSpace`) reports success but does nothing (Apple closed it in macOS 14.5). So:

1. chezmoi turns on macOS's own **Switch to Desktop 1–16** shortcuts (`com.apple.symbolichotkeys`, ids 118–133) on a
   combination nobody presses: **Cmd+Ctrl+Option+Shift** with `1`–`0` for Desktops 1–10 and with `-` `=` `[` `]` `;`
   `'` for 11–16, then runs `activateSettings -u` so they take effect without a logout. Ids 118–127 with the digits
   are verified on mbp (Desktop 10 = id 127 moved Chrome to the ultrawide's second desktop); 11–16 follow the same
   pattern and are the builder's to verify (see "Left to the builder").
2. Cmd+Ctrl+N works out the global number (desktops on the screens before this one, plus N; full-screen app spaces,
   `type` 4, are not desktops) and presses that hidden shortcut. Desktop N beyond the screen's count, or a global
   number above 16: nothing moves, a short alert says why.

**How sending works.** Hammerspoon waits until the keys are released (a held Ctrl turns a click into a right-click),
moves the mouse to an empty, draggable spot at the top of the window, presses the mouse with no modifiers, nudges it
1 px, presses the hidden desktop shortcut, releases after 0.5 s, and puts the mouse back. macOS carries a held window
along to the desktop it switches to, so the user always follows the window. Grab spots: right of the window's zoom
button for ordinary windows; per-app spots for apps that draw their own top bar, found with a probe that drags each
candidate spot and checks whether the window moved:

- Chrome (`com.google.Chrome`): the empty end of the tab strip, 140 px from the right edge, 6 px from the top.
- Slack (`com.tinyspeck.slackmacgap`): left of its search box, min(260 px, 22% of the width) from the left, 14 px down.

Verified on mbp: Warp, Docker Desktop, Chrome and Slack, on both screens.

**Tile (Cmd+Ctrl+T)** takes the standard, visible windows of the focused window's screen (the current desktop only;
minimized and hidden windows stay put), most recently used first, and gives each half of the space left, alternating
side and top/bottom split (wider than tall: the first split is left/right), with an 8 px gap. Swish can rearrange
them afterwards; nothing re-tiles until the key is pressed again.

## Files and where things go

- `dot_hammerspoon/window_keys.lua`: the keys (new module, next to `window_rescue.lua`, same style: a `start()`, a
  log at `~/Library/Logs/window-keys.log` with one line per send, tile and failed key, never per focus press).
  `dot_hammerspoon/init.lua` starts it after the rescue.
- **The probe stays, without a key**: `open -g "hammerspoon://window-keys-probe"` probes the focused window and logs
  which top spots drag it, so a new app whose windows will not send gets its spot added to the table. Documented in
  the cheatsheet.
- **The desktop shortcuts** are written by `run_after_97_macos_defaults.sh.tmpl` (it already owns "the same macOS
  settings on every Mac"): compare each of ids 118–133 with the wanted value, write only those that differ, then one
  `activateSettings -u`, and report them on the existing "macOS settings updated" line. The table of ids, key codes
  and characters lives in one place in `.chezmoidata/macos.toml`, which the Lua module reads too (chezmoi template) so
  the two never disagree.
- `run_after_99_assert_requirements.sh.tmpl`: nothing new beyond what the Hammerspoon check already reports.
- `docs/CHEATSHEET.md`: a "Window Keys (macOS and Omarchy)" table beside "Lost and Minimized Windows", with the Swish
  note (gestures unchanged) and the probe.
- `docs/NEW_MACHINE.md`: nothing new to do by hand (Hammerspoon's first-open step already covers it).
- `tests/host-profiles.sh`: `luac -p` on the new module; darwin and intel manage `.hammerspoon/window_keys.lua`, Linux
  profiles do not; the rendered 97 script on darwin writes exactly ids 118–133 with the hidden combination; the key
  counts in existing assertions updated.

## Building from the test, and who checks what

The throwaway module (`spike_keys.lua`, kept in the session scratchpad and on mbp until the rollout) is the starting
point: its focus, swap, tile, desktop arithmetic, send sequence, timings and grab table are proven and carry over;
its test-only parts (the per-press log lines, the desktop-change watcher, the probe on a key) do not. Checks that need
the Mac's screen and keyboard (a desktop switched, a window carried along, a tile looked right) are the user's, at
mbp, with the agent reading the log over SSH; everything else (rendering, tests, plist values, the apply's output) the
agent checks.

## Rollout

mbp, mbp-work, mbp-16i: `chezmoi update` as usual (second apply must say the settings match). Intel Macs need
Hammerspoon installed by hand first (`docs/INTEL_MACS.md`); the desktop shortcuts and the two Mission Control settings
are written either way. 16i runs macOS 26.7.1, where nothing here is tested: it gets one check at its screen once
Hammerspoon is installed; until then, or if a part fails there, a key that cannot act shows an alert and changes
nothing. mbp-32i stays on its held-back chezmoi update (its other pending changes still need a review), so it gets
none of this for now.

No Mac has another global-hotkey tool (Karabiner, Raycast, BetterTouchTool, Alfred, a Hyper-key app; checked on mbp,
mbp-work and 16i, 2026-11-26), so Cmd+Ctrl, Cmd+Ctrl+Option and Cmd+Ctrl+Option+Shift are free beyond macOS's own
shortcuts. On mbp, remove the throwaway test: `~/.hammerspoon/local.lua`,
`~/.hammerspoon/spike_keys.lua`, `~/Library/Logs/window-keys-spike.log`; ids 118–127 there were written by the test and
are rewritten to the same values by the apply.

## Left to the builder

- Verify ids 128–133 (Desktops 11–16) map as expected on one Mac, or, if a live check would need adding desktops the
  user does not want, verify by reading the plist back and say so.
- The exact alert wording, and whether focus/swap with no neighbour shows an alert (Omarchy shows nothing).
- Whether swap should also work across screens (Hammerspoon's search does it by default; keep unless it misbehaves).

## Approaches considered

- **A. Hammerspoon keys on top of Swish and macOS desktops** (picked by the user): nothing new installed, cannot fight
  Swish, same Cmd+Ctrl habit as the rescue.
- **B. yabai with skhd, floating mode**: two more apps from a third-party tap; its desktop features need SIP partly
  off; macOS 27 support unconfirmed.
- **C. AeroSpace**: closest to Hyprland, but its own workspaces hide windows off-screen, which defeats Swish's desktop
  gestures and Mission Control and trips the window rescue.

Fn or Cmd+Fn as the modifier was considered and rejected: macOS 27 uses Fn for its own tiling, full screen, Control
Center, emoji, the Dock, notifications and Quick Note; the user's external keyboards mostly do not send Fn; and
neither Hammerspoon hotkeys nor macOS desktop shortcuts take Fn as a modifier.
