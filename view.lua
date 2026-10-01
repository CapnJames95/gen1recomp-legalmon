return function(Model)
  local View = {}
  local Window = require("src.ui.game3.window")
  local Font = require("src.ui.game3.frlg_font")
  local Pokemon = require("src.core.game3.pokemon")

  local function text(value, x, y, width, small, colors)
    value = tostring(value or "")
    if Font.measure(value, { small = small }) > width then
      while #value > 0 and Font.measure(value .. "...", { small = small }) > width do value = value:sub(1, -2) end
      value = value .. "..."
    end
    Window.printPx(value, x, y, { maxWidth = width, small = small, colors = colors })
  end

  function View.wrap(value, width)
    local lines, line = {}, ""
    for word in tostring(value):gmatch("%S+") do
      local trial = line == "" and word or line .. " " .. word
      if Font.measure(trial, { small = true }) > width and line ~= "" then
        lines[#lines + 1], line = line, word
      else line = trial end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
  end

  local function frame(x, y, width, height, screen)
    Window.userFrame(Window.template(x, y, width, height), screen.frameType or 0)
  end

  local function portrait(screen, selected)
    local species = selected and selected.species or screen.request.species
    local valid = screen.job and screen.job.status == "valid" and species == screen.request.species
    local shiny = valid and screen.isShiny(screen.job) or screen.request.shiny == true
    if selected and selected.shiny ~= nil then shiny = selected.shiny end
    frame(1, 3, 10, 13, screen)
    local personality = valid and screen.job.result.pid or 0
    local form = selected and selected.form or screen.request.form
    if species == 201 and form ~= nil and (not valid or selected and selected.form ~= nil) then
      personality = form % 4 + math.floor(form / 4) % 4 * 256 + math.floor(form / 16) * 65536
    end
    local pic = Pokemon.frontPic(Pokemon.picSpecies(species, personality), 0, shiny, personality)
    if pic and pic.image then
      love.graphics.setColor(1, 1, 1, 1)
      local bounce = screen.animate and math.floor(math.sin(screen.elapsed * 4) * 2) or 0
      love.graphics.draw(pic.image, 16, 32 + bounce)
    else text("No sprite", 17, 55, 68, true) end
    local name = screen.pack and screen.pack.names[species] or "POKEMON"
    if species == 201 then name = name .. " " .. ("ABCDEFGHIJKLMNOPQRSTUVWXYZ!?"):sub(Pokemon.unownLetter(personality) + 1, Pokemon.unownLetter(personality) + 1) end
    text(name, 12, 99, 74, true)
    text("Lv." .. (selected and selected.level or screen.request.level) .. (shiny and "  SHINY" or ""), 12, 112, 74, true)
  end

  function View.draw(screen)
    love.graphics.setColor(0.78, 0.88, 0.9, 1)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    love.graphics.setColor(0.73, 0.84, 0.87, 1)
    for offset = 18, 135, 4 do love.graphics.rectangle("fill", 0, offset, 240, 1) end
    love.graphics.setColor(0, 123 / 255, 197 / 255, 1)
    love.graphics.rectangle("fill", 0, 0, 240, 16)
    love.graphics.setColor(1, 1, 1, 1)
    local page, editor = screen.pages[#screen.pages], screen.editor
    local title = page.kind == "preview" and ("PREVIEW " .. (screen.candidateIndex or 1)) or page.title
    text(editor and editor.title or title, 8, 0, 174, false, Font.COLOR.WHITE)
    local marker = Model.pageMarker(page, screen.session.version)
    if page.title == "LEGALMON" then
      local statuses = { valid = "VALID", searching = "WAIT", paused = "PAUSE", impossible = "FAIL", exhausted = "MORE", incomplete = "LIMIT", invalid = "FAIL", unsupported = "FAIL" }
      marker = screen.job and statuses[screen.job.status] or "READY"
    end
    text(marker, 202, 0, 30, true, Font.COLOR.WHITE)
    if editor then
      frame(1, 3, 28, 13, screen)
      text(editor.value == "" and (editor.numericOnly and "Enter ID: 0-65535" or "Enter text...") or editor.value, 16, 28, 208)
      local columns, spacing = editor.columns or 8, editor.numericOnly and 72 or 27
      for index, key in ipairs(screen.keyboard) do
        local x, y = 16 + ((index - 1) % columns) * spacing, 52 + math.floor((index - 1) / columns) * 18
        if index == editor.cursor then
          love.graphics.setColor(0.73, 0.85, 0.96, 1)
          love.graphics.rectangle("fill", x - 3, y, 26, 17)
          love.graphics.setColor(1, 1, 1, 1)
        end
        text(key, x, y, 25, true)
      end
    elseif page.kind == "compare" then
      frame(1, 3, 28, 13, screen)
      text(page.caption, 14, 24, 210, true)
      text(page.currentCaption, 14, 35, 210, true)
      text("       IV old/new      STAT old/new", 14, 47, 210, true)
      local keys = { "maxHp", "attack", "defense", "speed", "spAtk", "spDef" }
      for index, stat in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do
        local y = 61 + (index - 1) * 11
        local previous, current = page.baseline.ivs[stat], page.current.ivs[stat]
        text(stat:upper(), 14, y, 30, true)
        local oldStat, newStat = page.baseline[keys[index]], page.current[keys[index]]
        if current ~= previous or oldStat ~= newStat then
          local better = current > previous or current == previous and newStat > oldStat
          love.graphics.setColor(better and 0.72 or 0.98, better and 0.92 or 0.81, 0.78, 1)
          love.graphics.rectangle("fill", 49, y, 177, 12)
          love.graphics.setColor(1, 1, 1, 1)
        end
        text(previous .. "/" .. current .. string.format(" (%+d)", current - previous), 51, y, 80, true)
        text(oldStat .. "/" .. newStat .. string.format(" (%+d)", newStat - oldStat), 137, y, 88, true)
      end
    elseif page.kind == "progress" then
      frame(1, 3, 28, 13, screen)
      local job = screen.job
      local active = job.profiles and job.profiles[job.activeProfile or 1] or job
      text(job.status == "searching" and (active.phase == "pid" and "Stage 1/2: Poke Spot PID" or active.pokePidSeed and "Stage 2/2: IVs and level" or "Searching legal RNG frames...") or "Search paused", 16, 29, 208)
      text(string.format("%d / %d %s", job.checked, job.phase == "pid" and math.min(job.limit, job.pidDomain) or job.limit, job.profiles and "work" or job.phase == "pid" and "PIDs" or "frames"), 16, 53, 208)
      love.graphics.setColor(0.66, 0.72, 0.76, 1)
      love.graphics.rectangle("fill", 16, 78, 208, 8)
      love.graphics.setColor(0.25, 0.67, 0.47, 1)
      love.graphics.rectangle("fill", 16, 78, math.floor(208 * job.checked / (job.phase == "pid" and math.min(job.limit, job.pidDomain) or job.limit)), 8)
      love.graphics.setColor(1, 1, 1, 1)
      text(job.profiles and string.format("Acquisition path %d / %d", job.activeProfile or 1, #job.profiles) or "Progress is search coverage,", 16, 99, 208, true)
      text(job.profiles and "Budget, not global coverage." or "not the chance of a match.", 16, 112, 208, true)
    else
      if page.portrait then portrait(screen, page.rows[page.cursor]) end
      local left, width = page.portrait and 13 or 1, page.portrait and 16 or 28
      frame(left, 3, width, 13, screen)
      local count = page.query and 5 or 6
      local first = math.max(1, math.min(page.cursor - count + 1, #page.rows - count + 1))
      if page.query then text("Find: " .. (page.query == "" and "All" or page.query), left * 8 + 7, 26, width * 8 - 12, true) end
      for index = first, math.min(#page.rows, first + count - 1) do
        local row = page.rows[index]
        local y = (page.query and 43 or 28) + (index - first) * 16
        if index == page.cursor then
          love.graphics.setColor(0.82, 0.91, 0.96, 1)
          love.graphics.rectangle("fill", left * 8 + 1, y, width * 8 - 2, 16)
          love.graphics.setColor(1, 1, 1, 1)
          Window.cursorPx(left * 8 + 2, y)
        end
        local label = type(row.label) == "function" and row.label() or row.label
        text(label, left * 8 + 11, y, width * 8 - 16, page.small)
      end
    end
    frame(1, 17, 28, 2, screen)
    local selected = page.rows and page.rows[page.cursor]
    local help = editor and "Type or use pad. ENTER: OK  B/L: back"
      or (page.kind == "preview" or page.kind == "compare") and (screen.candidateSearch and ("Finding next: " .. screen.candidateSearch.checked .. "  B: stop")
        or screen.previewNotice or ("L/R: " .. (screen.candidateIndex or 1) .. "/" .. #(screen.candidates or {}) .. "  SELECT: best found  B: back"))
      or page.kind == "progress" and "A: pause  B/L: back  SELECT: cancel"
      or selected and (type(selected.help) == "function" and selected.help() or selected.help)
      or "A: choose  B/L: back  Left/Right: page"
    if page.kind == "preview" or page.kind == "compare" then
      love.graphics.setColor(0.75, 0.84, 0.91, 1)
      love.graphics.rectangle("fill", 12, 138, 11, 10)
      love.graphics.rectangle("fill", 25, 138, 11, 10)
      love.graphics.setColor(1, 1, 1, 1)
      text("L", 14, 135, 9, true); text("R", 27, 135, 9, true)
      text(help:gsub("L/R: ", ""), 40, 136, 187, true)
    else text(help, 12, 136, 216, true) end
  end

  return View
end
