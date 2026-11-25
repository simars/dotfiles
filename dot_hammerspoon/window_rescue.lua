-- Window rescue: bring back windows that Cmd+Tab picks but does not show.
--   Cmd+Ctrl+U        the frontmost app (the one Cmd+Tab just picked): unhide it, restore its minimized windows, pull
--                     its off-screen windows back
--   Cmd+Ctrl+Shift+U  every app: restore all minimized windows and pull every off-screen window back
-- Each window it brings back is stacked on the screen you are using: centered, each next one 40 px down and right,
-- the last one focused. Windows on another Space are left there (Cmd+Tab already switches to their Space), and so are
-- windows that are simply on another screen. Omarchy's Super+Ctrl+U does the off-screen part there.
-- Also triggered by `open -g "hammerspoon://window-rescue"` (add `?all=1` for every app), for testing over SSH.
-- Each run adds one line to ~/Library/Logs/window-rescue.log.

local M = {}

local STEP = 40
local LOG = os.getenv("HOME") .. "/Library/Logs/window-rescue.log"

-- Off-screen = the window's center is outside every screen (the same rule as Omarchy's rescue.sh).
local function onAnyScreen(frame)
  local cx, cy = frame.x + frame.w / 2, frame.y + frame.h / 2
  for _, screen in ipairs(hs.screen.allScreens()) do
    local f = screen:fullFrame()
    if cx >= f.x and cx < f.x + f.w and cy >= f.y and cy < f.y + f.h then return true end
  end
  return false
end

-- Add the app's minimized (restoring them) and off-screen standard windows to `found`.
local function collect(app, found)
  for _, win in ipairs(app:allWindows()) do
    if win:isStandard() then
      if win:isMinimized() then
        win:unminimize()
        table.insert(found, win)
      elseif not onAnyScreen(win:frame()) then
        table.insert(found, win)
      end
    end
  end
end

local function place(win, screen, i)
  local area = screen:frame() -- without the menu bar and Dock
  local f = win:frame()
  f.w = math.min(f.w, area.w * 0.9)
  f.h = math.min(f.h, area.h * 0.9)
  f.x = area.x + (area.w - f.w) / 2 + i * STEP
  f.y = area.y + (area.h - f.h) / 2 + i * STEP
  win:setFrame(f, 0)
end

local function log(line)
  local file = io.open(LOG, "a")
  if file then
    file:write(os.date("%Y-%m-%d %H:%M:%S "), line, "\n")
    file:close()
  end
end

function M.rescue(allApps)
  local screen = hs.screen.mainScreen()
  local found, scope = {}, nil

  if allApps then
    scope = "every app"
    for _, app in ipairs(hs.application.runningApplications()) do
      if app:kind() == 1 then collect(app, found) end -- 1 = an app with a Dock icon; skips agents and daemons
    end
  else
    local app = hs.application.frontmostApplication()
    if not app then return end
    scope = app:name()
    if app:isHidden() then app:unhide() end
    collect(app, found)
  end

  for i, win in ipairs(found) do
    place(win, screen, i - 1)
    win:raise()
  end
  if #found > 0 then found[#found]:focus() end

  local names = {}
  for _, win in ipairs(found) do
    local app = win:application()
    table.insert(names, app and app:name() or "?")
  end
  local summary = #found == 0 and ("Nothing minimized or off-screen in " .. scope)
    or ("Brought back " .. #found .. " (" .. scope .. "): " .. table.concat(names, ", "))
  hs.alert.show(summary, 1.5)
  log(summary)
end

function M.start()
  M.hotkeys = {
    hs.hotkey.bind({ "cmd", "ctrl" }, "u", function() M.rescue(false) end),
    hs.hotkey.bind({ "cmd", "ctrl", "shift" }, "u", function() M.rescue(true) end),
  }
  hs.urlevent.bind("window-rescue", function(_, params) M.rescue(params.all == "1") end)
end

return M
