-- Hammerspoon's config, managed by chezmoi (dot_hammerspoon/ in the chezmoi source); macOS only.
-- Cheatsheet: "Lost and Minimized Windows" and "Window Keys". Per-Mac additions go in ~/.hammerspoon/local.lua, which chezmoi leaves alone.

hs.window.animationDuration = 0 -- move windows at once, no slide
hs.autoLaunch(true)              -- start at login
-- Moving windows needs Accessibility (macOS 27: Device Control and Data Access), allowed once by hand
-- (docs/NEW_MACHINE.md). Never checked here: on macOS 27.2 the check reports "not allowed" even when it is, and asking
-- showed macOS's dialog on every config reload.

require("window_rescue").start()
require("window_keys").start()

local localConfig = hs.configdir .. "/local.lua"
if hs.fs.attributes(localConfig) then dofile(localConfig) end

-- Reload when a .lua file here changes (a chezmoi apply, or an edit), so no reload step is needed. Global, so the
-- watcher is not garbage-collected.
configWatcher = hs.pathwatcher.new(hs.configdir, function(paths)
  for _, path in ipairs(paths) do
    if path:sub(-4) == ".lua" then
      hs.reload()
      return
    end
  end
end):start()
