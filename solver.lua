local Solver = {}
Solver.unownLetters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ!?"
Solver.stats = { "hp", "atk", "def", "spe", "spa", "spd" }
Solver.hiddenTypes = { "Fighting", "Flying", "Poison", "Ground", "Rock", "Bug", "Ghost", "Steel", "Fire", "Water", "Grass", "Electric", "Psychic", "Ice", "Dragon", "Dark" }

function Solver.hiddenPower(ivs)
  local typeBits, powerBits = 0, 0
  for index, stat in ipairs(Solver.stats) do
    typeBits = typeBits + ivs[stat] % 2 * 2 ^ (index - 1)
    powerBits = powerBits + math.floor(ivs[stat] / 2) % 2 * 2 ^ (index - 1)
  end
  return math.floor(typeBits * 15 / 63) + 1, math.floor(powerBits * 40 / 63) + 30
end

local function integer(value, low, high)
  return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end

local function multiply(value, multiplier)
  local low, high = value % 65536, math.floor(value / 65536)
  return (low * (multiplier % 65536)
    + ((high * (multiplier % 65536) + low * math.floor(multiplier / 65536)) % 65536) * 65536) % 4294967296
end

function Solver.next(seed)
  return (multiply(seed, 1103515245) + 24691) % 4294967296
end

function Solver.previous(seed)
  return (multiply(seed, 4005161829) + 171270561) % 4294967296
end

function Solver.gcNext(seed)
  return (multiply(seed, 214013) + 2531011) % 4294967296
end

function Solver.gcPrevious(seed)
  return (multiply(seed, 3115528533) + 2708534849) % 4294967296
end

function Solver.nameOrigin(seed)
  local pending, visited, cursor = { seed }, {}, 1
  while cursor <= #pending and cursor <= 4096 do
    local state = pending[cursor]
    cursor = cursor + 1
    if not visited[state] then
      visited[state] = true
      local tail, clear = state, true
      for _ = 1, 4 do
        local spawn = tail
        for _ = 1, 4 do spawn = Solver.gcPrevious(spawn) end
        if math.floor(spawn / 65536) <= 6553 then pending[#pending + 1] = Solver.gcPrevious(spawn) end
        if math.floor(tail / 65536) <= 6553 then clear = false; break end
        tail = Solver.gcPrevious(tail)
      end
      if clear then return tail end
    end
  end
  return false
end

local trainerSeeds = {}
function Solver.trainerSeed(trainer, origin)
  local cube = origin == "colosseum" or origin == "xd"
  local key = (cube and "cube" or "gba") .. ":" .. trainer.tid .. ":" .. trainer.sid
  if trainerSeeds[key] ~= nil then return trainerSeeds[key] end
  local advance = cube and Solver.gcNext or Solver.next
  local first, second = cube and trainer.tid or trainer.sid, cube and trainer.sid or trainer.tid
  for low = 0, 65535 do
    local state = first * 65536 + low
    if math.floor(advance(state) / 65536) == second then
      local valid = true
      if cube then
        for _ = 1, 1001 do state = Solver.gcPrevious(state) end
        state = Solver.nameOrigin(state)
        valid = state ~= false
      else state = Solver.previous(state) end
      if valid then trainerSeeds[key] = state; return state end
    end
  end
  trainerSeeds[key] = false
  return false
end

local function xor(first, second)
  local result, place = 0, 1
  for _ = 1, 16 do
    if first % 2 ~= second % 2 then result = result + place end
    first, second, place = math.floor(first / 2), math.floor(second / 2), place * 2
  end
  return result
end

function Solver.shiny(pid, trainer)
  return xor(xor(pid % 65536, math.floor(pid / 65536)), xor(trainer.tid, trainer.sid)) < 8
end

function Solver.gender(pid, ratio)
  if ratio == 255 then return "U" end
  if ratio == 254 then return "F" end
  if ratio == 0 then return "M" end
  return pid % 256 < ratio and "F" or "M"
end

function Solver.frame(seed, method)
  local state = Solver.next(seed)
  local low = math.floor(state / 65536)
  state = Solver.next(state)
  local pid = low + math.floor(state / 65536) * 65536
  if method == "Method H2" then state = Solver.next(state) end
  state = Solver.next(state)
  local first = math.floor(state / 65536)
  if method == "Method H4" then state = Solver.next(state) end
  state = Solver.next(state)
  local second = math.floor(state / 65536)
  return { seed = seed, pid = pid, ivs = {
    hp = first % 32, atk = math.floor(first / 32) % 32, def = math.floor(first / 1024) % 32,
    spe = second % 32, spa = math.floor(second / 32) % 32, spd = math.floor(second / 1024) % 32,
  } }
end

function Solver.eggFrame(seed, prepared)
  if prepared.encounter.version == 'emerald' then
    -- No-Everstone witness: pending PID uses the primary RNG low word and
    -- a vblank-seeded secondary RNG high word. Pickup has independent timing.
    local pending = Solver.next(seed)
    local vblank = 1 + seed % 65535
    local result = Solver.frame(seed)
    result.pid = math.floor(Solver.next(vblank)/65536)*65536 + math.floor(pending/65536)%65534 + 1
    result.pendingSeed, result.vblankSeed = seed, vblank
    local state=seed
    for _=1,4 do state=Solver.next(state) end -- native initial PID and IV rolls
    local available,selected,parents={'hp','atk','def','spe','spa','spd'},{},{}
    for i=1,3 do
      state=Solver.next(state)
      selected[i]=available[math.floor(state/65536) % #available + 1]
      -- Emerald removes the loop position, allowing duplicate inheritance.
      table.remove(available,i)
    end
    for i=1,3 do
      state=Solver.next(state);parents[i]=math.floor(state/65536)%2+1
      result.ivs[selected[i]]=prepared.ivs[selected[i]].max
    end
    result.inherited,result.parents=selected,parents
    return result
  end
  local pending = seed
  for _ = 1, 11 do pending = Solver.next(pending) end
  while math.floor(pending / 65536) * 100 >= 50 * 65535 do pending = Solver.next(pending) end
  local low = math.floor(Solver.next(pending) / 65536) % 65534 + 1
  local state = Solver.next(seed)
  local result = Solver.frame(Solver.previous(seed))
  result.seed, result.pid, result.pendingSeed = seed, math.floor(state / 65536) * 65536 + low, pending
  state = Solver.next(Solver.next(state))
  local available, selected, parents = { "hp", "atk", "def", "spe", "spa", "spd" }, {}, {}
  for index = 1, 3 do
    state = Solver.next(state)
    selected[index] = table.remove(available, math.floor(state / 65536) % #available + 1)
  end
  for index = 1, 3 do
    state = Solver.next(state)
    parents[index] = math.floor(state / 65536) % 2 + 1
    result.ivs[selected[index]] = prepared.ivs[selected[index]].max
  end
  result.inherited, result.parents = selected, parents
  return result
end

function Solver.pokePID(seed, prepared)
  local slot = math.floor(seed / 65536) % 100
  if (slot < 50 and 0 or slot < 85 and 1 or 2) ~= prepared.encounter.pokespot then return nil end
  local previous = Solver.gcPrevious(seed)
  local roll = math.floor(previous / 65536)
  if roll % 3 ~= 0 then
    if roll % 100 < 10 then return nil end
    previous = Solver.gcPrevious(previous)
    if math.floor(previous / 65536) % 3 ~= 0 then return nil end
  end
  local high = Solver.gcNext(seed)
  local pid = math.floor(high / 65536) * 65536 + math.floor(Solver.gcNext(high) / 65536)
  return pid, Solver.gcPrevious(previous)
end

function Solver.gcPIDSeeds(pid)
  if not integer(pid, 0, 4294967295) then return {} end
  local high, low = math.floor(pid / 65536), pid % 65536
  local target = (low - 214013 * high) % 65536
  local seeds = {}
  for wrap = 0, 3 do
    local suffix = math.ceil((target * 65536 + wrap * 4294967296 - 2531011) / 214013)
    if suffix >= 0 and suffix <= 65535 then
      local state = high * 65536 + suffix
      if math.floor(Solver.gcNext(state) / 65536) == low then
        seeds[#seeds + 1] = Solver.gcPrevious(state)
      end
    end
  end
  return seeds
end

local function pokePIDMatches(pid, prepared, onlyShiny)
  local desiredShiny = prepared.shiny
  if onlyShiny then desiredShiny = true end
  return pid and (prepared.nature == nil or pid % 25 == prepared.nature)
    and (not prepared.gender or Solver.gender(pid, prepared.row.ratio) == prepared.gender)
    and (desiredShiny == nil or Solver.shiny(pid, Solver.resultTrainer(prepared)) == desiredShiny)
end

local function pokePIDTrial(prepared, seed, cursor, onlyShiny)
  if onlyShiny or prepared.shiny == true then
    local trainer = Solver.resultTrainer(prepared)
    local high = math.floor(cursor / 8)
    local low = xor(xor(high, xor(trainer.tid, trainer.sid)), cursor % 8)
    local pid = high * 65536 + low
    if pokePIDMatches(pid, prepared, onlyShiny) then
      for _, origin in ipairs(Solver.gcPIDSeeds(pid)) do
        if Solver.pokePID(origin, prepared) == pid then return origin, seed end
      end
    end
  elseif pokePIDMatches(Solver.pokePID(seed, prepared), prepared, onlyShiny) then
    return seed, Solver.gcNext(seed)
  end
  return nil, Solver.gcNext(seed)
end

function Solver.findPokePID(prepared, seed, onlyShiny)
  local limit = (onlyShiny or prepared.shiny == true) and 524288 or 1000000
  for cursor = 0, limit - 1 do
    local found
    found, seed = pokePIDTrial(prepared, seed, cursor, onlyShiny)
    if found then return found end
  end
  return nil
end

function Solver.candidate(seed, prepared, pokePidSeed)
  if prepared.trade then
    local ivs = {}
    for _, stat in ipairs(Solver.stats) do ivs[stat] = prepared.encounter.fixedIVs[stat] end
    return { seed = seed, pid = prepared.encounter.fixedPID, ivs = ivs,
      fixedAbility = prepared.encounter.fixedAbility, otGender = prepared.encounter.ot.gender }
  end
  if prepared.gamecube then
    local ivSeed, npc, teamRolls, lastPid = seed, nil, 0, nil
    if prepared.encounter.locks then
      local state = Solver.gcNext(seed)
      npc = { tid = math.floor(state / 65536) }
      state = Solver.gcNext(state); npc.sid = math.floor(state / 65536)
      for _, lock in ipairs(prepared.encounter.locks) do
        for _ = 1, 5 do state = Solver.gcNext(state) end
        local accepted
        repeat
          state = Solver.gcNext(state); local high = math.floor(state / 65536)
          state = Solver.gcNext(state); local pid = high * 65536 + math.floor(state / 65536)
          lastPid = pid
          teamRolls = teamRolls + 1
          accepted = lock.shadow or (pid % 25 == lock[1] and (lock[2] == 2 or (pid % 256 < lock[3] and 1 or 0) == lock[2]))
          if not lock.shadow or prepared.encounter.version == "xd" then accepted = accepted and not Solver.shiny(pid, npc) end
          if prepared.encounter.version == "xd" then accepted = accepted and not Solver.shiny(pid, Solver.resultTrainer(prepared)) end
        until accepted
      end
      ivSeed = Solver.gcNext(Solver.gcNext(state))
    end
    if prepared.encounter.ereader then
      return { seed = seed, pid = lastPid, gcAbility = 0, pidRolls = 0, teamSeed = seed,
        teamRolls = teamRolls, ivs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 } }
    end
    local state = Solver.gcNext(ivSeed)
    local first = math.floor(state / 65536)
    state = Solver.gcNext(state)
    local second = math.floor(state / 65536)
    state = Solver.gcNext(state)
    local ability = math.floor(state / 65536) % 2
    local pid, rolls = nil, 0
    repeat
      state = Solver.gcNext(state); local high = math.floor(state / 65536)
      state = Solver.gcNext(state); pid = high * 65536 + math.floor(state / 65536)
      rolls = rolls + 1
    until (not prepared.encounter.shinyLocked or not Solver.shiny(pid, Solver.resultTrainer(prepared)))
      and (not prepared.encounter.starter or prepared.encounter.starter == "eevee" or pid % 256 >= 31)
      and (not npc or prepared.encounter.version ~= "xd" or not Solver.shiny(pid, npc))
    local result = { seed = seed, pid = pid, gcAbility = ability, pidRolls = rolls,
      teamSeed = npc and seed, ivSeed = npc and ivSeed, teamRolls = npc and teamRolls,
      otGender = prepared.encounter.ot and prepared.encounter.ot.gender, ivs = {
      hp = first % 32, atk = math.floor(first / 32) % 32, def = math.floor(first / 1024) % 32,
      spe = second % 32, spa = math.floor(second / 32) % 32, spd = math.floor(second / 1024) % 32,
    } }
    if prepared.encounter.pokespot ~= nil then
      result.pokePidSeed = pokePidSeed or seed
      result.pid, result.activationSeed = Solver.pokePID(result.pokePidSeed, prepared)
      result.pid = result.pid or 0
      local levelState = Solver.gcPrevious(Solver.gcPrevious(seed))
      result.pokeLevel = 10 + math.floor(levelState / 65536) % (prepared.encounter.maxLevel - 9)
      local animation = seed
      for _ = 1, 6 do animation = Solver.gcPrevious(animation) end
      for distance = 1, 5 do
        animation = Solver.gcPrevious(animation)
        local roll = math.floor(animation / 65536) % 10
        if distance == 1 and roll < 5 and roll ~= 3 or distance == 2 and roll >= 5 and roll ~= 8 or distance == 5 and roll == 8 then
          result.animationSeed = Solver.gcPrevious(animation); break
        end
      end
    end
    return result
  end
  if prepared.egg then return Solver.eggFrame(seed, prepared) end
  local result = Solver.frame(seed, prepared.encounter.method)
  if prepared.event or prepared.unown then
    result.pid = result.pid % 65536 * 65536 + math.floor(result.pid / 65536)
  end
  if prepared.event then
    if prepared.encounter.antishiny and Solver.shiny(result.pid, prepared.encounter.ot) then result.pid = (math.floor(result.pid / 8) * 8 + 8) % 4294967296 end
    local state = seed
    for _ = 1, 5 do state = Solver.next(state) end
    result.otGender = prepared.encounter.antishiny and (1 - math.floor(state / 65536 / 128) % 2) or 0
  elseif prepared.roamer then
    result.ivs.atk = result.ivs.atk % 8
    result.ivs.def, result.ivs.spe, result.ivs.spa, result.ivs.spd = 0, 0, 0, 0
  end
  return result
end

function Solver.resultTrainer(prepared)
  return prepared.fixedOT or prepared.encounter.ot or prepared.customOT or prepared.trainer
end

function Solver.starterSeeds(trainer, starter)
  local seeds = {}
  for low = 0, 65535 do
    local state = trainer.tid * 65536 + low
    local sidState = Solver.gcNext(state)
    if math.floor(sidState / 65536) == trainer.sid then
      local nameState = state
      for _ = 1, 1001 do nameState = Solver.gcPrevious(nameState) end
      local allowed = Solver.nameOrigin(nameState)
      if allowed then
        local ivSeed = Solver.gcNext(Solver.gcNext(sidState))
        if starter == "espeon" then
          local cursor = ivSeed
          for _ = 1, 3 do cursor = Solver.gcNext(cursor) end
          local pid
          repeat
            cursor = Solver.gcNext(cursor); local high = math.floor(cursor / 65536)
            cursor = Solver.gcNext(cursor); pid = high * 65536 + math.floor(cursor / 65536)
          until pid % 256 >= 31 and not Solver.shiny(pid, trainer)
          ivSeed = Solver.gcNext(Solver.gcNext(cursor))
        end
        seeds[#seeds + 1] = ivSeed
      end
    end
  end
  return seeds
end

function Solver.abilitySlot(frame, prepared)
  if prepared.row.abilities[2] == 0 then return 0 end
  return frame.fixedAbility or frame.gcAbility or frame.pid % 2
end

function Solver.unownForm(pid)
  return (pid % 4 + math.floor(pid / 256) % 4 * 4 + math.floor(pid / 65536) % 4 * 16 + math.floor(pid / 16777216) % 4 * 64) % 28
end

local function failure(code, message)
  return { status = code, message = message }
end

function Solver.acquisition(encounter)
  if (encounter.method == "FRLG trade" or encounter.method == "Emerald trade") then return "trade" end
  if (encounter.method == "FRLG egg" or encounter.method == "Emerald egg") then return "egg" end
  if encounter.method ~= "GameCube" then return "cartridge" end
  if encounter.ereader then return "ereader" end
  if encounter.pokespot ~= nil then return "pokespot" end
  if encounter.starter then return "starter" end
  if encounter.ot then return "trade" end
  return encounter.purified and "shadow" or "gift"
end

function Solver.preEvolutionMoves(encounter, level)
  local moves, history = {}, {}
  local targetLevel = level
  for index = #(encounter.steps or {}), 1, -1 do
    local step = encounter.steps[index]
    if not step.species or not step.learnset or step.method < 1 or step.method > 7 then return {}, nil end
    local cost = (step.method <= 4) and 1 or 0
    local sourceLevel = targetLevel - cost
    if sourceLevel < encounter.level or step.method == 4 and targetLevel < step.param then return {}, nil end
    history[index] = { species = step.species, sourceLevel = sourceLevel, teachingLevel = targetLevel,
      evolutionLevel = targetLevel, method = step.method }
    for _, move in ipairs(step.learnset) do
      if move[1] <= targetLevel and not moves[move[2]] then
        moves[move[2]] = { step = index, level = move[1], species = step.species, source = "Gen 3 level-up/reminder" }
      end
    end
    for move in pairs(step.machines or {}) do
      if not moves[move] then moves[move] = { step = index, level = sourceLevel, species = step.species, source = "Gen 3 TM/HM" } end
    end
    for move, source in pairs(step.tutors or {}) do
      if not moves[move] then moves[move] = { step = index, level = sourceLevel, species = step.species,
        source = type(source) == "string" and source or "Gen 3 tutor" } end
    end
    targetLevel = sourceLevel
  end
  return moves, history
end

function Solver.breedingProof(encounter, moves, catalog, limits)
  if type(moves) ~= "table" or #moves < 1 or #moves > 4 then return nil, 0 end
  local seen = {}
  for _, move in ipairs(moves) do
    if not integer(move, 1, 354) or seen[move] then return nil, 0 end
    seen[move] = true
  end
  limits = limits or {}
  local active, proven, nodes = {}, {}, 0
  local prove, pairProof
  pairProof = function(profile, required, depth)
    for _, pair in ipairs(profile.eggParents or {}) do
      local maternal, possible = {}, true
      for _, move in ipairs(required) do
        if not (profile.eggMoves or {})[move] then
          if (profile.sharedEggMoves or {})[move] then maternal[#maternal + 1] = move
          else possible = false; break end
        end
      end
      if possible then
        local father = prove(pair.species, required, depth + 1)
        local mother = father and prove(pair.motherSpecies, maternal, depth + 1)
        if mother then
          return { species = pair.species, motherSpecies = pair.motherSpecies, moves = father.moves,
            motherMoves = mother.moves, fatherProof = father, motherProof = mother }
        end
      end
      if nodes >= (limits.nodes or 2048) then break end
    end
  end
  prove = function(species, required, depth)
    local row = catalog[species]
    if not row or depth > (limits.depth or 16) or nodes >= (limits.nodes or 2048) then return nil end
    local sorted = {}
    for index, move in ipairs(required) do sorted[index] = move end
    table.sort(sorted)
    local key = species .. ":" .. table.concat(sorted, ",")
    local memoKey = key .. ":" .. depth
    if proven[memoKey] then return proven[memoKey] end
    if active[key] then return nil end
    nodes = nodes + 1
    active[key] = true
    local function finish(proof)
      active[key] = nil
      if proof then proven[memoKey] = proof end
      return proof
    end
    local direct, missing = {}, {}
    for _, move in ipairs(sorted) do
      local source = (row.parentMoves or {})[move] or (row.sketchMoves or {})[move]
      if source then direct[move] = source else missing[#missing + 1] = move end
    end
    if #missing == 0 then return finish({ species = species, moves = direct }) end
    for profileIndex, profile in ipairs(row.encounters or {}) do
      if profile.minimum <= 100 then
        local earlier, history = Solver.preEvolutionMoves(profile, 100)
        local sources, needed, usesHistory = {}, {}, false
        for move, source in pairs(direct) do sources[move] = source end
        for _, move in ipairs(missing) do
          if earlier[move] then
            sources[move] = "Pre-evolution species " .. earlier[move].species .. " " .. earlier[move].source .. " at Lv." .. earlier[move].level
            usesHistory = true
          else needed[#needed + 1] = move end
        end
        local parents = #needed > 0 and (profile.method == "FRLG egg" or profile.method == "Emerald egg") and pairProof(profile, needed, depth)
        if #needed == 0 or parents then
          for _, move in ipairs(needed) do sources[move] = "Gen 3 chained inheritance from species " .. parents.species end
          return finish({ species = species, moves = sources, profileIndex = profileIndex,
            history = usesHistory and history or nil, parents = parents or nil })
        end
      end
      if nodes >= (limits.nodes or 2048) then break end
    end
    return finish(nil)
  end
  local proof = pairProof(encounter, moves, 0)
  return proof, nodes
end

function Solver.prepare(request, catalog, trainer, profileIndex)
  if type(request) ~= "table" or type(catalog) ~= "table" or type(trainer) ~= "table" then
    return nil, failure("invalid", "Request, ROM catalog and trainer are required.")
  end
  if not integer(trainer.tid, 0, 65535) or not integer(trainer.sid, 0, 65535) then
    return nil, failure("unsupported", "A saved trainer ID and secret ID are required.")
  end
  if not integer(request.species, 1, 411) or not catalog[request.species] then
    return nil, failure("unsupported", "Species has no supported acquisition path.")
  end
  local row = catalog[request.species]
  if request.form ~= nil and (request.species ~= 201 or not integer(request.form, 0, 27)) then
    return nil, failure("invalid", "An Unown form must be 0-27 and is supported only for Unown.")
  end
  if profileIndex ~= nil and not integer(profileIndex, 1, #(row.encounters or {})) then
    return nil, failure("invalid", "Acquisition profile index is invalid.")
  end
  if not integer(request.level, 1, 100) then return nil, failure("invalid", "Level must be 1-100.") end
  local encounter, eligible = nil, {}
  local origins = { firered = true, leafgreen = true, ruby = true, sapphire = true, emerald = true, colosseum = true, xd = true }
  if request.origin ~= nil and not origins[request.origin] then return nil, failure("invalid", "Unknown origin game.") end
  if request.acquisition ~= nil and not ({ cartridge = true, egg = true, ereader = true, pokespot = true, starter = true, trade = true, shadow = true, gift = true })[request.acquisition] then
    return nil, failure("invalid", "Unknown acquisition filter.")
  end
  for index, candidate in ipairs(row.encounters or {}) do
    if (profileIndex == nil or profileIndex == index) and candidate.minimum <= request.level and (request.origin == nil or candidate.version == request.origin)
      and (request.acquisition == nil or Solver.acquisition(candidate) == request.acquisition)
      and (request.form == nil or candidate.method == "Unown H1" and (candidate.form or 0) == request.form) then
      eligible[#eligible + 1] = candidate
      encounter = encounter or candidate
    end
  end
  if not encounter then return nil, failure("impossible", "No supported acquisition/evolution path at this level and selected origin.") end
  local customOT
  if request.ot ~= nil then
    local original = request.ot
    if type(original) ~= "table" or type(original.name) ~= "string" or #original.name < 1 or #original.name > 7
      or not original.name:find("%S") or original.name:find("[^A-Za-z0-9 .,!?'%-]")
      or not integer(original.tid, 0, 65535) or not integer(original.sid, 0, 65535) or not integer(original.gender, 0, 1) then
      return nil, failure("invalid", "Custom OT needs a 1-7 character English name, TID/SID 0-65535 and gender 0 or 1.")
    end
    if encounter.ot then return nil, failure("impossible", "This acquisition has a fixed original trainer. Select Your trainer to retain the required NPC/event OT.") end
    customOT = { name = original.name, tid = original.tid, sid = original.sid, gender = original.gender }
  end
  if encounter.method == "GameCube" and (encounter.ot or customOT or trainer).gender ~= 0 then
    return nil, failure("impossible", "Colosseum/XD original trainers must be male. Choose a male custom OT; your player identity will not be changed.")
  end
  if encounter.ereader then
    local original = customOT or trainer
    if type(original.name) ~= "string" or #original.name > 5 or not original.name:match("^[A-Z0-9]+$") then
      return nil, failure("unsupported", "Japanese e-Reader delivery currently supports a 1-5 character uppercase Latin/digit OT only. Choose a compatible custom male OT. The Japanese-language Pokemon receives the nickname MON.")
    end
    local lock = encounter.locks[#encounter.locks]
    if request.nature ~= nil and request.nature ~= lock[1] or request.gender and request.gender ~= (lock[2] == 0 and "M" or "F") then
      return nil, failure("impossible", "This e-Reader encounter has a fixed nature and gender.")
    end
  end
  local otSeed
  if not encounter.ot and (encounter.method == "GameCube" or encounter.version == "ruby" or encounter.version == "sapphire") then
    otSeed = Solver.trainerSeed(customOT or trainer, encounter.version)
    if not otSeed then return nil, failure("unsupported", "No trainer-ID RNG proof within the supported origin/name-screen budget. Choose another OT or randomize its draft; exact IDs were not changed.") end
  end
  if encounter.shinyLocked and request.shiny then return nil, failure("impossible", "This acquisition is shiny-locked: XD Shadows, Colosseum starters and Colosseum's Plusle gift cannot be shiny.") end
  if request.nature ~= nil and not integer(request.nature, 0, 24) then
    return nil, failure("invalid", "Nature must be 0-24 or Any.")
  end
  if request.gender ~= nil and request.gender ~= "M" and request.gender ~= "F" and request.gender ~= "U" then
    return nil, failure("invalid", "Gender must be M, F, U or Any.")
  end
  if request.shiny ~= nil and type(request.shiny) ~= "boolean" then
    return nil, failure("invalid", "Shiny must be true, false or Any.")
  end
  if request.ability ~= nil and request.ability ~= row.abilities[1] and request.ability ~= row.abilities[2] then
    return nil, failure("impossible", "Ability is unavailable for this species in the loaded game.")
  end
  if request.ability == 0 then return nil, failure("invalid", "Ability zero is not an ability.") end
  if request.gender and ((row.ratio == 255 and request.gender ~= "U")
    or (row.ratio ~= 255 and request.gender == "U")
    or (row.ratio == 0 and request.gender ~= "M") or (row.ratio == 254 and request.gender ~= "F")) then
    return nil, failure("impossible", "Gender conflicts with this species' gender ratio.")
  end
  local constraints = {}
  if request.ivs ~= nil and type(request.ivs) ~= "table" then return nil, failure("invalid", "IV constraints must be a table.") end
  for key in pairs(request.ivs or {}) do
    local known = false
    for _, stat in ipairs(Solver.stats) do if key == stat then known = true end end
    if not known then return nil, failure("invalid", "Unknown IV stat: " .. tostring(key)) end
  end
  for _, stat in ipairs(Solver.stats) do
    local value = (request.ivs or {})[stat]
    local low, high = 0, 31
    if type(value) == "number" then low, high = value, value
    elseif type(value) == "table" then low, high = value.min, value.max
    elseif value ~= nil then return nil, failure("invalid", "Invalid IV constraint: " .. stat) end
    if not integer(low, 0, 31) or not integer(high, low, 31) then
      return nil, failure("invalid", "IV bounds must be integers from 0 to 31: " .. stat)
    end
    constraints[stat] = { min = low, max = high }
    if encounter.ereader then
      if low > 0 then return nil, failure("impossible", "e-Reader Shadow Pokemon have all six IVs fixed at zero.") end
      constraints[stat].max = 0
    end
  end
  if request.minTotal ~= nil and not integer(request.minTotal, 0, 186) then return nil, failure("invalid", "IV total must be 0-186.") end
  if request.minPerfect ~= nil and not integer(request.minPerfect, 0, 6) then return nil, failure("invalid", "Perfect IV count must be 0-6.") end
  if request.hiddenType ~= nil and not integer(request.hiddenType, 1, 16) then return nil, failure("invalid", "Choose a valid Hidden Power type.") end
  if request.hiddenPower ~= nil and not integer(request.hiddenPower, 30, 70) then return nil, failure("invalid", "Hidden Power strength must be 30-70.") end
  if encounter.ereader and (request.hiddenType and request.hiddenType ~= 1 or request.hiddenPower and request.hiddenPower > 30) then
    return nil, failure("impossible", "Zero-IV e-Reader Pokemon have Fighting Hidden Power with power 30.")
  end
  local maxTotal, maxPerfect = 0, 0
  for _, stat in ipairs(Solver.stats) do
    maxTotal = maxTotal + constraints[stat].max
    if constraints[stat].max == 31 then maxPerfect = maxPerfect + 1 end
  end
  if maxTotal < (request.minTotal or 0) or maxPerfect < (request.minPerfect or 0) then
    return nil, failure("impossible", "IV bounds conflict with the requested total or perfect-IV count.")
  end
  if encounter.antishiny and request.shiny then return nil, failure("impossible", "This implemented event distribution is shiny-locked; the original trainer cannot be changed.") end
  if encounter.method == "FRLG roamer" then
    for _, stat in ipairs({ "def", "spe", "spa", "spd" }) do
      if constraints[stat].min > 0 then return nil, failure("impossible", "FRLG roaming IV bug requires Defense, Speed and both Special IVs to be zero.") end
    end
    if constraints.atk.min > 7 then return nil, failure("impossible", "FRLG roaming IV bug limits Attack IV to 0-7.") end
  end
  local available, defaults = {}, {}
  for _, move in ipairs(row.learnset) do
    if move[1] <= request.level then
      available[move[2]] = "level-up / move reminder"
      local found = false
      for _, existing in ipairs(defaults) do if existing == move[2] then found = true end end
      if not found then
        defaults[#defaults + 1] = move[2]
        if #defaults > 4 then table.remove(defaults, 1) end
      end
    end
  end
  for move in pairs(row.machines or {}) do available[move] = "Gen 3 TM/HM" end
  for move, source in pairs(row.tutors or {}) do available[move] = available[move] or (type(source) == "string" and source or "Gen 3 move tutor") end
  local inheritedMoves, history = Solver.preEvolutionMoves(encounter, request.level)
  local moveHistory, inherited, unproven = nil, {}, {}
  for _, step in ipairs(encounter.steps or {}) do
    for _, move in ipairs(step.learnset or {}) do if move[1] <= request.level then unproven[move[2]] = true end end
    for move in pairs(step.machines or {}) do unproven[move] = true end
    for move in pairs(step.tutors or {}) do unproven[move] = true end
  end
  for move, source in pairs(inheritedMoves) do
    if not available[move] then
      available[move] = "Pre-evolution species " .. source.species .. " " .. source.source .. " (Lv." .. source.level .. ")"
      inherited[move] = source
    end
  end
  if encounter.method=='Emerald egg' and encounter.species==172 then available[344]='Emerald breeding with a Light Ball parent' end
  local eggRequired, eggInheritedMoves, eggMoveFather = {}, {}, nil
  if (encounter.method == "FRLG egg" or encounter.method == "Emerald egg") then
    for move in pairs(encounter.eggMoves or {}) do
      if not available[move] then available[move], eggRequired[move] = "Gen 3 egg move; compatible father required", true end
    end
    for move in pairs(encounter.sharedEggMoves or {}) do
      if not available[move] then available[move], eggRequired[move] = "Gen 3 shared-parent level-up inheritance; compatible pair required", true end
    end
  end
  if request.moves ~= nil and type(request.moves) ~= "table" then
    return nil, failure("invalid", "Moves must be a list or automatic.")
  end
  local moves = request.moves or defaults
  if type(moves) ~= "table" or #moves < 1 or #moves > 4 then
    return nil, failure("invalid", "Choose one to four moves, or use automatic moves.")
  end
  local seen, copied, sources = {}, {}, {}
  for index, move in pairs(moves) do
    if integer(move, 1, 354) and not available[move] and unproven[move] then
      return nil, failure("unsupported", "This earlier-stage move needs a teaching/evolution sequence outside the implemented history model. No constraints were changed; global impossibility is not proven.")
    end
    if not integer(index, 1, #moves) or not integer(move, 1, 354) or not available[move] or seen[move] then
      return nil, failure("impossible", "Moves must be distinct, contiguous and supported by this acquisition's level-up, pre-evolution, TM/HM or tutor history.")
    end
    seen[move], copied[index], sources[index] = true, move, available[move]
    if inherited[move] then moveHistory = history end
    if eggRequired[move] then eggInheritedMoves[#eggInheritedMoves + 1] = move end
  end
  if #eggInheritedMoves > 0 then
    for _, father in ipairs(encounter.eggFathers or {}) do
      local compatible = true
      for _, move in ipairs(eggInheritedMoves) do if not father.moves[move] then compatible = false end end
      if compatible then eggMoveFather = father; break end
    end
    if not eggMoveFather then eggMoveFather = Solver.breedingProof(encounter, eggInheritedMoves, catalog) end
    if not eggMoveFather then
      return nil, failure("unsupported", "No compatible parent-chain proof was found within 2048 states and 16 ancestry levels. Missing move histories or search bounds prevent a global impossibility claim. Nothing was relaxed.")
    end
  end
  if moveHistory or eggMoveFather then eligible = { encounter } end
  return { species = request.species, level = request.level, nature = request.nature, origin = request.origin,
    acquisition = request.acquisition, profileIndex = profileIndex, form = request.form,
    wildVariant = (encounter.method == "Method H2" or encounter.method == "Method H4") and encounter.method or nil,
    gender = request.gender, ability = request.ability, shiny = request.shiny, ivs = constraints,
    moves = copied, sources = sources, moveHistory = moveHistory, eggMoveFather = eggMoveFather, eggInheritedMoves = eggInheritedMoves,
    encounter = encounter, encounters = eligible, row = row,
    minTotal = request.minTotal, minPerfect = request.minPerfect, hiddenType = request.hiddenType, hiddenPower = request.hiddenPower,
    egg = (encounter.method == "FRLG egg" or encounter.method == "Emerald egg"), gamecube = encounter.method == "GameCube", trade = (encounter.method == "FRLG trade" or encounter.method == "Emerald trade"), customOT = customOT, otSeed = otSeed,
    fixedOT = encounter.playerSID and { name = encounter.ot.name, tid = encounter.ot.tid, sid = trainer.sid, gender = encounter.ot.gender } or nil,
    seedChoices = encounter.starter and Solver.starterSeeds(customOT or trainer, encounter.starter) or nil,
    event = encounter.method == "Restricted event", roamer = encounter.method == "FRLG roamer", unown = encounter.method == "Unown H1",
    trainer = { tid = trainer.tid, sid = trainer.sid, name = trainer.name, gender = trainer.gender } }
end

function Solver.matches(frame, prepared)
  local pid = frame.pid
  if prepared.form ~= nil and Solver.unownForm(pid) ~= prepared.form then return false end
  if prepared.nature ~= nil and pid % 25 ~= prepared.nature then return false end
  if prepared.gender and Solver.gender(pid, prepared.row.ratio) ~= prepared.gender then return false end
  local abilities = prepared.row.abilities
  local ability = abilities[Solver.abilitySlot(frame, prepared) + 1]
  if prepared.ability and ability ~= prepared.ability then return false end
  for _, stat in ipairs(Solver.stats) do
    local range = prepared.ivs[stat]
    if frame.ivs[stat] < range.min or frame.ivs[stat] > range.max then return false end
  end
  if prepared.shiny ~= nil and Solver.shiny(pid, Solver.resultTrainer(prepared)) ~= prepared.shiny then return false end
  local total, perfect = 0, 0
  for _, stat in ipairs(Solver.stats) do
    total = total + frame.ivs[stat]
    if frame.ivs[stat] == 31 then perfect = perfect + 1 end
  end
  if total < (prepared.minTotal or 0) or perfect < (prepared.minPerfect or 0) then return false end
  if prepared.hiddenType or prepared.hiddenPower then
    local hiddenType, power = Solver.hiddenPower(frame.ivs)
    if prepared.hiddenType and hiddenType ~= prepared.hiddenType or power < (prepared.hiddenPower or 30) then return false end
  end
  return true
end

function Solver.perfectFrames(seed, method)
  local frames = {}
  if seed ~= nil then
    if not integer(seed, 0, 4294967295) then return frames end
    local frame = Solver.frame(seed, method)
    for _, stat in ipairs(Solver.stats) do if frame.ivs[stat] ~= 31 then return frames end end
    return { frame }
  end
  for index = 0, 131071 do
    local state = (32767 + math.floor(index / 65536) * 32768) * 65536 + index % 65536
    local second = Solver.next(state)
    if method == "Method H4" then second = Solver.next(second) end
    if math.floor(second / 65536) % 32768 == 32767 then
      local origin = Solver.previous(Solver.previous(Solver.previous(state)))
      if method == "Method H2" then origin = Solver.previous(origin) end
      frames[#frames + 1] = Solver.frame(origin, method)
    end
  end
  return frames
end

local perfectSeeds = {}
function Solver.perfectCandidates(prepared, seed)
  local seeds = {}
  if seed ~= nil then
    if not integer(seed, 0, 4294967295) then return {} end
    seeds[1] = seed
  elseif prepared.trade then seeds = { 0 }
  elseif prepared.seedChoices then
    seeds = prepared.seedChoices
  elseif prepared.encounter.locks then
    for index = 0, 127 do seeds[#seeds + 1] = index * 2654435761 % 4294967296 end
  elseif prepared.gamecube then
    if not perfectSeeds.gamecube then
      perfectSeeds.gamecube = {}
      for index = 0, 131071 do
        local state = (32767 + math.floor(index / 65536) * 32768) * 65536 + index % 65536
        if math.floor(Solver.gcNext(state) / 65536) % 32768 == 32767 then
          perfectSeeds.gamecube[#perfectSeeds.gamecube + 1] = Solver.gcPrevious(state)
        end
      end
    end
    seeds = perfectSeeds.gamecube
  elseif prepared.egg or prepared.event then
    local key = prepared.egg and ("egg:" .. prepared.encounter.version) or prepared.encounter.ot.name
    if not perfectSeeds[key] then
      local found, state = {}, 0
      local limit = prepared.event and 65536 or 1000000
      for index = 0, limit - 1 do
        local frame = Solver.candidate(prepared.event and index or state, prepared)
        local perfect = true
        for _, stat in ipairs(Solver.stats) do if frame.ivs[stat] ~= 31 then perfect = false; break end end
        if perfect then found[#found + 1] = frame.seed end
        if prepared.egg and #found == 8 then break end
        state = Solver.next(state)
      end
      perfectSeeds[key] = found
    end
    seeds = perfectSeeds[key]
  else
    local method = prepared.wildVariant or "Method 1"
    if not perfectSeeds[method] then
      perfectSeeds[method] = {}
      for _, frame in ipairs(Solver.perfectFrames(nil, method)) do perfectSeeds[method][#perfectSeeds[method] + 1] = frame.seed end
    end
    seeds = perfectSeeds[method]
  end
  local results = {}
  local pokePidSeed
  if seed == nil and prepared.encounter.pokespot ~= nil then
    pokePidSeed = Solver.findPokePID(prepared, 0)
    if not pokePidSeed then return {} end
  end
  for _, origin in ipairs(seeds) do
    local frame = Solver.candidate(origin, prepared, pokePidSeed)
    local perfect = true
    for _, stat in ipairs(Solver.stats) do if frame.ivs[stat] ~= 31 then perfect = false; break end end
    if perfect then results[#results + 1] = frame end
  end
  return results
end

function Solver.encounter(frame, prepared)
  return (prepared.encounters or { prepared.encounter })[frame.encounterIndex or 1]
end

function Solver.evolutionFloor(encounter, metLevel)
  local level = metLevel
  for _, step in ipairs(encounter.steps or {}) do
    if step.method == 4 or step.method >= 8 and step.method <= 14 then level = math.max(level + 1, step.param)
    elseif step.method >= 1 and step.method <= 3 or step.method == 15 then level = level + 1 end
  end
  return level
end

function Solver.evolutionMatches(frame, encounter, prepared)
  for _, step in ipairs(encounter.steps or {}) do
    if step.method == 11 and math.floor(frame.pid / 65536) % 10 >= 5 then return false end
    if step.method == 12 and math.floor(frame.pid / 65536) % 10 < 5 then return false end
    if step.method >= 8 and step.method <= 10 then
      local matched = false
      local nature = frame.pid % 25
      for level = math.max(step.param, encounter.level + 1), prepared.level do
        local attack = math.floor((2 * step.stats.atk + frame.ivs.atk) * level / 100) + 5
        local defense = math.floor((2 * step.stats.def + frame.ivs.def) * level / 100) + 5
        if math.floor(nature / 5) ~= nature % 5 then
          attack = math.floor(attack * (math.floor(nature / 5) == 0 and 110 or nature % 5 == 0 and 90 or 100) / 100)
          defense = math.floor(defense * (math.floor(nature / 5) == 1 and 110 or nature % 5 == 1 and 90 or 100) / 100)
        end
        if step.method == 8 and attack > defense or step.method == 9 and attack == defense or step.method == 10 and attack < defense then matched = true; break end
      end
      if not matched then return false end
    end
  end
  return true
end

local function attachProof(frame, prepared)
  local encounters = prepared.encounters or { prepared.encounter }
  if prepared.trade then
    if frame.seed ~= 0 or not Solver.evolutionMatches(frame, prepared.encounter, prepared) then return false end
    frame.encounterIndex, frame.metLevel = 1, prepared.encounter.level
    return true
  end
  if prepared.gamecube then
    if prepared.encounter.pokespot ~= nil then
      if not frame.activationSeed or not frame.animationSeed then return false end
      if Solver.evolutionFloor(prepared.encounter, frame.pokeLevel) > prepared.level then return false end
      if not Solver.evolutionMatches(frame, prepared.encounter, prepared) then return false end
      frame.encounterIndex, frame.metLevel = 1, frame.pokeLevel
      return true
    end
    if not Solver.evolutionMatches(frame, prepared.encounter, prepared) then return false end
    if prepared.seedChoices then
      local found = false
      for _, seed in ipairs(prepared.seedChoices) do if seed == frame.seed then found = true end end
      if not found then return false end
    end
    frame.encounterIndex, frame.metLevel = 1, prepared.encounter.level
    return true
  end
  if prepared.event then
    if frame.seed >= 65536 then return false end
    frame.encounterIndex, frame.metLevel = 1, prepared.encounter.level
    return true
  end
  if prepared.roamer then
    frame.encounterIndex, frame.metLevel = 1, prepared.encounter.level
    return true
  end
  if prepared.unown then
    local form = Solver.unownForm(frame.pid)
    local supported = false
    for _, encounter in ipairs(encounters) do if (encounter.form or 0) == form then supported = true end end
    if not supported then return false end
    local state = frame.seed
    for rejected = 0, 4095 do
      local slotState = Solver.previous(state)
      local roll = math.floor(slotState / 65536) % 100
      for index, encounter in ipairs(encounters) do
        local metLevel = encounter.level + math.floor(state / 65536) % (encounter.maxLevel - encounter.level + 1)
        if (encounter.form or 0) == form and roll >= encounter.slotLow and roll < encounter.slotHigh and metLevel <= prepared.level then
          frame.encounterIndex, frame.metLevel = index, metLevel
          frame.originSeed, frame.rejectedPids = Solver.previous(slotState), rejected
          return true
        end
      end
      state = Solver.previous(Solver.previous(state))
      if Solver.unownForm(Solver.candidate(state, prepared).pid) == form then return false end
    end
    return false, "incomplete"
  end
  for index, encounter in ipairs(encounters) do
    if (encounter.method == "FRLG egg" or encounter.method == "Emerald egg") and prepared.egg and Solver.evolutionMatches(frame, encounter, prepared) then
      local low = frame.pid % 65536
      if not encounter.split or encounter.split == "low" and low < 32768 or encounter.split == "high" and low >= 32768 then
        frame.encounterIndex, frame.metLevel = index, 0
        return true
      end
    elseif encounter.method == "Method 1" and not prepared.wildVariant and Solver.evolutionMatches(frame, encounter, prepared) then
      frame.encounterIndex, frame.metLevel = index, encounter.level
      return true
    end
  end
  local state, nature = frame.seed, frame.pid % 25
  for rejected = 0, 4095 do
    if math.floor(state / 65536) % 25 == nature then
      local levelState = Solver.previous(state)
      local slotState = Solver.previous(levelState)
      local roll = math.floor(slotState / 65536) % 100
      for index, encounter in ipairs(encounters) do
        if (encounter.method == "Method H1" and not prepared.wildVariant or encounter.method == prepared.wildVariant)
          and roll >= encounter.slotLow and roll < encounter.slotHigh then
          local metLevel = encounter.level + math.floor(levelState / 65536) % (encounter.maxLevel - encounter.level + 1)
          local originSeed = Solver.previous(slotState)
          local ratePass = not encounter.activationRate or math.floor(originSeed / 65536) % 2880 < encounter.activationRate * 24
          if ratePass and Solver.evolutionFloor(encounter, metLevel) <= prepared.level and Solver.evolutionMatches(frame, encounter, prepared) then
            frame.encounterIndex, frame.metLevel = index, metLevel
            frame.originSeed, frame.rejectedPids = originSeed, rejected
            return true
          end
        end
      end
    end
    state = Solver.previous(Solver.previous(state))
    if Solver.frame(state).pid % 25 == nature then return false end
  end
  return false, "incomplete"
end

function Solver.attachProof(frame, prepared)
  local proven, reason = attachProof(frame, prepared)
  if proven and prepared.moveHistory then
    local first = prepared.moveHistory[1]
    local metLevel = prepared.egg and 5 or frame.metLevel
    if not first or type(metLevel) ~= "number" or metLevel > first.sourceLevel then return false end
  end
  return proven, reason
end

function Solver.verify(frame, prepared)
  if type(frame) ~= "table" or not integer(frame.seed, 0, 4294967295) then return false end
  if prepared.encounter.pokespot ~= nil and not integer(frame.pokePidSeed, 0, 4294967295) then return false end
  local expected = Solver.candidate(frame.seed, prepared, frame.pokePidSeed)
  if expected.pid ~= frame.pid or type(frame.ivs) ~= "table" then return false end
  for _, stat in ipairs(Solver.stats) do if frame.ivs[stat] ~= expected.ivs[stat] then return false end end
  if frame.pendingSeed ~= expected.pendingSeed or frame.vblankSeed ~= expected.vblankSeed then return false end
  if frame.otGender ~= expected.otGender then return false end
  if frame.fixedAbility ~= expected.fixedAbility then return false end
  if frame.gcAbility ~= expected.gcAbility or frame.pidRolls ~= expected.pidRolls then return false end
  if frame.ivSeed ~= expected.ivSeed or frame.teamRolls ~= expected.teamRolls then return false end
  if frame.pokeLevel ~= expected.pokeLevel or frame.activationSeed ~= expected.activationSeed or frame.animationSeed ~= expected.animationSeed then return false end
  if prepared.egg then
    if type(frame.inherited) ~= "table" or type(frame.parents) ~= "table" then return false end
    for index = 1, 3 do if frame.inherited[index] ~= expected.inherited[index] or frame.parents[index] ~= expected.parents[index] then return false end end
  end
  if not Solver.attachProof(expected, prepared) then return false end
  if frame.teamSeed ~= expected.teamSeed then return false end
  if (frame.encounterIndex or 1) ~= expected.encounterIndex then return false end
  if frame.metLevel ~= nil and frame.metLevel ~= expected.metLevel then return false end
  if (expected.originSeed ~= nil or prepared.egg or prepared.encounter.pokespot ~= nil) and frame.metLevel ~= expected.metLevel then return false end
  if frame.originSeed ~= expected.originSeed or frame.rejectedPids ~= expected.rejectedPids then return false end
  return Solver.matches(frame, prepared)
end

function Solver.start(request, catalog, trainer, options)
  local prepared, err = Solver.prepare(request, catalog, trainer, options and options.profileIndex)
  if not prepared then return err end
  options = options or {}
  local anchor = true
  for _, stat in ipairs({ "hp", "atk", "def" }) do
    if prepared.ivs[stat].min ~= prepared.ivs[stat].max then anchor = false end
  end
  if prepared.egg or prepared.event or prepared.trade or prepared.roamer or prepared.seedChoices or prepared.encounter.locks then anchor = false end
  local budget = options.budget or 1000000
  local seed = options.seed or 0
  if not integer(budget, 1, 4294967296) or not integer(seed, 0, 4294967295) then
    return failure("invalid", "Search budget or seed is invalid.")
  end
  local job = { status = "searching", prepared = prepared, checked = 0, anchor = anchor, onlyShiny = options.onlyShiny,
    limit = prepared.trade and 1 or prepared.seedChoices and #prepared.seedChoices or prepared.event and 65536 or anchor and 131072 or budget,
    seed = seed, finite = prepared.trade or prepared.event or prepared.seedChoices ~= nil,
    word = prepared.ivs.hp.min + prepared.ivs.atk.min * 32 + prepared.ivs.def.min * 1024 }
  if prepared.encounter.pokespot ~= nil then
    job.phase, job.pidSeed = "pid", seed
    job.ivAnchor, job.ivLimit = job.anchor, job.limit
    job.anchor, job.finite, job.limit = false, false, budget
    job.pidDomain = (options.onlyShiny or prepared.shiny == true) and 524288 or 4294967296
    job.message = "Stage 1/2: finding a Poke Spot PID. Pause/resume preserves the search position."
  end
  return job
end

function Solver.startAll(request, catalog, trainer, options)
  options = options or {}
  local first = Solver.start(request, catalog, trainer, options)
  if first.status == "invalid" or type(request) ~= "table" or type(catalog) ~= "table" then return first end
  local row = catalog[request.species]
  if not row or not integer(request.level, 1, 100) then return first end
  local profiles, rejected = {}, {}
  for index, encounter in ipairs(row.encounters or {}) do
    if encounter.minimum <= request.level and (request.origin == nil or encounter.version == request.origin)
      and (request.acquisition == nil or Solver.acquisition(encounter) == request.acquisition) then
      local child = Solver.start(request, catalog, trainer, {
        budget = options.budget, seed = options.seed, onlyShiny = options.onlyShiny, profileIndex = index })
      if child.status == "invalid" then return child end
      if child.prepared then profiles[#profiles + 1] = child
      else rejected[#rejected + 1] = { index = index, status = child.status, message = child.message } end
    end
  end
  if #profiles == 0 then
    for _, rejection in ipairs(rejected) do
      if rejection.status == "unsupported" or rejection.status == "incomplete" then
        return { status = "incomplete", message = "No searchable acquisition profile; at least one proof is unsupported or incomplete.", rejectedProfiles = rejected }
      end
    end
    first.rejectedProfiles = rejected
    return first
  end
  return { status = "searching", prepared = profiles[1].prepared, profiles = profiles,
    rejectedProfiles = rejected, profileCursor = 1, checked = 0, limit = options.budget or 1000000, seenResults = {},
    onlyShiny = options.onlyShiny, anchor = false, finite = false,
    message = "Searching all eligible implemented acquisition profiles; exact constraints preserved." }
end

function Solver.resultKey(frame, prepared)
  local trainer = Solver.resultTrainer(prepared)
  local parts = { frame.pid, trainer.tid, trainer.sid, trainer.name or "", trainer.gender or 0,
    Solver.abilitySlot(frame, prepared), prepared.encounter.language or 2 }
  for _, stat in ipairs(Solver.stats) do parts[#parts + 1] = frame.ivs[stat] end
  return table.concat(parts, ":")
end

local function stepProfiles(job, count)
  if job.checked >= job.limit then
    job.status, job.message = "exhausted", "Combined acquisition search budget exhausted; Resume continues all profile cursors. Impossibility is NOT proven."
    return job
  end
  local remaining = math.min(count or 512, job.limit - job.checked)
  local idle = 0
  while remaining > 0 and idle < #job.profiles do
    local index = job.profileCursor
    local child = job.profiles[index]
    job.profileCursor = index % #job.profiles + 1
    if child.status == "valid" then child.status, child.result = "searching", nil end
    if child.status == "exhausted" then
      child.limit, child.status = child.limit + 1000000, "searching"
    end
    if child.status == "searching" then
      idle = 0
      job.prepared, job.activeProfile = child.prepared, index
      child.onlyShiny = job.onlyShiny
      local quantum = math.min(16, remaining)
      for _ = 1, quantum do
        Solver.step(child, 1)
        job.checked, remaining = job.checked + 1, remaining - 1
        if child.status ~= "searching" then break end
      end
      if child.status == "valid" then
        local key = Solver.resultKey(child.result, child.prepared)
        if not job.seenResults[key] then
          job.seenResults[key] = true
          job.status, job.result = "valid", child.result
          job.message = "Validated acquisition profile " .. index .. "/" .. #job.profiles .. "; exact request preserved."
          return job
        end
      end
      if child.prepared.encounter.locks then return job end
    else idle = idle + 1 end
  end
  if idle == #job.profiles then
    local incomplete = false
    for _, child in ipairs(job.profiles) do if child.status ~= "impossible" then incomplete = true end end
    for _, rejection in ipairs(job.rejectedProfiles) do if rejection.status ~= "impossible" then incomplete = true end end
    job.status = incomplete and "incomplete" or "impossible"
    job.finite, job.limit = true, job.checked
    job.message = incomplete and "All searchable profiles reached a proof/coverage boundary. Global impossibility is NOT proven."
      or "No result in any eligible implemented profile; this conclusion does not cover unimplemented acquisitions."
  end
  return job
end

function Solver.step(job, count)
  if job.status ~= "searching" then return job end
  if job.profiles then return stepProfiles(job, count) end
  if job.phase == "pid" then
    for _ = 1, count or 512 do
      if job.checked >= job.pidDomain then
        job.status = "impossible"
        job.message = "No PID satisfies these traits in the supported Poke Spot activation model; the complete PID domain was checked."
        return job
      end
      if job.checked >= job.limit then
        job.status = "exhausted"
        job.message = "Poke Spot PID budget exhausted, not impossible. Resume continues without restarting."
        return job
      end
      local found
      found, job.pidSeed = pokePIDTrial(job.prepared, job.pidSeed, job.checked, job.onlyShiny)
      job.checked = job.checked + 1
      if found then
        job.pokePidSeed, job.pidChecked = found, job.checked
        job.phase, job.checked = nil, 0
        job.anchor, job.limit = job.ivAnchor, job.ivLimit
        job.message = "Stage 2/2: PID proven; searching independent Poke Spot IV/level frames."
        return job
      end
    end
    return job
  end
  for _ = 1, count or 512 do
    if job.checked >= job.limit then
      if job.prepared.seedChoices then
        job.status = "incomplete"
        job.message = "No proven starter seed for these exact trainer IDs satisfies the request. Name-screen traversal is bounded; nothing was relaxed. Choose another OT or traits."
      elseif job.anchor and job.prepared.encounter.pokespot ~= nil then
        job.status = "incomplete"
        job.message = "All IV anchors checked for one Poke Spot PID; other PIDs were not exhausted. Global impossibility is NOT proven."
      elseif job.anchor and job.proofLimited then
        job.status = "incomplete"
        job.message = "All IV anchors checked, but encounter proofs reached a traversal limit. Impossibility is NOT proven."
      else
        job.status = (job.anchor or job.finite) and "impossible" or "exhausted"
        job.message = job.prepared.trade and "The fixed NPC trade PID/IV/ability record cannot satisfy this exact request. Nothing was relaxed."
          or job.finite and "No seed in this event's 65,536-state distribution satisfies the exact request."
          or job.anchor and "No supported acquisition frame satisfies these exact constraints (exhaustive IV anchor search)."
          or "Search budget exhausted; impossibility is NOT proven. Continue or change constraints."
      end
      return job
    end
    local seed = job.seed
    if job.prepared.seedChoices then seed = job.prepared.seedChoices[job.checked + 1]
    elseif job.finite then seed = job.checked
    elseif job.anchor then
      local state = (job.word + math.floor(job.checked / 65536) * 32768) * 65536 + job.checked % 65536
      seed = job.prepared.gamecube and Solver.gcPrevious(state) or Solver.previous(Solver.previous(Solver.previous(state)))
      if job.prepared.wildVariant == "Method H2" then seed = Solver.previous(seed) end
    else
      if job.prepared.encounter.locks then job.seed = (seed + 2654435761) % 4294967296
      else job.seed = job.prepared.gamecube and Solver.gcNext(seed) or Solver.next(seed) end
    end
    job.checked = job.checked + 1
    local frame = Solver.candidate(seed, job.prepared, job.pokePidSeed)
    if Solver.matches(frame, job.prepared) and (not job.onlyShiny or Solver.shiny(frame.pid, Solver.resultTrainer(job.prepared))) then
      local proven, reason = Solver.attachProof(frame, job.prepared)
      if proven then
        job.status, job.result = "valid", frame
        job.message = "Validated " .. Solver.encounter(frame, job.prepared).method .. " acquisition; exact request preserved."
        return job
      elseif reason == "incomplete" then job.proofLimited = true end
    end
  end
  return job
end

return Solver
