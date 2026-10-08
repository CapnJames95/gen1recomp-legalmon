return function(Solver)
  local Model = {}
  Model.natures = { "Hardy", "Lonely", "Brave", "Adamant", "Naughty", "Bold", "Docile", "Relaxed", "Impish", "Lax", "Timid", "Hasty", "Serious", "Jolly", "Naive", "Modest", "Mild", "Quiet", "Bashful", "Rash", "Calm", "Gentle", "Sassy", "Careful", "Quirky" }

  function Model.copy(value, memo)
    if type(value) ~= "table" then return value end
    memo = memo or {}
    if memo[value] then return memo[value] end
    local result = {}
    memo[value] = result
    for key, entry in pairs(value) do result[key] = Model.copy(entry, memo) end
    return result
  end

  function Model.ivTotal(ivs)
    local total = 0
    for _, stat in ipairs(Solver.stats) do total = total + ivs[stat] end
    return total
  end

  function Model.bestCandidate(candidates)
    local bestIndex, bestTotal
    for index, job in ipairs(candidates or {}) do
      if job.status == "valid" and job.result then
        local total = Model.ivTotal(job.result.ivs)
        if not bestTotal or total > bestTotal then bestIndex, bestTotal = index, total end
      end
    end
    return bestIndex, bestTotal
  end

  function Model.minimum(row, origin, acquisition)
    local minimum = 100
    for _, encounter in ipairs(row.encounters) do
      if (origin == nil or encounter.version == origin) and (acquisition == nil or Solver.acquisition(encounter) == acquisition) then minimum = math.min(minimum, encounter.minimum) end
    end
    return minimum
  end

  function Model.selectSpecies(request, catalog, species)
    local selected = Model.copy(request)
    selected.species = species
    if species ~= 201 then selected.form = nil end
    local minimum
    for _, encounter in ipairs(catalog[species] and catalog[species].encounters or {}) do
      if (selected.origin == nil or encounter.version == selected.origin) and (selected.acquisition == nil or Solver.acquisition(encounter) == selected.acquisition) then
        minimum = math.min(minimum or encounter.minimum, encounter.minimum)
      end
    end
    if minimum then selected.level = minimum end
    return selected
  end

  function Model.originHint(row, origin, acquisition)
    if row then
      for _, encounter in ipairs(row.encounters) do
        if (origin == nil or encounter.version == origin) and (acquisition == nil or Solver.acquisition(encounter) == acquisition) then
          return "Supported from Lv." .. Model.minimum(row, origin, acquisition) .. (origin and (" / " .. origin) or " / any supported origin")
        end
      end
    end
    return origin and ("No supported acquisition in " .. origin .. ".") or "Generation unsupported: origin rules not implemented."
  end

  function Model.speciesList(pack, catalog)
    local result = {}
    for national = 1, 386 do
      local species = pack.national and pack.national.toSpecies and pack.national.toSpecies[national]
        or national <= 251 and national or nil
      if species and pack.names[species] and pack.meta[species] and pack.abilities[species] and pack.learnsets[species] then
        result[#result + 1] = { species = species, national = national, name = pack.names[species], supported = catalog[species] ~= nil }
      end
    end
    return result
  end

  function Model.ivLabel(value)
    if value == nil then return "Any" end
    if type(value) == "number" then return tostring(value) end
    return value.min .. "-" .. value.max
  end

  function Model.pageMarker(page, version)
    if page.title == "SPECIES" then
      local selected = page.rows and page.rows[page.cursor]
      return selected and selected.national and string.format("#%03d", selected.national) or ""
    end
    return page.rows and #page.rows > 6 and (page.cursor .. "/" .. #page.rows) or version == "ruby" and "RU" or version == "sapphire" and "SA" or version == "emerald" and "EM" or version == "leafgreen" and "LG" or "FR"
  end

  function Model.ivs(request, mode)
    local changed = Model.copy(request)
    changed.ivs = {}
    changed.minTotal, changed.minPerfect = nil, nil
    for _, stat in ipairs(Solver.stats) do
      if mode == "minimum20" then changed.ivs[stat] = { min = 20, max = 31 }
      elseif mode == "minimum" then changed.ivs[stat] = { min = 25, max = 31 }
      elseif mode == "perfect" then changed.ivs[stat] = 31 end
    end
    if mode == "zeroAttack" then changed.ivs.atk = 0 end
    if mode == "zeroSpeed" then changed.ivs.spe = 0 end
    if mode == "five" then changed.minPerfect = 5 end
    return changed
  end

  function Model.frameOptions(catalog, trainer, level, frames, perfect, shinyOnly, origin, perfectSeed, ot, acquisition)
    local options = {}
    for species = 1, 411 do
      local row = catalog[species]
      if row then
        local request = Model.ivs({ species = species, level = math.max(level, Model.minimum(row, origin, acquisition)), origin = origin, acquisition = acquisition, shiny = shinyOnly and true or nil }, perfect and "perfect" or "any")
        request.ot = Model.copy(ot)
        local seen = {}
        for profileIndex in ipairs(row.encounters or {}) do
          local prepared = Solver.prepare(request, catalog, trainer, profileIndex)
          if prepared then
            local candidates = perfect and Solver.perfectCandidates(prepared, perfectSeed) or frames
            for _, sourceFrame in ipairs(candidates) do
              local frame = Solver.candidate(sourceFrame.seed, prepared, sourceFrame.pokePidSeed)
              local key = Solver.resultKey(frame, prepared)
              if not seen[key] and Solver.attachProof(frame, prepared) and Solver.verify(frame, prepared) then
                seen[key] = true
                options[#options + 1] = { request = Model.copy(request), job = {
                  status = "valid", prepared = Model.copy(prepared), result = Model.copy(frame),
                  anchor = true, checked = #candidates, limit = #candidates,
                  message = Solver.encounter(frame, prepared).method .. " proof verified; finder options explicitly applied. Finite sampled result set, not exhaustive coverage.",
                } }
              end
            end
          end
        end
      end
    end
    return options
  end

  function Model.perfectOptions(catalog, trainer, level, seed, shinyOnly, origin, ot, acquisition)
    return Model.frameOptions(catalog, trainer, level, {}, true, shinyOnly, origin, seed, ot, acquisition)
  end

  function Model.shinyOptions(catalog, trainer, level, seed, origin, ot, acquisition)
    return Model.frameOptions(catalog, trainer, level, { Solver.frame(seed) }, false, true, origin, nil, ot, acquisition)
  end

  function Model.reroll(request, locks, job)
    local changed = Model.copy(request)
    local frame = job and job.status == "valid" and job.result
    for _, key in ipairs({ "nature", "gender", "ability", "shiny" }) do
      if not locks[key] then changed[key] = nil
      elseif frame then
        if key == "nature" then changed[key] = frame.pid % 25
        elseif key == "gender" then changed[key] = Solver.gender(frame.pid, job.prepared.row.ratio)
        elseif key == "shiny" then changed[key] = Solver.shiny(frame.pid, Solver.resultTrainer(job.prepared))
        else
          local abilities = job.prepared.row.abilities
          changed[key] = abilities[Solver.abilitySlot(frame, job.prepared) + 1]
        end
      end
    end
    changed.ivs = changed.ivs or {}
    for _, stat in ipairs(Solver.stats) do
      if not locks[stat] then changed.ivs[stat] = nil
      elseif frame then changed.ivs[stat] = frame.ivs[stat] end
    end
    return changed
  end

  function Model.preset(request, kind)
    local result = Model.ivs(request, "any")
    result.nature, result.gender, result.ability, result.shiny, result.moves = nil, nil, nil, nil, nil
    result.hiddenType, result.hiddenPower = nil, nil
    if kind == "physical" then
      result.nature = 3
      result.ivs.atk = { min = 25, max = 31 }
      result.ivs.spe = { min = 25, max = 31 }
    elseif kind == "special" then
      result.nature = 15
      result.ivs.spa = { min = 25, max = 31 }
      result.ivs.spe = { min = 25, max = 31 }
    end
    return result
  end

  local function normalized(value)
    return tostring(value):upper():gsub("[^A-Z0-9]", "")
  end

  function Model.filter(rows, query)
    local result, needle = {}, normalized(query or "")
    for _, row in ipairs(rows) do
      if normalized(row.label):find(needle, 1, true) then result[#result + 1] = row end
    end
    return result
  end

  function Model.moves(row, level, pack, origin, acquisition)
    local sources, result = {}, {}
    for _, move in ipairs(row.learnset) do
      if move[1] <= level then sources[move[2]] = "Level-up / reminder" end
    end
    for move in pairs(row.machines) do sources[move] = sources[move] or "Gen 3 TM/HM" end
    for move, source in pairs(row.tutors or {}) do sources[move] = sources[move] or (type(source) == "string" and source or "Gen 3 move tutor") end
    for _, encounter in ipairs(row.encounters or {}) do
      if encounter.minimum <= level and (not origin or encounter.version == origin) and (not acquisition or Solver.acquisition(encounter) == acquisition) then
        if encounter.method=='Emerald egg' and encounter.species==172 then sources[344]='Emerald breeding with a Light Ball parent' end
        for move in pairs(encounter.eggMoves or {}) do sources[move] = sources[move] or "Gen 3 egg move; validate a compatible father's full moveset" end
        for move in pairs(encounter.sharedEggMoves or {}) do sources[move] = sources[move] or "Gen 3 shared-parent level-up inheritance; validate both parents" end
        for move, source in pairs(Solver.preEvolutionMoves(encounter, level)) do
          sources[move] = sources[move] or "Pre-evolution species " .. source.species .. "; requires matching acquisition validation"
        end
      end
    end
    for move, source in pairs(sources) do
      result[#result + 1] = { value = move, label = pack.move_names[move] or tostring(move), help = source }
    end
    table.sort(result, function(first, second) return first.label < second.label end)
    return result
  end

  function Model.library(value)
    local result = { favorites = {}, recent = {}, ui = {} }
    if type(value) ~= "table" then return result end
    if type(value.ui) == "table" then
      for _, key in ipairs({ "shinyOnly", "animate", "cries" }) do
        if type(value.ui[key]) == "boolean" then result.ui[key] = value.ui[key] end
      end
      if type(value.ui.request) == "table" then result.ui.request = Model.copy(value.ui.request) end
      result.ui.places = {}
      local count = 0
      for title, place in pairs(type(value.ui.places) == "table" and value.ui.places or {}) do
        if count < 64 and type(title) == "string" and #title <= 80 and type(place) == "table" then
          local cursor = type(place.cursor) == "number" and place.cursor or 1
          if cursor ~= cursor or cursor < 1 or cursor > 10000 then cursor = 1 end
          result.ui.places[title] = { cursor = math.floor(cursor), query = type(place.query) == "string" and place.query:sub(1, 16) or nil }
          count = count + 1
        end
      end
    end
    for _, key in ipairs({ "favorites", "recent" }) do
      for _, entry in ipairs(type(value[key]) == "table" and value[key] or {}) do
        if #result[key] < 20 and type(entry) == "table" and type(entry.name) == "string"
          and type(entry.request) == "table" and type(entry.request.species) == "number" then
          result[key][#result[key] + 1] = Model.copy(entry)
        end
      end
    end
    return result
  end

  function Model.remember(library, request, name, favorite)
    local key = favorite and "favorites" or "recent"
    table.insert(library[key], 1, { name = name, request = Model.copy(request) })
    while #library[key] > (favorite and 20 or 10) do table.remove(library[key]) end
  end

  function Model.alternatives(request, catalog, trainer)
    local proposals = {}
    local function offer(label, help, changed)
      local prepared = Solver.prepare(changed, catalog, trainer)
      if prepared then proposals[#proposals + 1] = { label = label, help = help, request = changed } end
    end
    local relaxed = Model.ivs(request, "any")
    offer("Allow any IVs", "Replaces all six IV constraints. Other choices stay.", relaxed)
    relaxed = Model.copy(request)
    relaxed.nature = nil
    offer("Allow any nature", "Removes only the nature constraint.", relaxed)
    relaxed = Model.copy(request)
    relaxed.gender, relaxed.ability = nil, nil
    offer("Any gender / ability", "Removes gender and ability constraints.", relaxed)
    relaxed = Model.copy(request)
    relaxed.shiny = nil
    offer("Either shiny status", "Removes only the shiny requirement.", relaxed)
    relaxed = Model.copy(request)
    relaxed.moves = nil
    offer("Use automatic moves", "Replaces moves with ROM level-up defaults.", relaxed)
    relaxed = Model.copy(request)
    relaxed.hiddenType, relaxed.hiddenPower, relaxed.minTotal, relaxed.minPerfect = nil, nil, nil, nil
    offer("Clear extra IV filters", "Removes Hidden Power, total and perfect-count requirements only.", relaxed)
    relaxed = Model.preset(request, "any")
    if catalog[request.species] then relaxed.level = math.max(request.level, Model.minimum(catalog[request.species], request.origin)) end
    offer("Any supported build", "Keeps species; raises level if needed; clears all other constraints.", relaxed)
    return proposals
  end

  function Model.diagnose(request, catalog, trainer, job)
    local prepared, err = Solver.prepare(request, catalog, trainer)
    if job and job.prepared then prepared, err = job.prepared, nil end
    local lines = { err and err.message or job and job.message or "Validate first to test PID/IV relationships." }
    if job and job.status == "exhausted" then lines[#lines + 1] = "Budget reached, not proof of impossibility. Resume search." end
    local perfect = prepared ~= nil
    if prepared then
      for _, stat in ipairs(Solver.stats) do if prepared.ivs[stat].min ~= 31 then perfect = false end end
    end
    if perfect and not prepared.egg and not prepared.event and not prepared.trade and not prepared.roamer and not prepared.unown and not prepared.gamecube then
      local natures, seen, shiny = {}, {}, false
      local method = prepared.wildVariant or "Method 1"
      for _, frame in ipairs(Solver.perfectFrames(nil, method)) do
        local name = Model.natures[frame.pid % 25 + 1]
        if not seen[name] then natures[#natures + 1], seen[name] = name, true end
        if Solver.shiny(frame.pid, Solver.resultTrainer(prepared)) then shiny = true end
      end
      lines[#lines + 1] = "All-31 " .. method .. " natures: " .. table.concat(natures, ", ") .. "."
      if request.nature and not seen[Model.natures[request.nature + 1]] then lines[#lines + 1] = "Your exact nature conflicts with all-31 IVs in this method only; other acquisition methods may differ." end
      if request.shiny and not shiny then lines[#lines + 1] = "None of these perfect seeds is shiny for your trainer IDs." end
      if request.hiddenType and request.hiddenType ~= 16 then lines[#lines + 1] = "All-31 IVs force Dark Hidden Power (70)." end
    end
    lines[#lines + 1] = "Alternatives need your approval and a new validation; no choices change automatically."
    return lines
  end

  function Model.report(request, job, pack, lines)
    local result = { "LegalMon 0.17.1 - legality report", "REQUEST",
      "Species: " .. tostring(request.species) .. " " .. tostring(pack.names[request.species]),
      "Level: " .. tostring(request.level),
      "Unown form: " .. (request.form ~= nil and Solver.unownLetters:sub(request.form + 1, request.form + 1) or "Any"),
      "Origin filter: " .. tostring(request.origin or "Any supported"),
      "Acquisition filter: " .. tostring(request.acquisition or "Any supported"),
      "Nature: " .. (request.nature and Model.natures[request.nature + 1] or "Any"),
      "Gender: " .. tostring(request.gender or "Any"), "Ability: " .. tostring(request.ability or "Any"),
      "Shiny: " .. (request.shiny == nil and "Any" or tostring(request.shiny)) }
    if request.ot then result[#result + 1] = "Requested OT: " .. request.ot.name .. "; TID " .. request.ot.tid .. "; SID " .. request.ot.sid .. "; gender " .. request.ot.gender end
    for _, stat in ipairs(Solver.stats) do result[#result + 1] = "IV " .. stat .. ": " .. Model.ivLabel((request.ivs or {})[stat]) end
    result[#result + 1] = "Moves: " .. (request.moves and table.concat(request.moves, ", ") or "Automatic")
    result[#result + 1] = "IV total minimum: " .. tostring(request.minTotal or 0) .. "; perfect count minimum: " .. tostring(request.minPerfect or 0)
    result[#result + 1] = "Hidden Power: " .. (Solver.hiddenTypes[request.hiddenType] or "Any") .. "; minimum power: " .. tostring(request.hiddenPower or 30)
    result[#result + 1] = "RESULT: " .. tostring(job and job.status or "Not checked")
    if job and job.pidDomain then
      result[#result + 1] = "Poke Spot PID trials: " .. tostring(job.pidChecked or job.checked) .. " / " .. job.pidDomain
      result[#result + 1] = "Search stage: " .. (job.phase == "pid" and "PID activation" or "IV/level frames for one proven PID")
    end
    for _, line in ipairs(lines or {}) do result[#result + 1] = line end
    result[#result + 1] = "This is a generated Pokemon. External PKHeX acceptance is a separate check."
    return table.concat(result, "\n") .. "\n"
  end

  return Model
end
