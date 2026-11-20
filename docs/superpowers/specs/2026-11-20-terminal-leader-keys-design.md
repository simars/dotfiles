# Terminal Leader Keys: tmux Letters for the Terminal's Own Tabs and Splits

Date: 2026-11-20. Status: approved by the user 2026-11-20.

## Intent

One keyboard experience in the terminal on every machine: works (Omarchy) and the Macs (mbp*). The user's tmux config
(`dot_config/tmux/tmux.conf`) is the reference: tmux and Herdr must both behave like it. The terminals' own tabs and
splits get the **same letters behind a different prefix**, so a single vocabulary covers everything:

| Prefix | Mac (iTerm2, Ghostty) | Omarchy (Ghostty) | Drives |
| :--- | :--- | :--- | :--- |
| `Ctrl-b`, `Ctrl-Space` | same | same | tmux and Herdr, inside the terminal |
| `Cmd-b` | `Cmd-b` | `Super-b` | the terminal's own tabs and splits |

Omarchy already treats Super as the Mac's Cmd (Super+C / Super+V copy and paste), so `Cmd-b` and `Super-b` are the
same key in the user's hands. iTerm2's docs recommend Cmd-B as its leader
([iTerm2 Keys](https://iterm2.com/documentation-preferences-keys.html)).

Precedence the user set: tmux and Herdr behave like the user's tmux; the Mac behaves like a Mac and Omarchy like
Omarchy (their own shortcuts are never taken); Herdr's own shortcuts and the terminals' own shortcuts are the most
flexible and may be moved or dropped.

## Scope

- **Terminals:** iTerm2 (Mac only), foot (Omarchy only), Ghostty (both). iTerm2 and Ghostty have native tabs and
  splits; foot has neither.
- **Out of scope:** Wave and Warp (their cheatsheet sections stay as they are), Alacritty and kitty, tmux control mode
  (`tmux -CC`; Ghostty 1.4 still has it unwired, issue ghostty-org/ghostty#1935), nesting Herdr inside tmux (parked,
  see "Parked: nesting").
- foot stays Omarchy's default terminal (`~/.config/xdg-terminals.list`). Hyprland leaves Super+B to the focused
  window, so foot receives it. *Builder's call (2026-11-20):* test whether foot passes Super+B on to the program
  (with tmux extended keys or the kitty protocol it may); if it does, bind it to `noop` in foot's `[key-bindings]`
  through the existing foot.ini modify mechanism (extend it; it currently sets only `selection-target`).
- **Herdr desktop app (`herdr-app`, both platforms):** *builder's call:* not given a leader (it is Herdr's own UI,
  like Wave and Warp it stays out of the leader scheme). It reads the same `~/.config/herdr/config.toml`, and on works
  runs its own engine (`herdr-core`, binary `hc`), so the new keys (prefix array included) must be checked against the
  app as well as `herdr config check`; if the app rejects one, keep the app working (template the key out for it is
  not possible, so prefer a form both accept) and record it.

## Goals

1. Herdr's keys are the user's tmux keys wherever Herdr has the action; each tmux key Herdr lacks is listed as
   emulated or a known gap (table below). Herdr gets `Ctrl-Space` as a second prefix, as tmux has `prefix2`.
2. iTerm2 and Ghostty get a leader (`Cmd-b` on the Mac, `Super-b` on Omarchy) followed by tmux's letters for their own
   tabs and splits.
3. The Macs' native Cmd shortcuts (Cmd+T, Cmd+D, Cmd+Shift+D, Cmd+W, Cmd+1..9, Cmd+Opt+arrows, Cmd+[ ]) keep working
   in both Mac terminals. Ghostty's stock Linux keys that do not clash (Ctrl+Shift+T/W/C/V, Ctrl+Tab, Ctrl+PgUp/PgDn)
   keep working on Omarchy.
4. Nothing in the chain takes a key another layer needs: desktop (Hyprland, macOS) → terminal → tmux/Herdr →
   programs (Claude Code, zsh, Neovim). Verified per terminal, not assumed.

## Non-goals and anti-goals

- Not changing Hyprland or macOS shortcuts. If one is needed, it is a failure of this design.
- Not changing the tmux keys the user already has (beyond terminal-feature lines that make keys arrive).
- Anti-goal: a terminal leader that ever reaches a program as stray input, or a leader layer that takes a key Claude
  Code, zsh or Neovim uses.
- Anti-goal: Omarchy's Ghostty losing its theme include, Omarchy's own keybinds or the existing chezmoi unbinds.

## Approaches considered

1. **Ctrl+Shift chords only on Omarchy's Ghostty** (Ghostty's Linux defaults, tidied). One press, but it runs out of
   keys: Alt and Ctrl+Alt belong to tmux/Herdr, Super+Ctrl+Shift+arrows to Hyprland, Ctrl+Alt+Shift+arrows to tmux
   resize. Resize and go-to-tab-N would land on unrelated chords. Rejected.
2. **A Ghostty-only leader on Omarchy** (`Ctrl+Shift+Space`), Mac stays Cmd. Works, but the Mac and Omarchy would use
   different leaders and iTerm2 would have none.
3. **Chosen: `Cmd-b` / `Super-b` leader in both iTerm2 and Ghostty, tmux's letters after it, native keys kept.** Same
   physical key and same letters on every machine and both terminals; the native Cmd and Ctrl+Shift keys stay for
   people (and muscle memory) that use them.

## Design

### 1. The leader layer (Ghostty, both platforms)

Delivered by the existing modify script `dot_config/ghostty/modify_config.tmpl` (the block it appends; Omarchy and
Ghostty own the rest of the file). The leader is `cmd+b` on darwin and `super+b` on Linux.

Ghostty mechanism: a one-shot key table, so an unbound letter after the leader is swallowed instead of reaching the
program (`catch_all=ignore`), and a nested modal table for resize:

```ini
keybind = super+b=activate_key_table_once:term     # cmd+b on macOS
keybind = term/catch_all=ignore
keybind = term/escape=deactivate_all_key_tables
keybind = term/c=new_tab
keybind = term/r=activate_key_table:term_resize
keybind = term_resize/h=resize_split:left,20
keybind = term_resize/escape=deactivate_all_key_tables
keybind = term_resize/catch_all=ignore
```

Letter map (same letters as the user's tmux; Ghostty action in brackets):

| Key after leader | tmux meaning | Ghostty action |
| :--- | :--- | :--- |
| `c` | new window | `new_tab` |
| `%`, `v` | split right | `new_split:right` |
| `"`, `-` | split down | `new_split:down` |
| `h` `j` `k` `l`, arrows | focus pane | `goto_split:left/down/up/right` |
| `;` / `o` | last pane / next pane | `goto_split:previous` / `goto_split:next` |
| `x` | kill pane | `close_surface` |
| `z` | zoom | `toggle_split_zoom` |
| `1`..`9` | go to window | `goto_tab:N` |
| `n` / `p` | next / previous window | `next_tab` / `previous_tab` |
| `,` | rename window | `prompt_tab_title` |
| `&` | kill window | `close_tab` |
| `r`, then `h j k l` (repeat), `Esc`/`Enter` to leave | resize | `resize_split:<dir>,20` in table `term_resize` |
| `=` | (tmux `E`, spread evenly) | `equalize_splits` |
| `!` | break pane | `move_tab_to_new_window` is the nearest; builder decides whether to bind it |
| `?` | key list | `toggle_command_palette` |

Key names (`"`, `%`, `&`, `;`, `,`, `=`, `?`) must be checked with `ghostty +validate-config`: a scratch test showed
`term/percent` is rejected while `term/"` is accepted. Use whatever trigger spelling validates; drop a letter only if
no spelling does, and say so in the cheatsheet.

Mac Ghostty: confirm Ghostty binds nothing to `cmd+b` by default (`ghostty +list-keybinds --default` on a Mac). Its
Cmd defaults already match iTerm2's (`cmd+d`, `cmd+shift+d`, `cmd+t`, `cmd+w`, `cmd+1..9`, `cmd+alt+arrows`,
`cmd+[`/`]`, `cmd+shift+enter`); list any difference in the cheatsheet rather than rebinding.

Closing asks first, as in tmux and Herdr (user's decision, 2026-11-20): the Ghostty block sets
`confirm-close-surface = true` on both platforms. On Omarchy this replaces Omarchy's `confirm-close-surface=false`
(the awk drops that line by key), so Ghostty's own close keys (Ctrl+Shift+W) also ask while a program is running in
the split. The awk matches `confirm-close-surface=false` without spaces around `=`: test that.

Omarchy Ghostty: keep the existing chezmoi unbinds (Ctrl+Enter, Alt+1..9, Ctrl+Alt+arrows). Ghostty's stock
Ctrl+Shift split keys (`ctrl+shift+o`/`e`) and its Super+Ctrl split keys may stay; they do not clash.

**awk compatibility:** `.chezmoitemplates/kv-settings.awk.sh` keys a `keybind` line by its trigger (text before the
second `=`), so `term/c` and `super+b` are distinct triggers and existing Omarchy bindings stay. Add tests for table
triggers and for a trigger containing `"` or `=`-free punctuation. If a trigger itself contains `=` (`term/=`), the
awk's `sub(/=.*$/, ...)` cuts it short: handle that (match the first `=` after the trigger, or use Ghostty's `equal`
key name if it validates).

### 2. The leader layer (iTerm2, Mac)

iTerm2 has a global **Leader** (Settings > Keys) and leader bindings (leader followed by one key). Delivery is not
yet known and is the first task on a Mac:

1. **Discovery spike (on a Mac, by hand, reversible):** export iTerm2's prefs
   (`defaults export com.googlecode.iterm2 -`), set Leader = Cmd-B and add two leader bindings in Settings > Keys >
   Key Bindings, export again and diff. Record the preference keys (the leader itself and how leader bindings appear,
   likely in `GlobalKeyMap`) and the action codes.
2. **Delivery:** extend `run_after_96_macos_iterm2.sh.tmpl` to ensure those entries, merging into the existing global
   key map without removing the user's other bindings (same "write only what differs, report, never fail the apply"
   pattern as `ensure_global`; iTerm2 reads them at start, so the existing "quit and reopen iTerm2" to-do applies).
   Data for the bindings goes in `.chezmoidata/macos.toml` next to `iterm2_globals`.
3. **Action map:** same letters as Ghostty. iTerm2 key-binding actions cover new tab, split vertically/horizontally
   with current profile, select split pane left/right/above/below, next/previous tab, close; anything else via its
   "Select Menu Item" action (zoom = Maximize Active Pane, rename tab = Edit Tab Title, go to tab N, resize = move
   divider if a menu item exists). A letter with no action is bound to iTerm2's "Ignore" action (*builder's call*: the anti-goal says a leader never
   leaks a stray key into the program; if iTerm2 drops unbound leader letters itself, skip that) and listed in the
   cheatsheet. iTerm2's
   leader is one key per press, so resize repeat (`r` then `h j k l`) may not exist; fall back to iTerm2's native
   resize keys and say so.
4. The shared profile sets `"Keyboard Map": {}`. Check that profile key maps do not shadow global leader bindings.

The Macs were unreachable over SSH during design (2026-11-20). Mac tasks run when one is reachable or from a session
on the Mac.

### 3. Herdr like the user's tmux

In `dot_config/herdr/config.toml.tmpl`:

- `prefix = ["ctrl+b", "ctrl+space"]` (array prefixes since Herdr 0.9.2). On Omarchy, Hyprland's Ctrl+Space bind
  (input method) is `non_consuming`, so the key still reaches the terminal.
- Add tmux defaults the user relies on that Herdr can do: `(` / `)` previous / next workspace (tmux switch-client
  -p/-n), `f` goto picker (tmux find-window), `PageUp` copy mode if Herdr accepts the key name.
- Herdr-only features keep keys tmux leaves unused: `b` sidebar, `Shift-o` notification target, `Shift-s` settings,
  `Shift-g` new worktree. A Herdr default that shadows a tmux key the user uses is removed.

Gap list (cheatsheet gets a short "tmux keys Herdr lacks" line):

| tmux | Herdr | Treatment |
| :--- | :--- | :--- |
| `Space`, `M-1..5`, `E` layouts | no live layouts | gap |
| `C-o` rotate panes | none | gap |
| `]`, `#`, `=` paste buffers | none (community plugin only) | gap |
| `:` command prompt | none | gap |
| `q` pane numbers | goto picker | already mapped |
| `m` mark pane, `.` move window, `'` index prompt | none | gap |
| repeat (`bind -r`) | resize mode / direct resize chords | already mapped |

**Version and restart:** the running Herdr server on works is 0.9.1 (client 0.9.5); a prefix array needs a server
on ≥ 0.9.2. Herdr's docs say an invalid value falls back to a safe default (prefix `ctrl+b`), so the old server only
lacks Ctrl-Space until it is replaced; test that once. The server reports `live_handoff: true`: check whether
`herdr update --handoff` (or an equivalent) replaces it without closing panes and prefer that in the to-do; otherwise
restarting closes its panes, so it is the user's step. Add a check to
`run_after_99_assert_requirements.sh.tmpl`: when `herdr status` reports a stale server binary, print a NOTE and
`todo "Restart the Herdr server when no work is open in it (herdr server stop), so it runs <version>"`. Also check the
installed Herdr is ≥ 0.9.2 before relying on the array (if older on a host, the requirement check says to update).
`herdr config check` validates with the client binary only.

### 4. tmux: make the keys arrive

No key changes. Verify extended keys per terminal with `tmux display -p '#{client_termfeatures}'` (look for
`extkeys`) in iTerm2, foot and Ghostty, locally and over SSH. tmux before 3.8 does not detect Ghostty: add
`set -as terminal-features 'xterm-ghostty:extkeys'` (harmless on 3.8). foot runs with `TERM=xterm-256color` from
Omarchy's foot.ini; if `extkeys` is missing there, add a matching terminal-features line that targets foot without
touching other xterm-256color clients, or document the gap. Test Ctrl+Enter and Shift+Enter reaching Claude Code
inside tmux in each terminal.

### 5. Desktop guards

- **Omarchy:** Super+B must stay unbound in Hyprland. The requirement check (Omarchy, when `hyprctl` answers) warns
  and adds a to-do if `hyprctl binds -j` shows a SUPER-only `B` bind, naming the binding.
- **macOS:** the user never switches input language. macOS's "Select the previous input source" (Ctrl+Space) would
  take tmux's `prefix2`. The iTerm2/macOS after-script checks `com.apple.symbolichotkeys` (AppleSymbolicHotKeys id 60)
  and, if enabled, adds a to-do to turn it off in System Settings > Keyboard > Keyboard Shortcuts > Input Sources.
  Check only; do not write system shortcuts.

### 6. Documentation

- `docs/CHEATSHEET.md` (mandatory, same commit as each change): new section "Terminal Tabs and Splits (`Cmd-b` /
  `Super-b`)" with the letter table per terminal; update "tmux and Herdr Keys" (Ctrl-Space for Herdr, new keys, gap
  line) and "Keys the Terminal Must Not Take" (Super+B, Cmd+B, Ctrl+Space on macOS).
- `docs/NEW_MACHINE.md`: the macOS input-source step, if the check above adds a to-do.
- `docs/FUTURE_CONSIDERATIONS.md`: "Parked: nesting" (below).
- `AGENTS.md` 4.2: mention the Ghostty leader block in the modify-script sentence.

## Parked: nesting Herdr inside tmux

The user sometimes runs Herdr inside tmux but parked it on 2026-11-20. Both use `Ctrl-b`, and tmux also takes the
shared no-prefix chords (Alt-1..9, Alt-Enter, Ctrl-Alt-arrows). Today `Ctrl-b Ctrl-b` reaches Herdr (tmux
send-prefix). Two options to revisit:

- **A. Ctrl-Space goes to the inner one, no mode.** tmux binds `Ctrl-Space` and the shared chords with
  `if -F '#{==:#{pane_current_command},herdr}'` → `send-keys`, else the tmux action. Modeless; inside Herdr the hand
  uses Ctrl-Space. Cannot see Herdr behind ssh.
- **B. One key turns the outer tmux off.** A toggle (e.g. F12, key to be checked on all three terminals and both
  desktops) sets the outer tmux's key table to an empty one, greys its status bar with `OFF`, and passes every key on;
  the same key restores it. Covers ssh nesting too. Recommended base; A can be added on top.

## Testing

- `tests/host-profiles.sh`: rendered Ghostty block per host (darwin `cmd+b`, omarchy `super+b`), awk keeps Omarchy's
  bindings and is idempotent with table triggers, Herdr prefix array on every host, the requirement-check additions
  render only where they apply.
- `ghostty +validate-config` on the rendered Omarchy config (on works) and on a Mac.
- `herdr config check`; after the user restarts the server, `herdr status` shows no stale binary.
- Hands-on matrix (works: foot, Ghostty; Mac: iTerm2, Ghostty), each local and over SSH into tmux: leader letters do
  their job; tmux prefix and Ctrl-Space work; `client_termfeatures` has `extkeys`; Ctrl+Enter/Shift+Enter reach
  Claude Code; OSC 52 copy from tmux and Herdr lands in the local clipboard.
- `gitleaks`, `cheat` rendering, `chezmoi diff` before `chezmoi apply`.

## Left to the builder

Exact Ghostty trigger spellings, the iTerm2 preference format (from the spike), the resize step size, whether `!`
gets bound, and the precise wording of checks and cheatsheet rows.
