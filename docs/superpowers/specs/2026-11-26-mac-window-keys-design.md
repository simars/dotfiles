# Window Keys: One Prefix for Windows on the Macs and Omarchy

Date: 2026-11-26. Status: draft, awaiting the user's approval. Reviewed by a builder check; the user settled the
Mission Control question and chose the shared prefix on 2026-11-26.

## Intent

Moving between works (Omarchy, Hyprland) and the Macs (mbp, mbp-work, and the Intel Macs 16i and 32i) should feel like
one way of handling windows, on a Mac keyboard or a Windows-style one. The user's idea: **one stable prefix** for
window keys on both systems, **Ctrl+Option+Cmd** on the Mac and **Ctrl+Alt+Super** on Omarchy, with Shift added for
the "move it" variants. macOS treats a PC keyboard's Win key as Cmd and Alt as Option, so on a Windows-style keyboard
the prefix is the same three physical keys (Ctrl, Win, Alt) on both machines; on the Mac's own keyboard it is the
three keys left of the space bar. It also pairs with tmux and Herdr, where Ctrl+Alt+arrows moves between panes: adding
Super/Cmd steps up from panes to windows.

**Keys on top, not an auto-tiler (Mac).** The user arranges Mac windows mostly with Swish's gestures (its counters on
mbp: fill the screen 182, halves 91, move to another screen 71, move to another desktop 20, full screen 32). A tiling
manager that re-lays windows by itself would undo every Swish snap. So the Mac keys act only when pressed, macOS's own
desktops (Spaces) stay the workspaces, and Swish keeps working exactly as before. On Omarchy the prefix keys are
aliases: Omarchy's own Super keys stay as they are.

## The keys

Prefix **P** = Ctrl+Option+Cmd on the Mac, Ctrl+Alt+Super on Omarchy.

| Keys | Mac (Hammerspoon) | Omarchy (alias of Omarchy's own key) |
| :--- | :--- | :--- |
| P + arrows | Focus the nearest window in that direction, across screens too | Super+arrows (focus) |
| P + Shift + arrows | Swap the focused window with the nearest one in that direction (they trade frames) | Super+Shift+arrows (swap) |
| P + 1–9 | Show desktop N **of the screen under the mouse** | Super+1–9 (each monitor has workspaces 1–10 of its own, `monitor-workspaces.lua`) |
| P + Shift + 1–9 | Send the focused window to desktop N of its screen, and go there with it | Super+Shift+1–9 (move and follow) |
| P + L | Lay out this screen's windows once, dwindle style ("layout") | not bound: Hyprland already tiles |
| P + U | The window rescue (as well as Cmd+Ctrl+U, which stays) | The window rescue (as well as Super+Ctrl+U, which stays) |

Digits on Omarchy use key codes (`code:10`–`code:18`), as Omarchy's own bindings do, so they work on any layout.
Omarchy's 10th workspace (Super+0) and the Mac's desktop 10 are left out, as in the user's "1–9".

## Goals, non-goals, anti-goals

**Goals:** the table above on every Mac (through Hammerspoon, already installed by chezmoi for the window rescue) and
on works (through a private Omarchy guide); per-screen desktop numbers on the Mac, matching Omarchy's per-monitor
workspaces; one on-demand tile on the Mac.

**Non-goals:** automatic tiling or any window-manager app (AeroSpace, yabai, Amethyst); resize, toggle floating, split
direction, pop out, next/previous workspace, moving silently (on macOS a sent window always takes you along); a
one-key prefix (Caps Lock as the prefix needs Karabiner on the Mac and keyd on Omarchy: later, only if the chord
proves tiring).

**Anti-goals (a failure even if it works):**
- Taking a macOS or Omarchy shortcut. On the Mac the previous Cmd+Ctrl design would have taken Ghostty's
  Cmd+Ctrl+arrows (its macOS default resizes splits) and the prefix avoids that; the Mac keys are **only** the prefix
  ones, no Cmd+Ctrl window keys.
- Breaking or second-guessing Swish (its gestures, snapping, move-to-desktop).
- Changing Omarchy's own bindings, or editing `/usr/share/omarchy`.
- Turning off System Integrity Protection; osascript.

## Conflicts checked (2026-11-26)

**Mac** (mbp, macOS 27.2.1, `hs.hotkey.systemAssigned`; mbp-work and 16i have no other hotkey tool: no Karabiner,
Raycast, BetterTouchTool, Alfred or Hyper-key app):
- P + arrows, P + Shift + arrows, P + 1–9, P + L, P + U: free of macOS shortcuts. Ghostty's macOS defaults use none
  of them.
- **P + 8 is macOS's "Invert Colors"** (Accessibility shortcut), off on mbp and not stored on 16i. If someone turns it
  on, macOS takes P + 8 first. The requirement check reports it (NOTE plus a to-do to turn it off) when its
  symbolic hotkey is enabled with Ctrl+Option+Cmd+8.
- P + Shift + 1–0 is where the throwaway test put macOS's hidden desktop shortcuts: they move (below).
- VoiceOver uses Ctrl+Option as its key; only relevant while VoiceOver is on.

**Omarchy** (works, `omarchy menu keybindings --print`, `hyprctl binds`, Ghostty's keybind list):
- Omarchy uses Super+Ctrl+Alt only with letters (C screenshot, F full-screen desktop, T time, B, D, E, R, W, Z, comma,
  Delete): arrows, Shift+arrows, digits, Shift+digits, L and U are free. Hence L, not T, for tile.
- **P + Shift + arrows shadows Ghostty's Super+Ctrl+Alt+Shift+arrows** (resize split by 100) on works: Hyprland takes
  it first. Ghostty keeps Super+Ctrl+Shift+arrows (10) and its leader resize (Super-b, Alt-arrows). Accepted.
- Near miss, not a conflict: tmux and Herdr use Ctrl+Alt+arrows (focus pane) and Ctrl+Alt+Shift+arrows (resize pane);
  P is the same plus Super/Cmd.

**Hands:** swap and send are four modifiers. On a laptop keyboard the left hand holds Ctrl+Option+Cmd and Shift comes
from the right hand; on the Kinesis thumb clusters it is easier. Accepted for now (see non-goals).

## Desktops stay in a fixed order (user's decision, 2026-11-26)

Desktop numbers mean something only while macOS keeps desktops in order. On mbp, mbp-work and 16i,
`com.apple.dock mru-spaces` ("Automatically rearrange Spaces based on most recent use") was unset, which is macOS's
default, **on**: desktops reorder as they are used. The user chose to turn it **off** on every Mac. chezmoi sets,
through `[[macos_defaults]]` in `.chezmoidata/macos.toml`:

- `com.apple.dock` `mru-spaces = false` (Dock group; the Dock restart the script already does).
- `com.apple.spaces` `spans-displays = false` ("Displays have separate Spaces" **on**, macOS's default and what every
  Mac has; `same_when_unset`; takes effect at logout). The per-screen numbering depends on it.

Before adding them, the builder confirms macOS 27.2 still reads these keys as CLAUDE.md 3.5 requires (the user flips
each in System Settings on one Mac while the builder compares `defaults read` before and after), and applies twice:
the second apply must say "match the repo".

## How the Mac side works (proven in a throwaway test on mbp, 2026-11-26)

**Focus and swap** use Hammerspoon's directional window search (`focusWindowWest` and friends, `windowsToWest` and
friends, frontmost only, strict angle). Swap exchanges the two windows' frames and keeps focus on the moved one. No
alert when nothing lies in that direction (Omarchy shows none either).

**Desktops are numbered across screens by macOS.** Its "Switch to Desktop N" shortcuts count every screen's desktops
in Mission Control's display order (`hs.spaces.data_managedDisplaySpaces()`, the main display first): on mbp the
laptop has Desktop 1–8 and the ultrawide Desktop 9–10. Hammerspoon's own space switching (`hs.spaces.gotoSpace`) fails
on macOS 27 ("unable to get Mission Control data from the Dock"), and `hs.spaces.moveWindowToSpace` reports success
but does nothing (Apple closed it in macOS 14.5). So:

1. chezmoi turns on macOS's own **Switch to Desktop 1–16** shortcuts (`com.apple.symbolichotkeys`, ids 118–133) on a
   **hidden combination** nobody presses, then runs `activateSettings -u` so they take effect without a logout. The
   test used Ctrl+Option+Cmd+Shift with the digits, which is now P + Shift + digits, so the hidden combination moves.
   **First choice:** Ctrl+Option+Cmd with the **number-pad** keys (1–9, 0, then `-` `+` `*` `/` `=` `.` for 11–16;
   laptops have no number pad). **Fallback**, if macOS will not take keypad keys there: Ctrl+Option+Shift with the
   digits and `-` `=` `[` `]` `;` `'`, after checking it is free. Either way the builder verifies on mbp that
   Desktop 1, 2, 9 and 10 switch, and reads back ids 128–133 (11–16 cannot be tried live without adding desktops).
2. P + N works out the global number (desktops on the screens before this one, plus N; full-screen app spaces,
   `type` 4, are not desktops) and presses the hidden shortcut. Desktop N beyond the screen's count, or a global
   number above 16: nothing moves, a short alert says why.

**How sending works.** Hammerspoon waits until the keys are released (a held Ctrl turns a click into a right-click),
moves the mouse to an empty, draggable spot at the top of the window, presses the mouse with no modifiers, nudges it
1 px, presses the hidden desktop shortcut, releases after 0.5 s, and puts the mouse back. macOS carries a held window
along to the desktop it switches to. Grab spots: right of the zoom button for ordinary windows; per-app spots for apps
that draw their own top bar:

- Chrome (`com.google.Chrome`): the empty end of the tab strip, 140 px from the right edge, 6 px from the top.
- Slack (`com.tinyspeck.slackmacgap`): left of its search box, min(260 px, 22% of the width) from the left, 14 px down.

Verified on mbp: Warp, Docker Desktop, Chrome and Slack, on both screens.

**Tile (P + L)** takes the standard, visible windows of the focused window's screen (current desktop only), most
recently used first, and gives each half of the space left, alternating left/right and top/bottom (a screen wider
than tall splits left/right first), with an 8 px gap. Nothing re-tiles until the key is pressed again.

**The probe stays, without a key:** `open -g "hammerspoon://window-keys-probe"` drags candidate spots at the top of
the focused window (skipping buttons, tabs and text fields) and logs which ones move it, so an app whose windows will
not send gets its spot added to the table.

## Files

**chezmoi (public repo):**
- `dot_hammerspoon/window_keys.lua` (new, next to `window_rescue.lua`, same style: `start()`, a log at
  `~/Library/Logs/window-keys.log` with one line per send, tile, refused key and probe, never per focus press).
  `dot_hammerspoon/init.lua` starts it after the rescue. P + U calls `window_rescue`'s existing rescue.
- `.chezmoidata/macos.toml`: the two Mission Control keys, and the hidden desktop shortcuts as one table (id, key
  code, character, modifier mask) that both the 97 script and the Lua module read (the Lua file becomes a template),
  so they never disagree.
- `run_after_97_macos_defaults.sh.tmpl`: compare ids 118–133 with the table, write only those that differ, one
  `activateSettings -u`, reported on the existing "macOS settings updated" line.
- `run_after_99_assert_requirements.sh.tmpl`: the Invert Colors check (P + 8).
- `docs/CHEATSHEET.md`: a "Window Keys (macOS and Omarchy)" section beside "Lost and Minimized Windows" with the table,
  the Swish note, the fixed desktop order, the probe.
- `tests/host-profiles.sh`: `luac -p` on the rendered module; darwin and intel manage `.hammerspoon/window_keys.lua`,
  Linux profiles do not; the rendered 97 script writes exactly ids 118–133 with the hidden combination; the two new
  Dock/Spaces keys; key counts in existing assertions updated.

**Private `~/.cfg` (Omarchy):** `~/guides/omarchy/window-keys/` with `README.md`, `apply.sh`, `undo.sh`, `status.sh`,
`common.sh`, the pattern of `wave-keys` and `window-rescue`: a marked block in `~/.config/hypr/bindings.lua` binding
P + arrows, P + Shift + arrows, P + `code:10`–`code:18`, P + Shift + `code:10`–`code:18` to the same actions as
Omarchy's tiling bindings (`hl.dsp.focus({ direction })`, `hl.dsp.window.swap({ direction })`,
`o.workspaces.focus(n)`, `o.workspaces.move_window(n)`), and P + U to the window rescue. apply.sh refuses if any of
those keys is already bound elsewhere, reloads Hyprland and restores the backup on config errors; undo.sh restores
the file byte for byte. Added to `~/guides/README.md`, `~/guides/omarchy/README.md`, and to `omarchy_guides` in
chezmoi's `.chezmoidata/omarchy.toml` (which lists zsh, terminals-clipboard and wave-keys; `window-rescue` is missing
from it too and is added alongside), so the requirement check reports either guide when not active.

## Building from the test, and who checks what

The throwaway module (`spike_keys.lua`, in the session scratchpad and on mbp) is the starting point: its focus, swap,
tile, desktop arithmetic, send sequence, timings and grab table carry over; its test-only parts (per-press log lines,
the desktop-change watcher, the probe key) do not. Checks that need the Mac's screen and keyboard (a desktop switched,
a window carried along, a tile looked right) are the user's, at mbp, with the agent reading the log over SSH. On works
the agent checks bindings with `hyprctl binds` and `configerrors`; the user presses the keys once. Everything else
(rendering, tests, plist values, the apply's output) the agent checks.

## Rollout

mbp, mbp-work, mbp-16i: `chezmoi update` (second apply must say the settings match). Intel Macs need Hammerspoon
installed by hand first (`docs/INTEL_MACS.md`); the desktop shortcuts and the two Mission Control settings are written
either way. 16i runs macOS 26.7.1, where nothing here is tested: it gets one check at its screen once Hammerspoon is
installed; until then, or if a part fails there, a key that cannot act shows an alert and changes nothing. mbp-32i
stays on its held-back chezmoi update (its other pending changes still need a review). works: `apply.sh` of the new
guide. On mbp, remove the throwaway test (`~/.hammerspoon/local.lua`, `~/.hammerspoon/spike_keys.lua`,
`~/Library/Logs/window-keys-spike.log`); the apply rewrites ids 118–127 to the new hidden combination.

## Left to the builder

- Keypad versus fallback hidden combination, by the test above.
- Alert wording.
- Whether swap also works across screens (Hammerspoon's search does by default; keep unless it misbehaves).

## Approaches considered

- **A. Hammerspoon keys on top of Swish and macOS desktops** (picked): nothing new installed, cannot fight Swish.
- **B. yabai with skhd, floating mode**: two more apps from a third-party tap; desktop features need SIP partly off;
  macOS 27 support unconfirmed.
- **C. AeroSpace**: closest to Hyprland, but its own workspaces hide windows off-screen, which defeats Swish's desktop
  gestures and Mission Control and trips the window rescue.

**Prefix:** first Cmd+Ctrl (Super's place on the Mac, like the rescue's Cmd+Ctrl+U); replaced by the user's shared
prefix, which also clears Ghostty's Cmd+Ctrl+arrows and gives a Windows-style keyboard the same keys on both systems.
Fn or Cmd+Fn was rejected: macOS 27 uses Fn for its own tiling, full screen, Control Center, emoji, the Dock,
notifications and Quick Note; the user's external keyboards mostly do not send Fn; neither Hammerspoon hotkeys nor
macOS desktop shortcuts take Fn as a modifier.
