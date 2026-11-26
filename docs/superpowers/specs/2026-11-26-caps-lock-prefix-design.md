# Caps Lock as a One-Key Window Prefix

Date: 2026-11-26. Status: draft, awaiting the user's approval. Builds on
`2026-11-26-mac-window-keys-design.md` (the window keys).

## Intent

The window keys use a three-key prefix: Ctrl+Option+Cmd on the Macs, Ctrl+Alt+Super on Omarchy. Swap and send add
Shift, four modifiers in one hand. The user wants **one key to hold instead of the prefix**, on every machine and
keyboard (Mac laptops, Windows-style keyboards, the Kinesis), **without taking anything essential**. The three-key
prefix keeps working.

## The behaviour (decided with the user)

| You do | You get |
| :--- | :--- |
| Tap Caps Lock (press and release, no other key) | Capitals on/off, exactly as today |
| Hold Caps Lock + a key | The same as holding the prefix + that key: arrows focus, Shift+arrows swap, 1–9 desktop, Shift+1–9 send, L tile (Mac), U rescue |
| Shift, then Caps Lock (Omarchy) | Compose, as today (`omarchy:shift_caps_compose`: the user's `~/.XCompose` snippets and Omarchy's emoji) |

Holding Caps and pressing a letter at the same moment is read as prefix + letter, not a capital. Caps Lock is a
toggle, so ordinary typing never does that.

**Non-goals:** Caps Lock as Escape (the user declined); any other key or a two-key combination (all checked and
rejected below); changing the window keys themselves.

**Anti-goals:** losing Caps Lock's toggle, losing Compose on Omarchy, a key that stops working on an external
keyboard plugged in later, anything that needs SIP off.

## Keys considered (2026-11-26)

- **Caps Lock:** on every keyboard the user has; free once a tap still toggles capitals. Picked.
- Right Option / Right Alt: chezmoi keeps right Option for special characters on the Mac; on Omarchy it is AltGr and
  Omarchy's dictation bindings are written around it.
- Right Cmd / Right Super: missing on many PC keyboards; right-hand Cmd shortcuts on the Mac.
- Fn/Globe: macOS 27's own shortcuts; external keyboards mostly do not send it.
- Right Ctrl, Menu, F13+: missing on Mac laptops.
- Two-key: Cmd+Ctrl is Ghostty's split resize (Mac); Cmd+Option is Chrome's tab switching and Ghostty's split focus;
  Ctrl+Option is tmux/Herdr panes and VoiceOver.

## Approaches (user's choices)

**Mac: macOS's own key remap plus Hammerspoon (picked).** `hidutil` maps Caps Lock (usage 0x700000039) to F18
(0x70000006D) for every keyboard; a LaunchAgent in chezmoi (`~/Library/LaunchAgents`) re-applies it at login.
Hammerspoon watches F18: while it is held, the window keys' keys act as with the prefix (the module's existing
functions); F18 pressed and released with no other key toggles Caps Lock (`hs.hid.capslock.toggle()`).
Rejected: **Karabiner-Elements**: the standard tool, but a new app with a system extension to approve on every Mac
(by hand on the Intel ones).

**Omarchy: keyd (picked).** `omarchy pkg add keyd` (Arch extra, 2.6.0), config `/etc/keyd/default.conf`:
`capslock = overload(window, capslock)` with `[window:C-A-M]`, so a held Caps Lock *is* Ctrl+Alt+Super for every key
(the window-keys guide's bindings fire unchanged) and a tap is Caps Lock. Shift+Caps reaches xkb as Shift+Caps Lock,
so Omarchy's Compose option still applies. A private guide (`~/guides/omarchy/caps-prefix`, apply/undo/status, the
user runs apply.sh in a terminal: sudo) installs the package, writes the file, enables the service.
Rejected: **Hyprland only** (a submap on Caps Lock): Hyprland cannot stop a held Caps Lock from also toggling
capitals, so it would mean replacing Omarchy's own `kb_options`.

## To prove first (a throwaway test on mbp and works)

- Mac: `hidutil` reaches an external keyboard plugged in after login (if not, the LaunchAgent also runs on device
  connect, or match by product); F18 has no other use on macOS 27; Hammerspoon sees F18 down/up and the toggle works;
  the Caps Lock light follows.
- Omarchy: keyd's virtual keyboard keeps Omarchy's per-device input settings (layout, the disabled-input-device rule);
  Shift+Caps still composes (`Compose, Space, N` types the name); Hyprland sees Super+Ctrl+Alt from a held Caps.

## Where it lives

- chezmoi: the Mac LaunchAgent (`dot_Library/LaunchAgents/...`, macOS only), the F18 layer in
  `dot_hammerspoon/window_keys.lua.tmpl`, the requirement check (NOTE + to-do when the remap is not active on a Mac,
  when keyd's guide is not active on Omarchy through `omarchy_guides`), tests, the cheatsheet's "Window Keys".
- Private `~/.cfg`: the Omarchy guide, its README and the guide indexes.

## Left to the builder

The F18 layer's internals (an `hs.eventtap` or `hs.hotkey.modal`), the LaunchAgent's label and trigger, keyd's
exact syntax, test names.
