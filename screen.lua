return function(Solver, Adapter, Model, makeView, services)
  local Screen = {}

  function Screen.show(session)
    local Stack = require("src.ui.game3.stack")
    local Options = require("src.core.game3.options")
    local View = makeView(Model)
    local pack, errorMessage = Adapter.load(session)
    local screen = { pages = {}, session = session, pack = pack,
      request = { species = 1, level = 5, ivs = {} }, destination = "party",
      library = Model.library(services.readLibrary()), frameType = Options.ensure(session).frameType or 0 }
    local alphabet = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "-", ".", "'", "SP", "DEL", "OK" }
    local digits = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "DEL", "0", "OK" }
    screen.keyboard = alphabet
    Screen.active = screen
    screen.ui = screen.library.ui
    screen.ui.places = type(screen.ui.places) == "table" and screen.ui.places or {}
    screen.locks, screen.pins, screen.elapsed = {}, {}, 0
    screen.shinyOnly = screen.ui.shinyOnly == true
    screen.animate = screen.ui.animate == true
    screen.cries = screen.ui.cries ~= false
    local function page() return screen.pages[#screen.pages] end
    local function rememberPlace()
      local current = page()
      if current then screen.ui.places[current.title] = { cursor = current.cursor, query = current.query } end
    end
    local function cry(species)
      if screen.cries then pcall(function() require("src.core.game3.audio").playCry(species, 0) end) end
    end
    local function sound() pcall(function() require("src.core.game3.audio").playSe(5) end) end
    local function push(title, rows, portrait, kind)
      rememberPlace()
      local entry = { title = title, rows = rows or {}, cursor = 1, portrait = portrait, kind = kind }
      local saved = screen.ui.places[title]
      if saved and type(saved.cursor) == "number" then entry.cursor = math.max(1, math.min(#entry.rows, math.floor(saved.cursor))) end
      screen.pages[#screen.pages + 1] = entry
      return entry
    end
    local function invalidate()
      screen.job, screen.candidates, screen.candidateIndex = nil, nil, nil
      screen.searchCursor, screen.candidateSearch, screen.previewNotice = nil, nil, nil
      screen.previousJob = nil
    end
    local function close()
      rememberPlace()
      screen.ui.request = Model.copy(screen.request)
      screen.ui.shinyOnly, screen.ui.animate, screen.ui.cries = screen.shinyOnly, screen.animate, screen.cries
      services.writeLibrary(Model.copy(screen.library))
      pcall(function() require("src.core.game3.audio").stopCry() end)
      Stack.pop("legalmon")
      if Screen.active == screen then Screen.active = nil end
    end
    local function back()
      if screen.editor then screen.editor = nil; return end
      if screen.candidateSearch then
        screen.searchCursor = screen.candidateSearch
        screen.candidateSearch = nil
        screen.previewNotice = "Search stopped. R: continue  L: previous"
        return
      end
      if screen.job and screen.job.status == "searching" then screen.job.status = "paused"; return end
      if #screen.pages > 1 then
        local wasCompare = page().kind == "compare"
        rememberPlace(); table.remove(screen.pages)
        if wasCompare and page().kind == "preview" then screen.preview() end
      else close() end
    end
    local function home() while #screen.pages > 1 do table.remove(screen.pages) end end
    local function info(title, lines, actions)
      local rows = {}
      for _, line in ipairs(lines) do
        for _, wrapped in ipairs(View.wrap(line, 205)) do rows[#rows + 1] = { label = wrapped } end
      end
      for _, row in ipairs(actions or {}) do rows[#rows + 1] = row end
      rows[#rows + 1] = { label = "Back", action = back }
      local entry = push(title, rows)
      entry.small = true
      return entry
    end
    local function edit(title, initial, callback, numericOnly)
      screen.keyboard = numericOnly and digits or alphabet
      screen.editor = { title = title, value = initial or "", callback = callback, cursor = 1,
        numericOnly = numericOnly, columns = numericOnly and 3 or 8 }
    end
    local function editorKey(key)
      local editor = screen.editor
      if key == "OK" then screen.editor = nil; editor.callback(editor.value)
      elseif key == "DEL" then editor.value = editor.value:sub(1, -2)
      elseif #editor.value < (editor.numericOnly and 5 or 16) and (not editor.numericOnly or key:match("^%d$")) then
        editor.value = editor.value .. (key == "SP" and " " or key)
      end
    end
    local function confirm(title, lines, action)
      local entry = info(title, lines, { { label = "Apply these changes", action = function()
        table.remove(screen.pages); action()
      end } })
      entry.cursor = #entry.rows - 1
    end
    local function choose(title, choices, setter, searchable, portrait)
      local entry = push(title, {}, portrait)
      local function populate(query)
        entry.query = searchable and query or nil
        entry.rows, entry.cursor = {}, 1
        if searchable then
          entry.rows[#entry.rows + 1] = { label = "Search / filter...", help = "Type a name or use the on-screen keyboard.", action = function()
            edit("SEARCH", entry.query, populate)
          end }
          if query ~= "" then entry.rows[#entry.rows + 1] = { label = "Clear filter", action = function() populate("") end } end
        end
        local matches = Model.filter(choices, query)
        for _, option in ipairs(matches) do
          entry.rows[#entry.rows + 1] = { label = option.label, help = option.help, species = option.species, national = option.national, shiny = option.shiny, level = option.level, form = option.form, action = function()
            if option.unavailable then info("ORIGIN UNAVAILABLE", {option.help}); return end
            rememberPlace(); table.remove(screen.pages); if option.species then cry(option.species) end; setter(option.value)
          end }
        end
        if #matches == 0 then entry.rows[#entry.rows + 1] = { label = "No matches", help = "Try a shorter name or clear the filter." } end
      end
      local saved = screen.ui.places[title]
      populate(searchable and saved and type(saved.query) == "string" and saved.query or "")
      if saved and type(saved.cursor) == "number" then entry.cursor = math.max(1, math.min(#entry.rows, math.floor(saved.cursor))) end
      return entry
    end
    local function numeric(title, low, high, current, setter)
      local choices = {}
      for value = low, high do choices[#choices + 1] = { label = tostring(value), value = value } end
      local entry = choose(title, choices, function(value) setter(value); invalidate() end)
      entry.cursor = math.max(1, math.min(#choices, (current or low) - low + 1))
    end
    screen.back, screen.info = back, info
    screen.isShiny = function(job) return Solver.shiny(job.result.pid, Solver.resultTrainer(job.prepared)) end

    if not pack then info("LEGALMON", { errorMessage })
    else
      screen.catalog = Adapter.catalog(pack, session.version)
      screen.speciesList, screen.allSpecies = Model.speciesList(pack, screen.catalog), {}
      for _, entry in ipairs(screen.speciesList) do screen.allSpecies[entry.species] = entry end
      if type(screen.ui.request) == "table" then
        local ok, prepared, err = pcall(Solver.prepare, screen.ui.request, screen.catalog, Adapter.trainer(session))
        if ok and screen.allSpecies[screen.ui.request.species] and (prepared or err and (err.status == "impossible" or err.status == "unsupported")) then screen.request = Model.copy(screen.ui.request) end
      end
      local function request() return screen.request end
      local function speciesRow()
        local species = request().species
        return screen.catalog[species] or { name = pack.names[species], ratio = pack.meta[species].genderRatio,
          abilities = pack.abilities[species], learnset = pack.learnsets[species], machines = {}, encounters = {} }
      end
      local function setRequest(value)
        if not screen.allSpecies[value.species] then info("UNAVAILABLE", { "This species is missing from your imported ROM catalog." }); return end
        local ok, _, err = pcall(Solver.prepare, value, screen.catalog, Adapter.trainer(session))
        if not ok or (err and err.status == "invalid") then info("INVALID BUILD", { "Saved build is malformed; it was not loaded." }); return end
        screen.request = Model.copy(value)
        screen.request.ivs = screen.request.ivs or {}
        invalidate()
      end
      local function change(key, value) request()[key] = value; invalidate() end
      local function persist() services.writeLibrary(Model.copy(screen.library)) end
      local function hint()
        local _, err = Solver.prepare(request(), screen.catalog, Adapter.trainer(session))
        return err and err.message or "Compatible choices. Validate to check RNG."
      end
      local function report()
        local lines = Adapter.explain(screen.job or { status = "Not validated" })
        lines[#lines + 1] = "Shiny-only result filter: " .. tostring(screen.shinyOnly)
        return Model.report(request(), screen.job, pack, lines)
      end
      local function export()
        local text = report()
        services.log(text)
        local ok, message = services.export(text)
        info(ok and "REPORT SAVED" or "EXPORT FAILED", { message, "The complete report is also in the engine log." })
      end
      local function alternatives()
        local rows = {}
        for _, proposal in ipairs(Model.alternatives(request(), screen.catalog, Adapter.trainer(session))) do
          rows[#rows + 1] = { label = proposal.label, help = proposal.help, action = function()
            confirm("REVIEW CHANGES", { proposal.help, "A new search is required. No match is promised." }, function()
              setRequest(proposal.request); home()
            end)
          end }
        end
        if #rows == 0 then
          info("NO SUPPORTED ORIGIN", { hint(), "No supported alternative was found. Review the origin, level and original trainer. Nothing was generated." })
        else push("ALTERNATIVES", rows) end
      end
      local function explain()
        info("LEGALITY", Adapter.explain(screen.job or { status = hint() }), {
          { label = "Why no match?", action = function() info("WHY NO MATCH?", Model.diagnose(request(), screen.catalog, Adapter.trainer(session), screen.job), {
            { label = "Review alternatives", action = alternatives },
          }) end },
          { label = "Find alternatives...", help = "Review changes before applying any.", action = alternatives },
          { label = "Export full report", action = export },
        })
      end
      local function storage()
        local free = 420
        if session.storage then free = 420 - require("src.core.game3.storage").countTotalMons(session.storage) end
        return math.max(0, 6 - #(session.party or {})), math.max(0, free)
      end
      local function destination()
        local partyFree, pcFree = storage()
        local choices = {
          { label = "Party (" .. partyFree .. " free)", value = "party", help = "Full party never redirects automatically." },
          { label = "PC (" .. pcFree .. " free)", value = "pc", help = "First free slot from the current box." },
        }
        for box = 1, 14 do
          local free = 30 - require("src.core.game3.storage").countBoxMons(session.storage, box)
          choices[#choices + 1] = { label = "Box " .. box .. " (" .. free .. " free)", value = box }
        end
        choose("SEND TO", choices, function(value)
          if type(value) == "number" then
            local slots = {}
            local Storage = require("src.core.game3.storage")
            for slot = 1, 30 do if not Storage.getBoxMon(session.storage, value, slot) then slots[#slots + 1] = slot end end
            if #slots == 0 then info("BOX FULL", { "Choose another box. Nothing will be overwritten." }); return end
            confirm("BOX " .. value, { "Empty slots: " .. table.concat(slots, ", "), "Uses first free slot at delivery; never spills into another box or overwrites." }, function()
              screen.destination, screen.targetBox = "pc", value
            end)
          else screen.destination, screen.targetBox = value, nil end
        end)
      end
      local function destinationLabel() return screen.targetBox and "BOX " .. screen.targetBox or screen.destination:upper() end
      local function validate()
        if screen.shinyOnly and request().shiny == false then info("FILTER CONFLICT", { "Shiny-only results conflict with Shiny: No. Disable the filter or explicitly change your request." }); return end
        if screen.job and (screen.job.status == "paused" or screen.job.status == "exhausted") then
          if screen.job.anchor and screen.job.checked >= screen.job.limit then explain(); return end
          if screen.job.status == "exhausted" then screen.job.limit = screen.job.limit + 1000000 end
          screen.job.status, screen.job.message = "searching", nil
        else
          invalidate()
          screen.job = Solver.startAll(request(), screen.catalog, Adapter.trainer(session), { onlyShiny = screen.shinyOnly })
        end
        if screen.job.status == "searching" then screen.job.onlyShiny = screen.shinyOnly end
        if screen.job.status == "searching" then push("VALIDATING", {}, false, "progress") else explain() end
      end
      local function preview()
        if not screen.job or screen.job.status ~= "valid" then info("PREVIEW", { "Validate first to see exact stats, moves and origin." }); return end
        local mon, err = Adapter.buildMon(screen.job, session, pack)
        if not mon then info("PREVIEW", { err }); return end
        local rows = {
          { label = "Compare IVs & stats", action = function() screen.compare() end },
          { label = "Pin this result", action = function()
            if #screen.pins >= 8 then info("PINS FULL", { "Clear a pin before bookmarking another result." }); return end
            screen.pins[#screen.pins + 1] = { job = screen.job, request = Model.copy(request()) }
            screen.pinned = screen.pins[#screen.pins]
            screen.previewNotice = "Pinned for comparison. L/R: browse"
          end },
          { label = Model.natures[mon.nature + 1] .. " / " .. mon.gender, help = "PID-derived nature and gender." },
          { label = "Ability: " .. pack.ability_names[mon.ability] },
          { label = "Shiny: " .. (screen.isShiny(screen.job) and "Yes" or "No") },
          { label = "IV total: " .. Model.ivTotal(mon.ivs) .. "/186", help = "SELECT: highest IV total among results found. Ties use the first result." },
          { label = "HP " .. mon.maxHp .. " / ATK " .. mon.attack },
          { label = "DEF " .. mon.defense .. " / SPE " .. mon.speed },
          { label = "SPA " .. mon.spAtk .. " / SPD " .. mon.spDef },
        }
        for _, move in ipairs(mon.moves) do rows[#rows + 1] = { label = pack.move_names[move] } end
        local encounter = Solver.encounter(screen.job.result, screen.job.prepared)
        rows[#rows + 1] = { label = "Met Lv." .. mon.metLevel .. " / area " .. mon.metLocation, help = encounter.kind .. " / " .. encounter.method .. " / origin " .. encounter.version }
        rows[#rows + 1] = { label = (mon.pokeball == 5 and "Safari Ball / " or "Poke Ball / ") .. encounter.version }
        if encounter.event then rows[#rows + 1] = { label = "EVENT origin", help = encounter.kind .. ". Historical distribution rules; not a normal catch." } end
        rows[#rows + 1] = { label = "OT: " .. mon.otName, help = (encounter.ot and "Fixed NPC/event trainer " or "Original trainer ") .. mon.otId .. "/" .. mon.otSecretId .. ". Shininess uses these IDs." }
        if encounter.nickname then rows[#rows + 1] = { label = "Nickname: " .. mon.nickname, help = encounter.ereader and "Japanese-language e-Reader Pokemon; Latin nickname MON avoids bundling Japanese species names." or "Required NPC trade nickname, preserved through evolution." } end
        if encounter.ereader then rows[#rows + 1] = { label = "Language: Japanese", help = "e-Reader origin, fixed zero IVs and locked nature/gender. OT uses supported Latin characters." } end
        local hiddenType, power = Solver.hiddenPower(mon.ivs)
        rows[#rows + 1] = { label = "Hidden Power: " .. Solver.hiddenTypes[hiddenType] .. " " .. power }
        rows[#rows + 1] = { label = function() return "Send to: " .. destinationLabel() end, action = destination }
        rows[#rows + 1] = { label = "Confirm generation...", action = function()
          local partyFree, pcFree = storage()
          local confirmation = info("CONFIRM", { "Generate " .. mon.name .. " at level " .. mon.level .. "?",
            encounter.event and ("EVENT: " .. encounter.kind .. ". OT: " .. mon.otName .. " (" .. mon.otId .. "/" .. mon.otSecretId .. ").") or ("Origin: " .. encounter.version .. " / " .. encounter.method .. "."),
            "OT: " .. mon.otName .. " / " .. mon.otId .. "/" .. mon.otSecretId .. " / " .. (mon.otGender == 0 and "Male" or "Female"),
            encounter.ereader and "Japanese e-Reader origin. Nickname: MON. All IVs: zero." or "Acquisition: " .. encounter.kind,
            "Destination: " .. destinationLabel() .. ". Party space: " .. partyFree .. "; PC space: " .. pcFree .. "." }, {
            { label = "Yes, generate", action = function()
              if services.isActive and not services.isActive(session) then info("NOT GENERATED", { "Session changed. Reopen LegalMon." }); return end
              local fresh, failure = Adapter.load(session)
              if not fresh then info("NOT GENERATED", { failure }); return end
              local ok, message = Adapter.deliver(screen.job, request(), session, fresh, screen.destination, screen.targetBox)
              services.log(message)
              if ok then Model.remember(screen.library, request(), mon.name .. " Lv." .. mon.level, false); persist(); home() end
              info(ok and "POKEMON SENT" or "NOT GENERATED", { message })
            end },
          })
          confirmation.cursor = #confirmation.rows
        end }
        local cursor = 1
        if page().kind == "preview" then cursor = page().cursor; table.remove(screen.pages) end
        local entry = push("PREVIEW", rows, true, "preview")
        entry.cursor = math.min(cursor, #rows)
      end
      local function browse(delta)
        if not screen.candidates then return end
        if screen.candidateSearch then
          if delta > 0 then return end
          screen.searchCursor, screen.candidateSearch = screen.candidateSearch, nil
        end
        local index = screen.candidateIndex + delta
        if index < 1 then screen.previewNotice = "First result. R: next matching Pokemon"; return end
        if index <= #screen.candidates then
          screen.previousJob = screen.job
          screen.candidateIndex, screen.job = index, screen.candidates[index]
          screen.previewNotice = nil
          if page().kind == "compare" then screen.compare() else preview() end
          return
        end
        local cursor = screen.searchCursor
        if (cursor.anchor or cursor.finite) and cursor.checked >= cursor.limit then
          screen.previewNotice = (cursor.status == "incomplete" or cursor.proofLimited or cursor.prepared.seedChoices or cursor.prepared.encounter.pokespot ~= nil) and "Proof limit: more matches not ruled out."
            or "No more matches. L: previous result"
          return
        end
        local pending = Model.copy(cursor)
        if not pending.anchor and not pending.finite and pending.checked >= pending.limit then pending.limit = pending.limit + 1000000 end
        pending.status, pending.result, pending.message, pending.consumed = "searching", nil, nil, nil
        screen.candidateSearch, screen.previewNotice = pending, nil
      end
      local function bestResult()
        local index, total = Model.bestCandidate(screen.candidates)
        if not index then return end
        if screen.candidateSearch then
          screen.searchCursor, screen.candidateSearch = screen.candidateSearch, nil
        end
        if index ~= screen.candidateIndex then screen.previousJob = screen.job end
        screen.candidateIndex, screen.job = index, screen.candidates[index]
        screen.previewNotice = "Best found: " .. total .. "/186 (" .. #screen.candidates .. " results)"
        if page().kind == "compare" then screen.compare() else preview() end
      end
      local function perfectResults(seed)
        local choices = {}
        local options = screen.finderShiny and Model.shinyOptions(screen.catalog, Adapter.trainer(session), request().level, seed, request().origin, request().ot, request().acquisition)
          or Model.perfectOptions(screen.catalog, Adapter.trainer(session), request().level, seed, screen.shinyOnly, request().origin, request().ot, request().acquisition)
        local groups = {}
        for _, option in ipairs(options) do
          local frame = option.job.result
          local species = option.request.species
          if not groups[species] then
            groups[species] = {}
            choices[#choices + 1] = { label = pack.names[species], species = species, value = groups[species], shiny = screen.finderShiny or screen.shinyOnly }
          end
          local abilities = option.job.prepared.row.abilities
          local ability = abilities[Solver.abilitySlot(frame, option.job.prepared) + 1]
          local shiny = Solver.shiny(frame.pid, Solver.resultTrainer(option.job.prepared))
          groups[species][#groups[species] + 1] = { label = Model.natures[frame.pid % 25 + 1] .. " " .. Solver.gender(frame.pid, option.job.prepared.row.ratio) .. (shiny and " *" or "") .. " #" .. (#groups[species] + 1),
            species = species, shiny = shiny, level = option.request.level, value = option,
            help = string.format("%s / seed %08X / %s", pack.ability_names[ability], frame.seed, shiny and "SHINY" or "NORMAL") }
        end
        if #choices == 0 then
          info(screen.finderShiny and "NO SHINY MATCH" or "NO PERFECT MATCH", { seed and string.format("Game seed snapshot: %08X", seed) or "Cartridge/GameCube methods checked. Eggs and locked NPC teams use bounded samples, not an exhaustive search.",
            "No matching proof in this finder set. Egg results are bounded samples, not exhaustive. Event shininess uses fixed event IDs. Your choices are unchanged.",
            screen.finderShiny and "Try again after normal gameplay changes the seed, or use a normal shiny search." or "Try other seeds or disable shiny-only if you want non-shiny results." })
          return
        end
        for _, choice in ipairs(choices) do choice.help = #choice.value .. " matching spreads. Choose to see nature, gender, ability and shiny badges." end
        local function selectOption(option)
          local frame = option.job.result
          confirm("REVIEW RESULT", {
            pack.names[option.request.species] .. " Lv." .. option.request.level .. (screen.finderShiny and "; shiny seed snapshot." or "; all six IVs 31."),
            Model.natures[frame.pid % 25 + 1] .. "; gender " .. Solver.gender(frame.pid, option.job.prepared.row.ratio)
              .. "; shiny " .. tostring(Solver.shiny(frame.pid, Solver.resultTrainer(option.job.prepared))) .. ".",
            string.format("Proof seed: %08X", frame.seed),
            "Origin: " .. Solver.encounter(frame, option.job.prepared).version .. "; " .. Solver.encounter(frame, option.job.prepared).method,
            "Replaces species and IVs; raises level only if required. Nature, gender and ability become Any; moves automatic. Shiny-only stays enforced when enabled. Extra IV filters are cleared.",
            "This selects a proof, not the live game's next encounter. Game RNG is not changed.",
          }, function()
            setRequest(option.request)
            screen.job = option.job
            screen.candidates = {}
            for _, candidate in ipairs(options) do
              if candidate.request.species == option.request.species then
                screen.candidates[#screen.candidates + 1] = candidate.job
                if candidate == option then screen.candidateIndex = #screen.candidates end
              end
            end
            screen.searchCursor = Model.copy(option.job)
            home(); preview()
          end)
        end
        choose(screen.finderShiny and "SHINY RESULTS" or "PERFECT RESULTS", choices, function(group)
          choose("SPREADS", group, selectOption, false, true)
        end, true, true)
      end
      local function perfectFinder()
        screen.finderShiny = false
        info("ALL 31 FINDER", {
          "A seed is interpreted with each species' acquisition method. Eggs also require the displayed hypothetical parental IVs.",
          "Current seed is read-only. Normal IV domains are checked; eggs and locked NPC teams use bounded samples (128 team starts). No result is not proof that no perfect team-locked Pokemon exists. Use normal validation to search further.",
          "Results use implemented origins, including eggs and events. Review all changes before applying.",
        }, {
          { label = "Check current game seed", action = function()
            perfectResults(require("src.core.game3.rng").getState().value)
          end },
          { label = "Any perfect Pokemon", action = function() perfectResults() end },
          { label = "Keep my choices", action = function()
            confirm("PERFECT IV SEARCH", { "Only replace IV constraints with all six exact 31. Keep species, level, nature, gender, ability, shiny and moves.",
              "Finite domains are exhaustive; egg searches are bounded and resumable. Exact choices are never relaxed." }, function()
              setRequest(Model.ivs(request(), "perfect")); home(); validate()
            end)
          end },
        })
      end
      local function shinyFinder()
        screen.finderShiny = true
        info("SHINY FINDER", { "Check one read-only seed snapshot using each acquisition method. Normal origins use the selected OT's IDs; fixed-OT events use their event IDs. XD Shadows cannot be shiny.",
          "Egg proofs include hypothetical parents. Event seeds must lie in their distribution's seed domain. IVs are not guaranteed perfect; no gameplay RNG is advanced." }, {
          { label = "Check current shiny seed", action = function() perfectResults(require("src.core.game3.rng").getState().value) end },
        })
      end
      local function compare()
        if not screen.job or screen.job.status ~= "valid" then info("COMPARE", { "Validate first. Pin a result to keep it as the comparison baseline." }); return end
        local reference = screen.pinned and screen.pinned.job or screen.previousJob or screen.job
        local current = Adapter.buildMon(screen.job, session, pack)
        local baseline = Adapter.buildMon(reference, session, pack)
        if not current or not baseline then info("COMPARE", { "Trainer or data changed; validate again." }); return end
        if page().kind == "compare" then table.remove(screen.pages) end
        local entry = push("IV / STAT COMPARE", {}, false, "compare")
        entry.current, entry.baseline = current, baseline
        entry.caption = (screen.pinned and "Pin " or "Old ") .. baseline.name .. " " .. baseline.level .. " " .. Model.natures[baseline.nature + 1]
        entry.currentCaption = "Now " .. current.name .. " " .. current.level .. " " .. Model.natures[current.nature + 1]
      end
      screen.compare = compare
      local function pinsPage()
        local rows = {}
        for index, pin in ipairs(screen.pins) do
          rows[#rows + 1] = { label = index .. ". " .. pack.names[pin.request.species] .. " / " .. Model.natures[pin.job.result.pid % 25 + 1], action = function()
            push("PIN " .. index, {
              { label = "Compare with current", action = function() screen.pinned = pin; compare() end },
              { label = "Restore pinned preview", action = function()
                if screen.shinyOnly and not screen.isShiny(pin.job) then info("FILTER CONFLICT", { "This pin is not shiny. Disable shiny-only first." }); return end
                confirm("RESTORE PIN", { "Restore this pin's saved configuration and exact result? Trainer and ROM data will be rechecked. Already delivered results cannot be delivered twice." }, function()
                  setRequest(pin.request)
                  screen.job, screen.candidates, screen.candidateIndex = pin.job, { pin.job }, 1
                  screen.searchCursor = Model.copy(pin.job)
                  screen.searchCursor.onlyShiny = screen.shinyOnly
                  home(); preview()
                end)
              end },
              { label = "Remove this pin", action = function()
                if screen.pinned == pin then screen.pinned = nil end
                table.remove(screen.pins, index); back(); back()
              end },
            })
          end }
        end
        rows[#rows + 1] = { label = "Clear pins", action = function() screen.pins, screen.pinned = {}, nil; back() end }
        push("PINNED RESULTS", rows)
      end
      local function locksPage()
        local rows = {}
        for _, key in ipairs({ "nature", "gender", "ability", "shiny", "hp", "atk", "def", "spe", "spa", "spd" }) do
          rows[#rows + 1] = { label = function() return (screen.locks[key] and "[X] " or "[ ] ") .. key:upper() end,
            help = "Locks apply to Search unlocked, not manual edits or presets.", action = function() screen.locks[key] = not screen.locks[key] end }
        end
        rows[#rows + 1] = { label = "Search unlocked", action = function()
          local proposed = Model.reroll(request(), screen.locks, screen.job)
          local lines = { "Keep species, level, moves and extra IV filters. Locked fields use this preview's exact values, or existing constraints if not validated. Unlocked traits/IVs become Any." }
          for _, stat in ipairs(Solver.stats) do lines[#lines + 1] = stat:upper() .. ": " .. Model.ivLabel(proposed.ivs[stat]) end
          confirm("REVIEW LOCKS", lines, function() setRequest(proposed); home(); validate() end)
        end }
        push("LOCKS & REROLL", rows)
      end
      local function settingsPage()
        push("RESULTS & STYLE", {
          { label = function() return "Shiny-only results: " .. (screen.shinyOnly and "ON" or "OFF") end,
            help = "Filters normal and finder results; clears current validation. Never relaxes Shiny: No.", action = function()
              screen.shinyOnly = not screen.shinyOnly; invalidate()
            end },
          { label = function() return "Selection cries: " .. (screen.cries and "ON" or "OFF") end, action = function() screen.cries = not screen.cries end },
          { label = function() return "Sprite bounce: " .. (screen.animate and "ON" or "OFF") end, action = function() screen.animate = not screen.animate end },
        })
      end
      local function pokemonPage()
        push("POKEMON", {
          { label = function() return "Species: " .. speciesRow().name end, help = hint, action = function()
            local choices = {}
            for _, entry in ipairs(screen.speciesList) do
              local row = screen.catalog[entry.species]
              choices[#choices + 1] = { label = entry.name .. (entry.supported and "" or " [!]"), value = entry.species, species = entry.species, national = entry.national,
                help = string.format("#%03d / %s", entry.national, Model.originHint(row, request().origin, request().acquisition)) }
            end
            choose("SPECIES", choices, function(value) setRequest(Model.selectSpecies(request(), screen.catalog, value)) end, true, true)
          end },
          { label = function() return "Level: " .. request().level end, help = function() return Model.originHint(screen.catalog[request().species], request().origin, request().acquisition) end,
            action = function() numeric("LEVEL", 1, 100, request().level, function(value) request().level = value end) end },
          { label = function() return "Origin: " .. (request().origin or "Any supported") end, help = "Source game survives transfer into the active game. Exact origin is never relaxed.", action = function()
            local choices = { { label = "Any supported" } }
            for _, origin in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald", "colosseum", "xd" }) do
              local available=false
              for _, e in ipairs(speciesRow().encounters or {}) do if e.version==origin then available=true;break end end
              local missing=pack.unavailableOrigins and pack.unavailableOrigins[origin]
              choices[#choices + 1] = { label = origin .. (available and "" or " [unavailable]"), value = origin,
                unavailable=not available, help=available and Model.originHint(speciesRow(),origin)
                  or (missing and "Import this source game's supported ROM to load its native routes. Existing verified transfer profiles remain available."
                    or "No supported acquisition for this species in this origin. Another origin may be available.") }
            end
            choose("ORIGIN GAME", choices, function(value) change("origin", value) end)
          end },
          { label = function() return "Acquisition: " .. (request().acquisition or "Any") end, help = "Choose the exact route; useful for e-Reader evolutions and NPC trades. Never silently falls back.", action = function()
            local choices = { { label = "Any supported" } }
            for _, value in ipairs({ "cartridge", "egg", "shadow", "starter", "trade", "gift", "pokespot", "ereader" }) do choices[#choices + 1] = { label = value, value = value } end
            choose("ACQUISITION", choices, function(value) change("acquisition", value) end)
          end },
          { label = function() return "Nature: " .. (request().nature and Model.natures[request().nature + 1] or "Any") end, action = function()
            local choices = { { label = "Any" } }
            for index, name in ipairs(Model.natures) do choices[#choices + 1] = { label = name, value = index - 1 } end
            choose("NATURE", choices, function(value) change("nature", value) end)
          end },
          { label = function() return "Gender: " .. (request().gender or "Any") end, action = function()
            local ratio, choices = speciesRow().ratio, { { label = "Any" } }
            if ratio == 255 then choices[#choices + 1] = { label = "Genderless", value = "U" }
            else
              if ratio ~= 254 then choices[#choices + 1] = { label = "Male", value = "M" } end
              if ratio ~= 0 then choices[#choices + 1] = { label = "Female", value = "F" } end
            end
            choose("GENDER", choices, function(value) change("gender", value) end)
          end },
          { label = function() return "Ability: " .. (request().ability and pack.ability_names[request().ability] or "Any") end, action = function()
            local choices, seen = { { label = "Any" } }, {}
            for _, ability in ipairs(speciesRow().abilities) do if ability ~= 0 and not seen[ability] then
              choices[#choices + 1] = { label = pack.ability_names[ability], value = ability }; seen[ability] = true
            end end
            choose("ABILITY", choices, function(value) change("ability", value) end)
          end },
          { label = function() return "Shiny: " .. (request().shiny == nil and "Any" or request().shiny and "Yes" or "No") end, action = function()
            choose("SHINY", { { label = "Any" }, { label = "Yes", value = true }, { label = "No", value = false } }, function(value) change("shiny", value) end)
          end },
        })
        if request().species == 201 then
          page().rows[#page().rows + 1] = { label = function() return "Unown form: " .. (request().form ~= nil and Solver.unownLetters:sub(request().form + 1, request().form + 1) or "Any") end,
            help = "A-Z, ! or ?. The PID, chamber and encounter slot must all match.", action = function()
              local choices = { { label = "Any", species = 201 } }
              for form = 0, 27 do
                choices[#choices + 1] = { label = Solver.unownLetters:sub(form + 1, form + 1), value = form, form = form, species = 201 }
              end
              choose("UNOWN FORM", choices, function(value) change("form", value) end, false, true)
            end }
        end
      end
      local function ivPage()
        local rows = {}
        for _, stat in ipairs(Solver.stats) do
          rows[#rows + 1] = { label = function() return stat:upper() .. " IV: " .. Model.ivLabel(request().ivs[stat]) end,
            help = "Choose Any, Exact, or a minimum and maximum.", action = function()
              local function bounds()
                local value = request().ivs[stat]
                return type(value) == "table" and value.min or value or 0, type(value) == "table" and value.max or value or 31
              end
              push(stat:upper() .. " IV", {
                { label = "Any", action = function() request().ivs[stat] = nil; invalidate(); back() end },
                { label = "Exact...", action = function() numeric("EXACT IV", 0, 31, bounds(), function(number) request().ivs[stat] = number end) end },
                { label = "Minimum...", help = "Upper bound stays; change Maximum first to raise it.", action = function()
                  local low, high = bounds()
                  numeric("MINIMUM", 0, high, low, function(number) request().ivs[stat] = { min = number, max = high } end)
                end },
                { label = "Maximum...", action = function()
                  local low, high = bounds()
                  numeric("MAXIMUM", low, 31, high, function(number) request().ivs[stat] = { min = low, max = number } end)
                end },
              })
            end }
        end
        for _, shortcut in ipairs({ { "All Any", "any" }, { "All minimum 20", "minimum20" }, { "All minimum 25", "minimum" }, { "All exact 31", "perfect" },
          { "0 Attack / others Any", "zeroAttack" }, { "0 Speed / others Any", "zeroSpeed" }, { "At least five perfect IVs", "five" } }) do
          rows[#rows + 1] = { label = shortcut[1], action = function()
            confirm("IV SHORTCUT", { "Replace all six IV constraints with " .. shortcut[1] .. "?", "Clears old total/perfect-count filters. Five-perfect sets a minimum count of five; 0 Attack/Speed leaves other IVs Any. Hidden Power filters stay.", "Exact spreads may be impossible with Method 1." }, function() setRequest(Model.ivs(request(), shortcut[2])) end)
          end }
        end
        rows[#rows + 1] = { label = function() return "Minimum total: " .. (request().minTotal or 0) end, action = function()
          numeric("IV TOTAL MINIMUM", 0, 186, request().minTotal, function(value) request().minTotal = value end)
        end }
        push("INDIVIDUAL VALUES", rows)
      end
      local function hiddenPage()
        push("HIDDEN POWER", {
          { label = function() return "Type: " .. (Solver.hiddenTypes[request().hiddenType] or "Any") end, action = function()
            local choices = { { label = "Any" } }
            for index, name in ipairs(Solver.hiddenTypes) do choices[#choices + 1] = { label = name, value = index } end
            choose("HP TYPE", choices, function(value) change("hiddenType", value) end)
          end },
          { label = function() return "Minimum power: " .. (request().hiddenPower or 30) end, action = function()
            numeric("HP MINIMUM POWER", 30, 70, request().hiddenPower or 30, function(value) request().hiddenPower = value end)
          end },
          { label = "Clear Hidden Power filter", action = function() change("hiddenType", nil); change("hiddenPower", nil) end },
          { label = "About Hidden Power", action = function() info("HIDDEN POWER", { "Gen III type and power (30-70) come from IV bits. This filters IVs; it does not add the move. Select the move separately if desired." }) end },
        })
      end
      local function movesPage()
        local rows = { { label = "Use automatic moves", help = "Replaces all moves with level-up defaults.", action = function()
          confirm("AUTOMATIC MOVES", { "Replace your move choices with level-up defaults?" }, function() change("moves", nil) end)
        end } }
        for slot = 1, 4 do rows[#rows + 1] = { label = function()
          local move = request().moves and request().moves[slot]
          return slot .. ". " .. (move and pack.move_names[move] or request().moves and "Empty" or "Automatic")
        end, help = "Only supported move sources appear.", action = function()
          local choices = Model.moves(speciesRow(), request().level, pack, request().origin, request().acquisition)
          table.insert(choices, 1, { label = "Remove slot", value = false })
          choose("MOVE " .. slot, choices, function(move)
            if not request().moves then
              local prepared = Solver.prepare(request(), screen.catalog, Adapter.trainer(session))
              request().moves = prepared and prepared.moves or {}
            end
            if move then request().moves[math.min(slot, #request().moves + 1)] = move
            elseif slot <= #request().moves then table.remove(request().moves, slot) end
            invalidate()
          end, true)
        end } end
        push("MOVES", rows)
      end
      local function libraryPage(key)
        local rows = {}
        for index, entry in ipairs(screen.library[key]) do
          rows[#rows + 1] = { label = entry.name, help = "Load a copy; validation is always required.", action = function()
            push(entry.name, {
              { label = "Load build", action = function() setRequest(entry.request); home() end },
              { label = "Delete saved build", action = function() table.remove(screen.library[key], index); persist(); back(); back() end },
            })
          end }
        end
        if #rows == 0 then rows[1] = { label = "No saved builds yet" } end
        push(key == "favorites" and "FAVOURITES" or "RECENT BUILDS", rows)
      end
      local function presetsPage()
        local rows = {}
        for _, preset in ipairs({ { "Any legal", "any" }, { "Physical attacker", "physical" }, { "Special attacker", "special" } }) do
          rows[#rows + 1] = { label = preset[1], action = function()
            confirm("APPLY PRESET", { "Keep species and level. Reset moves, gender, ability and shiny to Any/default.",
              preset[2] == "any" and "All natures and IVs allowed." or "Sets an attacking nature, with attacking and Speed IVs of 25-31.", "Validation still required." }, function() setRequest(Model.preset(request(), preset[2])) end)
          end }
        end
        rows[#rows + 1] = { label = "Save custom build...", action = function()
          edit("SAVE BUILD", pack.names[request().species], function(name)
            if name:match("%S") then Model.remember(screen.library, request(), name, true); persist() end
          end)
        end }
        rows[#rows + 1] = { label = "Favourites", action = function() libraryPage("favorites") end }
        rows[#rows + 1] = { label = "Recent builds", action = function() libraryPage("recent") end }
        push("PRESETS & BUILDS", rows)
      end
      local function trainerPage()
        local draft = Model.copy(request().ot or Adapter.trainer(session))
        local function identifier(key)
          edit(key:upper(), tostring(draft[key]), function(value)
            local number = value:match("^%d+$") and tonumber(value)
            if number and number <= 65535 then draft[key] = number
            else info("INVALID ID", { "Enter a whole number from 0 to 65535." }) end
          end, true)
        end
        push("ORIGINAL TRAINER", {
          { label = "Use your trainer", help = "NPC trades and fixed-OT events retain their required original trainer.", action = function() change("ot", nil); back() end },
          { label = function() return "Name: " .. draft.name end, action = function() edit("OT NAME", draft.name, function(value)
            if #value >= 1 and #value <= 7 and value:match("%S") and not value:find("[^A-Za-z0-9 .,!?'%-]") then draft.name = value
            else info("INVALID NAME", { "Use 1-7 English letters, digits, spaces or . ! ? -" }) end
          end) end },
          { label = function() return "Trainer ID: " .. draft.tid end, action = function() identifier("tid") end },
          { label = function() return "Secret ID: " .. draft.sid end, action = function() identifier("sid") end },
          { label = function() return "Gender: " .. (draft.gender == 0 and "Male" or "Female") end, action = function() draft.gender = 1 - draft.gender end },
          { label = "Randomize draft", help = "Review before applying. Uses a local sequence, never advances the game's RNG.", action = function()
            local advance = (request().origin == "colosseum" or request().origin == "xd") and Solver.gcNext or Solver.next
            for _ = 1, 256 do
              screen.otSeed = advance(screen.otSeed or (session.trainerId * 65536 + session.secretId))
              draft.tid = math.floor(screen.otSeed / 65536)
              screen.otSeed = advance(screen.otSeed)
              draft.sid = math.floor(screen.otSeed / 65536)
              if request().origin == "ruby" or request().origin == "sapphire" then draft.tid, draft.sid = draft.sid, draft.tid end
              if advance ~= Solver.gcNext or Solver.trainerSeed(draft, request().origin) then break end
            end
            draft.name, draft.gender = ({ "WES", "MICHAEL", "ALEX", "SAM" })[draft.sid % 4 + 1], 0
          end },
          { label = "Apply custom trainer", help = "Revalidates shininess. GameCube origins require Male; fixed NPC/event OTs cannot be changed.", action = function() change("ot", Model.copy(draft)); back() end },
        })
      end
      local function configure()
        push("CONFIGURE", {
          { label = "Pokemon", help = hint, action = pokemonPage },
          { label = "IV constraints", help = "Exact values, ranges and competitive shortcuts.", action = ivPage },
          { label = "Moves", help = "Search moves and inspect how they are learned.", action = movesPage },
          { label = "Hidden Power", help = "Gen III IV-derived type and minimum power.", action = hiddenPage },
          { label = "Locks & reroll", help = "Lock selected traits, then search the rest.", action = locksPage },
          { label = "Destination", help = "Choose party, automatic PC placement or a specific box.", action = destination },
          { label = "Original trainer", help = "Your trainer or custom name, IDs and gender. Changes require validation.", action = trainerPage },
        }, true)
      end
      local function toolsPage()
        push("FINDERS & TOOLS", {
          { label = "All 31 finder", help = "Check this game seed or explore perfect-IV options.", action = perfectFinder },
          { label = "Shiny seed finder", help = "Any supported shiny Pokemon at the current game seed.", action = shinyFinder },
          { label = "Presets & builds", help = "Saved builds travel with your normal SAVE.", action = presetsPage },
          { label = "Pinned results", help = "Compare up to eight bookmarks in this session.", action = pinsPage },
          { label = "Legality & report", help = "Why no match, alternatives and exportable proof.", action = explain },
        })
      end
      push("LEGALMON", {
        { label = "Configure Pokemon", help = "Species, traits, IVs, moves, locks and destination.", action = configure },
        { label = function() return screen.job and (screen.job.status == "paused" or screen.job.status == "exhausted") and "Resume search" or "Validate" end, help = hint, action = validate },
        { label = "Preview & send", help = "Review stats, origin and destination first.", action = preview },
        { label = "Finders & tools", help = "Perfect/shiny finders, saved builds, pins and legality.", action = toolsPage },
        { label = "Results & style", help = "Shiny-only filter, cries and optional sprite animation.", action = settingsPage },
        { label = "Close", action = close },
      }, true)
      screen.validate, screen.preview, screen.report, screen.browse = validate, preview, report, browse
      screen.bestResult = bestResult
    end

    function screen.rawKey(event)
      if not screen.editor or not Stack.top() or Stack.top().mod ~= screen then return false end
      if event.phase == "pressed" then
        local key = event.key
        if key == "escape" then screen.editor = nil
        elseif key == "return" or key == "kpenter" then editorKey("OK")
        elseif key == "backspace" or key == "delete" then editorKey("DEL")
        elseif key == "space" then editorKey("SP")
        elseif key:match("^kp%d$") then editorKey(key:sub(3))
        elseif #key == 1 and key:match("[%w.'%-]") then editorKey(key:upper())
        elseif key == "left" then screen.editor.cursor = (screen.editor.cursor - 2) % #screen.keyboard + 1
        elseif key == "right" then screen.editor.cursor = screen.editor.cursor % #screen.keyboard + 1
        elseif key == "up" then screen.editor.cursor = (screen.editor.cursor - 1 - screen.editor.columns) % #screen.keyboard + 1
        elseif key == "down" then screen.editor.cursor = (screen.editor.cursor - 1 + screen.editor.columns) % #screen.keyboard + 1 end
      end
      return true
    end
    function screen.handleInput(input)
      if input:wasPressed("b") or input:wasPressed("start") then sound(); back(); return end
      if input:wasPressed("l") and (screen.editor or page().kind ~= "preview" and page().kind ~= "compare") then
        sound(); back(); return
      end
      if screen.editor then
        local delta = input:wasPressed("up") and -screen.editor.columns or input:wasPressed("down") and screen.editor.columns or input:wasPressed("left") and -1 or input:wasPressed("right") and 1 or 0
        screen.editor.cursor = (screen.editor.cursor - 1 + delta) % #screen.keyboard + 1
        if input:wasPressed("a") then sound(); editorKey(screen.keyboard[screen.editor.cursor]) end
        return
      end
      if page().kind == "preview" or page().kind == "compare" then
        if input:wasPressed("select") then sound(); screen.bestResult(); return end
        if input:wasPressed("l") then sound(); screen.browse(-1); return end
        if input:wasPressed("r") then sound(); screen.browse(1); return end
        if screen.candidateSearch or page().kind == "compare" then return end
      end
      if page().kind == "progress" then
        if input:wasPressed("select") then invalidate(); home(); return end
        if input:wasPressed("a") then screen.job.status = screen.job.status == "searching" and "paused" or "searching" end
        return
      end
      local current = page()
      if #current.rows == 0 then return end
      local delta = input:wasPressed("up") and -1 or input:wasPressed("down") and 1 or input:wasPressed("left") and -5 or input:wasPressed("right") and 5 or 0
      current.cursor = (current.cursor - 1 + delta) % #current.rows + 1
      if delta ~= 0 then sound() end
      local selected = current.rows[current.cursor]
      if input:wasPressed("a") and selected.action then sound(); selected.action() end
    end
    function screen.update(dt)
      screen.elapsed = screen.elapsed + (dt or 1 / 60)
      if screen.candidateSearch then
        local pending = screen.candidateSearch
        Solver.step(pending, pending.prepared.encounter.locks and 16 or 512)
        if pending.status ~= "searching" then
          screen.searchCursor, screen.candidateSearch = Model.copy(pending), nil
          if pending.status == "valid" then
            screen.candidates[#screen.candidates + 1] = pending
            screen.previousJob = screen.job
            screen.candidateIndex, screen.job = #screen.candidates, pending
            screen.previewNotice = nil
            if page().kind == "compare" then screen.compare() else screen.preview() end
          else
            screen.previewNotice = (pending.anchor or pending.finite) and ((pending.status == "incomplete" or pending.proofLimited or pending.prepared.seedChoices) and "Proof limit: more matches not ruled out." or "No more matches. L: previous result")
              or "No new match yet. R: keep searching"
          end
        end
        return
      end
      if screen.job and screen.job.status == "searching" then
        Solver.step(screen.job, screen.job.prepared.encounter.locks and 16 or 512)
        if screen.job.status ~= "searching" then
          if page().kind == "progress" then table.remove(screen.pages) end
          services.log(table.concat(Adapter.explain(screen.job), "\n"))
          if screen.job.status == "valid" then
            screen.candidates, screen.candidateIndex = { screen.job }, 1
            screen.searchCursor = Model.copy(screen.job)
            screen.preview()
          else info(screen.job.status == "impossible" and "NO EXACT MATCH" or "SEARCH INCOMPLETE", { screen.job.message, "Your choices have not been changed." }) end
        end
      end
    end
    function screen.draw() View.draw(screen) end
    Stack.push("legalmon", screen, { fullscreen = true })
    return screen
  end

  return Screen
end
