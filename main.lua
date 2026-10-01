return function(mod)
  local function module(name)
    return assert(load(assert(mod:read(name .. ".lua")), "@legalmon/" .. name .. ".lua"))()
  end
  local Solver = module("solver")
  local Adapter = module("adapter")(Solver, module("acquisition"))
  local Model = module("model")(Solver)
  local activeGame
  local helpLease
  local Screen = module("screen")(Solver, Adapter, Model, module("view"), {
    log = function(line) mod.log:info("%s", line) end,
    readLibrary = function() return mod.save:get("library", {}) end,
    writeLibrary = function(value) mod.save:set("library", value) end,
    isActive = function(session) return require("src.core.game3.runtime").getSession() == session end,
    export = function(text)
      local ok, code, message = mod.storage:writeBytes(activeGame, "reports/latest", text)
      if not ok then return false, message or code or "Report storage unavailable." end
      return true, "Saved reports/latest.bin in this playthrough's LegalMon mod storage. It is plain text."
    end,
  })
  mod.hooks:wrap("input.key", function(next, game, event)
    if Screen.active and Screen.active.rawKey(event) then return true end
    return next(game, event)
  end)
  mod.hooks:wrap("input.step", function(next, game, dt)
    local Stack = require("src.ui.game3.stack")
    local Help = require("src.ui.game3.help_system")
    local top = Stack.top()
    if Screen.active and top and top.mod == Screen.active then
      if not helpLease then helpLease = { previous = Help.contextOverride } end
      Help.setContext(0)
      if game.input and game.input.setButtonAlias then game.input:setButtonAlias("l", nil) end
    elseif helpLease then
      if Help.contextOverride == 0 then Help.setContext(helpLease.previous) end
      helpLease = nil
    end
    return next(game, dt)
  end)
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local result = next(game, items)
    if type(result) ~= "table" then return result end
    local Runtime = require("src.core.game3.runtime")
    local session = Runtime.getSession()
    if not session or (session.version ~= "firered" and session.version ~= "leafgreen" and session.version ~= "emerald") then return result end
    for _, row in ipairs(result) do if row.id == "legalmon" then return result end end
    for index, row in ipairs(result) do
      if row.id == "save" then
        table.insert(result, index, { id = "legalmon", label = "LEGALMON", onSelect = function()
          if Runtime.getSession() == session then activeGame = game; Screen.show(session) end
        end })
        break
      end
    end
    return result
  end)
end
