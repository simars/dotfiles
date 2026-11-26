-- A stand-in for the parts of Hammerspoon that dot_hammerspoon/window_keys.lua uses, for tests/host-profiles.sh.
-- Usage: lua tests/hammerspoon-stub.lua RENDERED_MODULE SCENARIO
-- Prints what the module did as one line: the events it posted, in order, and any alert.
-- Timers run at once; the clock advances 0.5 s per read, so a wait for released keys times out after a few reads.

local module, scenario = arg[1], arg[2]
local events = {}
local function record(what) events[#events + 1] = what end

local held = scenario == "held" or scenario == "go-held" or scenario == "go-held-long"
local releaseAfter = scenario == "go-held" and 2 or math.huge -- go-held: the keys are let go after two reads
local reads, clock = 0, 0

local screen = { getUUID = function() return "A" end, name = function() return "Laptop" end }
local window = {
  screen = function() return screen end,
  frame = function() return { x = 0, y = 0, w = 1000, h = 800 } end,
  application = function() return { bundleID = function() return "com.example.app" end } end,
  zoomButtonRect = function() return { x = 50, y = 4, w = 14, h = 14 } end,
  title = function() return "Doc" end,
}

hs = {
  window = { focusedWindow = function() return window end },
  screen = { primaryScreen = function() return screen end, mainScreen = function() return screen end },
  mouse = {
    absolutePosition = function(p) if p then record("move") end return { x = 500, y = 500 } end,
    getCurrentScreen = function() return screen end,
  },
  spaces = {
    data_managedDisplaySpaces = function()
      return { { ["Display Identifier"] = "A", Spaces = { { ManagedSpaceID = 1, type = 0 }, { ManagedSpaceID = 6, type = 0 } } } }
    end,
    windowSpaces = function() return { 6 } end,
    activeSpaces = function() return { A = 6 } end,
  },
  timer = {
    secondsSinceEpoch = function() clock = clock + 0.5 return clock end,
    usleep = function() end,
    doAfter = function(_, fn) fn() return {} end,
    waitUntil = function(pred, fn) for _ = 1, 100 do if pred() then fn() return {} end end error("waitUntil never finished") end,
  },
  eventtap = {
    checkKeyboardModifiers = function()
      reads = reads + 1
      if held and reads <= releaseAfter then return { ctrl = true, alt = true, cmd = true } end
      return {}
    end,
    event = {
      types = { leftMouseDown = "down", leftMouseDragged = "drag", leftMouseUp = "up", keyDown = "kd", keyUp = "ku" },
      properties = { eventSourceUserData = "userData" },
      newMouseEvent = function(t) return { post = function() record("mouse-" .. t) end } end,
      newKeyEvent = function(mods, code, down)
        if scenario == "key-fails" then error("no such key") end
        local e = { tag = "" }
        function e.setProperty(self, prop, value) if prop == "userData" and value == 0x57494E4B then self.tag = " tagged" end return self end
        function e.post(self) record((down and "key-down " or "key-up ") .. tostring(code) .. " " .. table.concat(mods, "+") .. self.tag) end
        return e
      end,
    },
    keyStroke = function() record("keyStroke (by name: layout-dependent)") end,
  },
  axuielement = {
    systemElementAtPosition = function()
      return { attributeValue = function(_, a) if a == "AXRole" then return scenario == "button" and "AXButton" or "AXGroup" end end }
    end,
  },
  alert = { show = function(m) record("alert: " .. m) end },
  fnutils = { filter = function(t, f) local r = {} for _, v in ipairs(t) do if f(v) then r[#r + 1] = v end end return r end },
}

local M = dofile(module)
local log = io.open -- the module logs to ~/Library/Logs; send it nowhere
io.open = function() return nil end
local ok, err = pcall(scenario:sub(1, 2) == "go" and M.go or M.send, 2)
io.open = log
if not ok then record("error: " .. tostring(err):gsub("^.-: ", "")) end
io.write(table.concat(events, " | "))
