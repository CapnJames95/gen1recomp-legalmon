return function(Solver, encounters)
  local Adapter = {}

  local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copy(entry) end
    return result
  end

  local function same(first, second)
    if type(first) ~= type(second) then return false end
    if type(first) ~= "table" then return first == second end
    for key, value in pairs(first) do if not same(value, second[key]) then return false end end
    for key in pairs(second) do if first[key] == nil then return false end end
    return true
  end

  function Adapter.catalog(pack, version)
    local catalog = {}
    local capeBrink = require("src.core.game3.move_learn").CAPE_BRINK
    local function add(encounter, species, minimum, visited)
      if visited[species] or species > 411 or minimum > 100 then return end
      local meta, abilities = pack.meta[species], pack.abilities[species]
      if not meta or not abilities or not pack.stats[species] or not pack.learnsets[species] then return end
      visited = copy(visited)
      visited[species] = true
      local row = catalog[species]
      if not row then
        row = { name = pack.names[species], hostVersion = version, ratio = meta.genderRatio, abilities = abilities,
          learnset = pack.learnsets[species], machines = {}, tutors = {}, encounters = {} }
        local flags = pack.tmhm.learnsets[species]
        if flags then
          for index = 0, 57 do
            local bits = index < 32 and flags.lo or flags.hi
            if math.floor((bits or 0) / 2 ^ (index % 32)) % 2 == 1 then
              local move = pack.tmhm.machines[index]
              if move then row.machines[move] = true end
            end
          end
        end
        local tutor = pack.tutor
        if tutor and tutor.format_version == 1 and type(tutor.moves) == "table" and type(tutor.learnsets) == "table" then
          local bits = tutor.learnsets[species]
          if type(bits) == "number" and bits == math.floor(bits) and bits >= 0 and bits <= (version == "emerald" and 1073741823 or 32767) then
            for index = 0, (version == "emerald" and 29 or 14) do
              local move = tutor.moves[index]
              if math.floor(bits / 2 ^ index) % 2 == 1 and type(move) == "number" and move == math.floor(move) and move >= 1 and move <= 354 then
                row.tutors[move] = true
              end
            end
          end
        end
        for _, tutor in pairs(version ~= "emerald" and capeBrink or {}) do
          if tutor.species == species and pack.move_names[tutor.move] and pack.battle_moves.moves[tutor.move] then
            row.tutors[tutor.move] = "FRLG Cape Brink tutor"
          end
        end
        catalog[species] = row
      end
      local path = copy(encounter)
      path.minimum = minimum
      row.encounters[#row.encounters + 1] = path
      for _, evolution in ipairs(pack.evolutions[species] or {}) do
        local evolved = copy(encounter)
        evolved.steps = evolved.steps or {}
        evolved.steps[#evolved.steps + 1] = { method = evolution.method, param = evolution.param, stats = copy(pack.stats[species]),
          species = species, learnset = pack.learnsets[species], machines = copy(row.machines), tutors = copy(row.tutors) }
        if evolution.method == 4 then
          add(evolved, evolution.target, math.max(minimum + 1, evolution.param), visited)
        elseif evolution.method == 7 or evolution.method == 5 or evolution.method == 6 then
          add(evolved, evolution.target, minimum, visited)
        elseif evolution.method >= 1 and evolution.method <= 3 then
          add(evolved, evolution.target, minimum + 1, visited)
        elseif evolution.method >= 8 and evolution.method <= 14 then
          add(evolved, evolution.target, math.max(minimum + 1, evolution.param), visited)
        elseif evolution.method == 15 then
          evolved.beauty = evolution.param
          add(evolved, evolution.target, minimum + 1, visited)
        end
      end
    end
    local seen, gamecube = {}, {}
    for _, source in ipairs((version == "emerald" and {"emerald","firered","leafgreen"} or {version,version == "firered" and "leafgreen" or "firered"})) do
      for _, encounter in ipairs(encounters(source, pack.national)) do
        local key = table.concat({ encounter.version, encounter.species, encounter.level, encounter.location, encounter.method, encounter.form or "", encounter.slotLow or "" }, ":")
        if not seen[key] then
          if encounter.method == "GameCube" then gamecube[#gamecube + 1] = encounter
          else add(encounter, encounter.species, encounter.level, {}) end
          seen[key] = true
        end
      end
    end
    for _, encounter in ipairs(pack.wild or {}) do add(encounter, encounter.species, encounter.level, {}) end
    local previous = {}
    for species, evolutions in pairs(pack.evolutions) do
      for _, evolution in ipairs(evolutions) do previous[evolution.target] = species end
    end
    local function parentFor(species, visited)
      if visited[species] then return nil end
      visited[species] = true
      local meta = pack.meta[species]
      if meta and meta.eggGroup1 and meta.eggGroup1 ~= 15 and meta.eggGroup1 ~= 13 then return species end
      for _, evolution in ipairs(pack.evolutions[species] or {}) do
        local parent = parentFor(evolution.target, visited)
        if parent then return parent end
      end
    end
    for national = 1, 386 do
      local species = pack.national and pack.national.toSpecies[national] or national <= 251 and national
      if species and (not previous[species] or national == 183 or national == 202) then
        local parent = parentFor(species, {})
        if parent then
          add({ species = species, level = 5, location = version == "emerald" and 0 or 88, version = version, kind = "bred and hatched",
            method = version == "emerald" and "Emerald egg" or "FRLG egg", ball = 4, parentSpecies = parent,
            split = (national == 29 or national == 314) and "low" or (national == 32 or national == 313) and "high" or nil,
            incense = national == 298 and "Sea Incense" or national == 360 and "Lax Incense" or nil }, species, 5, {})
        end
      end
    end
    for _, encounter in ipairs(gamecube) do add(encounter, encounter.species, encounter.level, {}) end
    local trades = type(pack.trades) == "table" and pack.trades.trades
    for index = 0, 8 do
      local trade = type(trades) == "table" and trades[index] or nil
      if type(trade) ~= "table" then trade = nil end
      local offered = trade and catalog[trade.requestedSpecies]
      if offered and type(trade.species) == "number" and trade.species == math.floor(trade.species) and trade.species >= 1 and trade.species <= 411
        and type(trade.ivs) == "table" and type(trade.conditions) == "table"
        and type(trade.personality) == "number" and type(trade.otId) == "number"
        and type(trade.otName) == "string" and type(trade.nickname) == "string" then
        local minimum = 101
        for _, source in ipairs(offered.encounters) do minimum = math.min(minimum, source.minimum) end
        local ivs, valid = {}, trade.personality >= 0 and trade.personality <= 4294967295 and trade.personality == math.floor(trade.personality)
          and trade.otId >= 0 and trade.otId <= 4294967295 and trade.otId == math.floor(trade.otId)
        for position = 1, 6 do
          local value = position == 6 and trade.sheen or trade.conditions[position]
          if type(value) ~= "number" or value ~= math.floor(value) or value < 0 or value > 255 then valid = false end
        end
        for position, stat in ipairs(Solver.stats) do
          local value = trade.ivs[position]
          if type(value) ~= "number" or value ~= math.floor(value) or value < 0 or value > 31 then valid = false end
          ivs[stat] = value
        end
        if valid and (trade.abilityNum == 0 or trade.abilityNum == 1) and (trade.otGender == 0 or trade.otGender == 1) then
          add({ species = trade.species, level = minimum, location = 254, version = version, kind = "fixed NPC trade",
            method = version == "emerald" and "Emerald trade" or "FRLG trade", ball = 4, nickname = trade.nickname, tradeIndex = index, requestedSpecies = trade.requestedSpecies,
            fixedPID = trade.personality, fixedIVs = ivs, fixedAbility = trade.abilityNum,
            ot = { name = trade.otName, tid = trade.otId % 65536, sid = math.floor(trade.otId / 65536), gender = trade.otGender },
            contest = { cool = trade.conditions[1], beauty = trade.conditions[2], cute = trade.conditions[3],
              smart = trade.conditions[4], tough = trade.conditions[5], sheen = trade.sheen } }, trade.species, minimum, {})
        end
      end
    end
    local breeding, directMoves = {}, {}
    local function nationalSpecies(national)
      return pack.national and pack.national.toSpecies[national] or national <= 251 and national
    end
    local function family(species)
      local visited = {}
      while previous[species] and not visited[species] do
        visited[species], species = true, previous[species]
      end
      return species
    end
    local function direct(species)
      if directMoves[species] then return directMoves[species] end
      local row, moves = catalog[species], {}
      if row then
        for _, entry in ipairs(row.learnset) do if entry[1] <= 100 then moves[entry[2]] = "Gen 3 level-up/reminder" end end
        for move in pairs(row.machines) do moves[move] = moves[move] or "Gen 3 TM/HM" end
        for move in pairs(row.tutors or {}) do moves[move] = moves[move] or "Gen 3 tutor" end
      end
      directMoves[species] = moves
      return moves
    end
    for _, row in pairs(catalog) do
      for _, encounter in ipairs(row.encounters) do
        if (encounter.method == "FRLG egg" or encounter.method == "Emerald egg") then
          local child = encounter.species
          if not breeding[child] then
            local allowed, fathers, shared, parents = {}, {}, {}, {}
            local listed = type(pack.egg_moves) == "table" and pack.egg_moves[child]
            for _, move in ipairs(type(listed) == "table" and listed or {}) do
              if type(move) == "number" and move == math.floor(move) and move >= 1 and move <= 354 then allowed[move] = true end
            end
            local motherSpecies = child == nationalSpecies(32) and nationalSpecies(29)
              or child == nationalSpecies(313) and nationalSpecies(314) or encounter.parentSpecies
            local mother = pack.meta[motherSpecies]
            for _, entry in ipairs(pack.learnsets[child] or {}) do
              if entry[1] <= 100 then shared[entry[2]] = true end
            end
            if mother then
              for species = 1, 411 do
                local father, meta = catalog[species], pack.meta[species]
                if father and meta and meta.genderRatio ~= 254 then
                  local compatible = false
                  if mother.genderRatio > 0 and mother.genderRatio < 255 and meta.genderRatio ~= 255 then
                    for _, first in ipairs({ mother.eggGroup1 or 0, mother.eggGroup2 or 0 }) do
                      for _, second in ipairs({ meta.eggGroup1 or 0, meta.eggGroup2 or 0 }) do
                        if first == second and first > 0 and first < 15 and first ~= 13 then compatible = true end
                      end
                    end
                  end
                  local ditto = catalog[132] and meta.eggGroup1 and meta.eggGroup1 > 0 and meta.eggGroup1 < 15
                    and meta.eggGroup1 ~= 13 and family(species) == family(child)
                  for _, parent in ipairs({ compatible and motherSpecies or false, ditto and 132 or false }) do
                    if parent then
                      parents[#parents + 1] = { species = species, motherSpecies = parent }
                      local known, maternal = {}, {}
                      for move, source in pairs(direct(species)) do
                        if allowed[move] then known[move] = source
                        elseif shared[move] and direct(parent)[move] then
                          known[move], maternal[move] = source, direct(parent)[move]
                        end
                      end
                      if next(known) then fathers[#fathers + 1] = { species = species, motherSpecies = parent, moves = known, motherMoves = maternal } end
                    end
                  end
                end
              end
            end
            breeding[child] = { moves = allowed, fathers = fathers, shared = shared, parents = parents }
          end
          encounter.eggMoves, encounter.eggFathers = breeding[child].moves, breeding[child].fathers
          encounter.sharedEggMoves = breeding[child].shared
          encounter.eggParents = breeding[child].parents
        end
      end
    end
    for species, row in pairs(catalog) do row.parentMoves = direct(species) end
    local smeargle = catalog[nationalSpecies(235)]
    if smeargle and smeargle.parentMoves[166] then
      local excluded = { [102] = true, [118] = true, [119] = true, [120] = true, [144] = true,
        [153] = true, [165] = true, [166] = true, [214] = true, [262] = true }
      smeargle.sketchMoves = {}
      for species = 1, 411 do
        local witness = catalog[species]
        if witness and witness ~= smeargle then
          for move, source in pairs(witness.parentMoves) do
            if not excluded[move] and not smeargle.sketchMoves[move] then
              smeargle.sketchMoves[move] = "Gen 3 Sketch from species " .. species .. " (" .. source .. ")"
            end
          end
        end
      end
    end
    return catalog
  end

  function Adapter.wildCatalog(tables, headers, version)
    local result, keys = {}, {}
    local chambers = {
      Monean = { 188, "AAAAAAAAAAA?" }, Liptoo = { 189, "CCCDDDHHHUUO" },
      Weepth = { 190, "NNNNSSSSIIEE" }, Dilford = { 191, "PPLLJJRRRQQQ" },
      Scufib = { 192, "YYTTGGGFFFKK" }, Rixy = { 193, "VVVWWWXXMMBB" },
      Viapois = { 194, "ZZZZZZZZZZZ!" },
    }
    for key in pairs(tables) do if key:match("^%d+:%d+$") then keys[#keys + 1] = key end end
    table.sort(keys)
    for _, key in ipairs(keys) do
      local header = headers[key]
      if header and type(header.id) == "string" and type(header.regionMapSectionId) == "number" and not header.id:find("AlteringCave", 1, true) then
        local modes = {
          { "land", "land", 0, 12, { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 } },
          { "water", "water", 0, 5, { 60, 30, 5, 4, 1 } },
          { "rocks", "rocks", 0, 5, { 60, 30, 5, 4, 1 } },
          { "fishing", "old rod", 0, 10, { 70, 30 } },
          { "fishing", "good rod", 2, 10, { 60, 20, 20 } },
          { "fishing", "super rod", 5, 10, { 40, 40, 15, 4, 1 } },
        }
        for _, mode in ipairs(modes) do
          local area = tables[key][mode[1]]
          local weights = mode[5]
          if area and type(area.slots) == "table" and #area.slots == mode[4] then
            local low = 0
            for index in ipairs(weights) do
              local slot = area.slots[index + mode[3]]
              local high = low + weights[index]
              local chamber = chambers[header.id:match("^SevenIsland_TanobyRuins_(%a+)Chamber$")]
              local unown = slot.species == 201 and mode[1] == "land" and chamber and chamber[1] == header.regionMapSectionId
              local form = unown and (Solver.unownLetters:find(chamber[2]:sub(index, index), 1, true) - 1) or nil
              if (slot.species ~= 201 or unown) and type(slot.species) == "number" and type(slot.minLevel) == "number" and type(slot.maxLevel) == "number"
                and slot.minLevel >= 1 and slot.maxLevel <= 100 and slot.minLevel <= slot.maxLevel then
                result[#result + 1] = { species = slot.species, level = slot.minLevel, maxLevel = slot.maxLevel,
                  minimum = slot.minLevel, location = header.regionMapSectionId, kind = "wild " .. mode[2], version = version,
                  method = unown and "Unown H1" or "Method H1", form = form, slotLow = low, slotHigh = high, slot = index, map = key,
                  activationRate = mode[1] == "rocks" and area.rate or nil,
                  ball = header.id:find("SafariZone", 1, true) and 5 or 4 }
              end
              low = high
            end
          end
        end
      end
    end
    local count = #result
    for _, method in ipairs({ "Method H2", "Method H4" }) do
      for index = 1, count do
        if result[index].method == "Method H1" then
          local variant = copy(result[index])
          variant.method = method
          result[#result + 1] = variant
        end
      end
    end
    return result
  end

  function Adapter.wildHeader(source)
    if type(source) ~= "string" or not source:match("^%s*{.*}%s*$") then return nil end
    local _, ids = source:gsub('"id"%s*:', "")
    local _, sections = source:gsub('"regionMapSectionId"%s*:', "")
    if ids ~= 1 or sections ~= 1 then return nil end
    local id = source:match('"id"%s*:%s*"([%w_]+)"%s*[,}]')
    local section = tonumber(source:match('"regionMapSectionId"%s*:%s*(%d+)%s*[,}]'))
    if not id or not section or section > 255 then return nil end
    return { id = id, regionMapSectionId = section }
  end

  function Adapter.load(session)
    if not session or (session.version ~= "firered" and session.version ~= "leafgreen" and session.version ~= "emerald") then
      return nil, "LegalMon requires a FireRed, LeafGreen or Emerald session."
    end
    local cache = require("src.core.game3.dataset").cache()
    local root = require("src.core.game3.cache_paths").CACHE_ROOT
    local source = cache:read(root .. "/meta.json")
    local Versions = require("src.import.gba.versions").forGame(session.version)
    local hash = (source or ""):match('"md5"%s*:%s*"([a-f0-9]+)"')
    local identity = hash and Versions.BY_SHA1[hash]
    if not identity then
      return nil, "Import a supported clean US FireRed, LeafGreen or Emerald ROM with this engine version first."
    end
    if identity.game ~= session.version then
      return nil, "Imported ROM edition does not match this session."
    end
    local pack = {}
    for _, key in ipairs({ "manifest", "names", "national", "stats", "meta", "abilities", "ability_names", "learnsets", "evolutions", "tmhm", "move_names", "battle_moves" }) do
      local text = cache:read(root .. "/pokemon/" .. key .. ".lua")
      local chunk = text and load(text, "@legalmon-rom-" .. key, "t", {})
      local loaded, value = false, nil
      if chunk then loaded, value = pcall(chunk) end
      if not loaded or type(value) ~= "table" then return nil, "Missing ROM data: " .. key .. ". Re-import the ROM." end
      pack[key] = value
    end
    local Extract = require("src.import.gba.pokemon_extract")
    local eggSource = cache:read(root .. "/pokemon/egg_moves.lua")
    local eggChunk = eggSource and load(eggSource, "@legalmon-rom-egg-moves", "t", {})
    if eggChunk then
      local ok, moves = pcall(eggChunk)
      if ok and type(moves) == "table" then pack.egg_moves = moves end
    end
    local tutorSource = cache:read(root .. "/pokemon/tutor.lua")
    local tutorChunk = tutorSource and load(tutorSource, "@legalmon-rom-tutor", "t", {})
    if tutorChunk then
      local ok, tutor = pcall(tutorChunk)
      if ok and type(tutor) == "table" then pack.tutor = tutor end
    end
    if pack.manifest.magic ~= Extract.MAGIC or pack.manifest.format ~= Extract.FORMAT_VERSION
      or pack.manifest.pokemonVersion ~= Versions.POKEMON_VERSION then
      return nil, "Pokemon data format is outdated. Re-import your ROM."
    end
    local wildSource = cache:read(root .. "/encounters.lua")
    local tradeSource = cache:read(root .. "/trades/ingame_trades.lua")
    local tradeChunk = tradeSource and load(tradeSource, "@legalmon-rom-trades", "t", {})
    if tradeChunk then
      local ok, trades = pcall(tradeChunk)
      if ok and type(trades) == "table" then pack.trades = trades end
    end
    local wildChunk = wildSource and load(wildSource, "@legalmon-wild", "t", {})
    local wildOk, tables = false, nil
    if wildChunk then wildOk, tables = pcall(wildChunk) end
    if wildOk and type(tables) == "table" then
      local headers = {}
      for key in pairs(tables) do
        if key:match("^%d+:%d+$") then
          local source = cache:read(root .. "/map_tree/maps/" .. key:gsub(":", "_") .. "/header.json")
          headers[key] = Adapter.wildHeader(source)
        end
      end
      pack.wild = Adapter.wildCatalog(tables, headers, session.version)
    end
    return pack
  end

  function Adapter.trainer(session)
    return { tid = session.trainerId, sid = session.secretId, name = session.name,
      gender = require("src.core.game3.party").otGender(session) }
  end

  function Adapter.buildMon(job, session, pack)
    if job.status ~= "valid" or not Solver.verify(job.result, job.prepared) then
      return nil, "Validation failed; nothing was generated."
    end
    local prepared, frame = job.prepared, job.result
    local encounter = Solver.encounter(frame, prepared)
    if not same(prepared.trainer, Adapter.trainer(session)) or prepared.row.hostVersion ~= session.version then
      return nil, "Trainer or game changed; validate again."
    end
    local Pokemon = require("src.core.game3.pokemon")
    local species, pid = prepared.species, frame.pid
    if not same(Pokemon.stats(species), pack.stats[species])
      or not same(Pokemon.speciesMeta(species), pack.meta[species])
      or not same(Pokemon.abilities(species), pack.abilities[species]) then
      return nil, "Another mod changed species data; vanilla legality cannot be guaranteed."
    end
    local abilityNum = Solver.abilitySlot(frame, prepared)
    local ability = pack.abilities[species][abilityNum + 1]
    local meta = pack.meta[species]
    local mon = {
      species = species, speciesId = species, speciesNumbering = "internal",
      name = pack.names[species], nickname = encounter.nickname or "", language = encounter.language or 2,
      level = prepared.level, growthRate = meta.growthRate,
      exp = require("src.core.game3.summary_data").expForLevel(meta.growthRate, prepared.level),
      personality = pid, nature = pid % 25, ivs = copy(frame.ivs),
      evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
      abilityNum = abilityNum, ability = ability, abilityId = ability,
      gender = Solver.gender(pid, meta.genderRatio),
      friendship = meta.friendship, happiness = meta.friendship,
      ot = session.name, otName = session.name, otId = session.trainerId, otSecretId = session.secretId,
      otGender = require("src.core.game3.party").otGender(session),
      metGame = ({ sapphire = 1, ruby = 2, emerald = 3, firered = 4, leafgreen = 5, colosseum = 15, xd = 15 })[encounter.version],
      metLevel = frame.metLevel or encounter.level, metLocation = encounter.location, pokeball = encounter.ball,
      moves = copy(prepared.moves), pp = {}, maxPp = {}, pokerus = 0,
      cartExtra = { contest = copy(encounter.contest) or { beauty = encounter.beauty or 0, sheen = encounter.beauty and 255 or 0 }, modernFatefulEncounter = encounter.fateful or false },
      fatefulEncounter = encounter.fateful or false,
      legalmon = { version = 3, method = encounter.method, seed = frame.seed, originSeed = frame.originSeed, sourceSpecies = encounter.species,
        pendingSeed = frame.pendingSeed, vblankSeed = frame.vblankSeed, inherited = copy(frame.inherited), parents = copy(frame.parents) },
    }
    for _, source in ipairs(prepared.sources) do
      if source == "FRLG Cape Brink tutor" then mon.friendship, mon.happiness = 255, 255 end
    end
    if prepared.customOT then
      mon.ot, mon.otName, mon.otId, mon.otSecretId = prepared.customOT.name, prepared.customOT.name, prepared.customOT.tid, prepared.customOT.sid
      mon.otGender = prepared.customOT.gender
    end
    if prepared.gamecube then
      mon.cartExtra.ribbons = (encounter.purified and 16777216 or 0) + (encounter.fateful and 2147483648 or 0)
      mon.legalmon.sourceGame = encounter.version
      mon.legalmon.teamSeed = frame.teamSeed
      mon.legalmon.ivSeed, mon.legalmon.pokePidSeed = frame.ivSeed, frame.pokePidSeed
      mon.legalmon.activationSeed, mon.legalmon.animationSeed = frame.activationSeed, frame.animationSeed
    end
    if encounter.ot then
      local original = Solver.resultTrainer(prepared)
      mon.ot, mon.otName, mon.otId, mon.otSecretId = original.name, original.name, original.tid, original.sid
      mon.otGender = frame.otGender
    end
    if type(mon.otName) ~= "string" or #mon.otName < 1 or #mon.otName > 7 or mon.otName:find("[^A-Za-z0-9 .,!?'%-]") then
      return nil, "MVP requires an English trainer name of 1-7 supported characters."
    end
    for index, move in ipairs(mon.moves) do
      local data = pack.battle_moves.moves[move]
      if not data or not data.pp or data.pp <= 0 or Pokemon.movePp(move) ~= data.pp then
        return nil, "Missing or modified move PP; nothing was generated."
      end
      mon.pp[index], mon.maxPp[index] = data.pp, data.pp
    end
    Pokemon.applyStats(mon)
    mon.hp = mon.maxHp
    return mon
  end

  function Adapter.deliver(job, request, session, pack, destination, targetBox)
  if session and session.version=="emerald" and session.frontier and (session.frontier.challengeStatus or 0)~=0 then return false,"Finish the Battle Frontier challenge before receiving Pokemon." end
    if job.consumed then return false, "Already delivered. Validate again for another Pokemon." end
    if destination ~= "party" and destination ~= "pc" then return false, "Choose party or PC." end
    local prepared, err = Solver.prepare(request, Adapter.catalog(pack, session.version), Adapter.trainer(session), job.prepared and job.prepared.profileIndex)
    if not prepared then return false, err.message end
    if not same(prepared, job.prepared) then return false, "Configuration changed; validate again." end
    local mon, message = Adapter.buildMon(job, session, pack)
    if not mon then return false, message end
    local slot
    if destination == "party" then
      if type(session.party) ~= "table" or #session.party >= 6 then return false, "Party is full; select PC explicitly." end
      session.party[#session.party + 1] = mon
      slot = "party slot " .. #session.party
    else
      local Storage = require("src.core.game3.storage")
      if targetBox ~= nil and (type(targetBox) ~= "number" or targetBox ~= math.floor(targetBox) or targetBox < 1 or targetBox > 14) then
        return false, "Invalid PC box; nothing was delivered."
      end
      if targetBox and Storage.countBoxMons(session.storage, targetBox) >= 30 then return false, "Selected box is full; nothing was delivered." end
      if session.storage and not Storage.findOpenSlot(session.storage) then return false, "PC is full; nothing was delivered." end
      local storage = Storage.ensure(session)
      local previousBox = storage.currentBox
      if targetBox then storage.currentBox = targetBox end
      local sent, box, position = Storage.sendMonToPC(session, mon)
      storage.currentBox = previousBox
      if not sent then return false, "PC is full; nothing was delivered." end
      slot = "box " .. box .. ", slot " .. position
    end
    session.dex = session.dex or {}
    for _, key in ipairs({ "seen", "owned", "caught" }) do
      session.dex[key] = session.dex[key] or {}
      session.dex[key][mon.species] = true
    end
    job.consumed = true
    return true, "Delivered to " .. slot .. ". Save normally to keep it.", mon
  end

  function Adapter.explain(job)
    local lines = { job.message or job.status }
    if job.checked then lines[#lines + 1] = (job.profiles and "Combined search work units: " or "Search candidates checked: ") .. job.checked end
    if job.profiles then
      lines[#lines + 1] = "Acquisition profiles: " .. #job.profiles .. " searchable; " .. #job.rejectedProfiles .. " rejected. Search covers implemented profiles only."
      local child = job.profiles[job.activeProfile or 1]
      lines[#lines + 1] = "Selected catalog profile: " .. child.prepared.profileIndex .. "; child state: " .. child.status .. "; checked: " .. child.checked
      if child.pidDomain then lines[#lines + 1] = "Poke Spot PID trials: " .. (child.pidChecked or child.checked) .. "/" .. child.pidDomain end
      for _, rejection in ipairs(job.rejectedProfiles) do
        lines[#lines + 1] = "Profile " .. rejection.index .. " (" .. rejection.status .. "): " .. rejection.message
      end
    end
    if not job.result then return lines end
    local prepared, frame = job.prepared, job.result
    local encounter = Solver.encounter(frame, prepared)
    lines[#lines + 1] = prepared.trade and string.format("Fixed record PID %08X (no RNG search)", frame.pid) or string.format("Seed %08X; PID %08X", frame.seed, frame.pid)
    lines[#lines + 1] = encounter.method
    lines[#lines + 1] = string.format("%s %s species %d", encounter.version, encounter.kind, encounter.species)
    if prepared.unown then lines[#lines + 1] = "Unown form: " .. Solver.unownLetters:sub(Solver.unownForm(frame.pid) + 1, Solver.unownForm(frame.pid) + 1) end
    if prepared.trade then lines[#lines + 1] = "Fixed imported NPC trade record; no RNG seed claim. Offered species " .. encounter.requestedSpecies .. " has a supported acquisition at Lv." .. encounter.level .. ". No offered Pokemon is consumed; held items/mail are omitted." end
    for _, stage in ipairs(prepared.moveHistory or {}) do
      lines[#lines + 1] = "Move-history stage: species " .. stage.species .. " by Lv." .. stage.sourceLevel .. "; learn level-up moves through Lv." .. stage.teachingLevel .. " before evolving at Lv." .. stage.evolutionLevel .. " (method " .. stage.method .. "). Earlier TM/tutor teaching occurs before evolution."
    end
    for _, source in ipairs(prepared.sources) do
      if source == "FRLG Cape Brink tutor" then
        lines[#lines + 1] = "Cape Brink tutor: compatible fully evolved Kanto starter; generated friendship is 255. Tutor flags are not consumed."
        break
      end
    end
    lines[#lines + 1] = string.format("Met location %d; met level %d; ball %d", encounter.location, frame.metLevel or encounter.level, encounter.ball)
    if frame.originSeed then lines[#lines + 1] = string.format("Wild start %08X; map %s; slot %d; rejected PID pairs %d", frame.originSeed, encounter.map, encounter.slot, frame.rejectedPids) end
    if frame.pendingSeed then
      lines[#lines + 1] = string.format("Egg pending seed %08X; collection seed %08X; three inherited IVs.", frame.pendingSeed, frame.seed)
      lines[#lines + 1] = prepared.eggMoveFather and ("Compatible hypothetical mother slot: species " .. prepared.eggMoveFather.motherSpecies .. "; father slot: species " .. prepared.eggMoveFather.species .. ", with different OTs. Parents are not consumed.")
        or "Compatible hypothetical parents: species " .. encounter.parentSpecies .. " and Ditto with different original trainers. Parents are not consumed."
      if prepared.eggMoveFather then
        for _, move in ipairs(prepared.eggInheritedMoves) do
          lines[#lines + 1] = "Father supplies egg move " .. move .. " via " .. prepared.eggMoveFather.moves[move] .. "; all inherited moves fit one father's four slots."
          if prepared.eggMoveFather.motherMoves[move] then
            lines[#lines + 1] = "Shared level-up inheritance: mother also supplies move " .. move .. " via " .. prepared.eggMoveFather.motherMoves[move] .. "."
          end
        end
        local visited = {}
        local function describe(proof, depth)
          if not proof or visited[proof] then return end
          visited[proof] = true
          local moves = {}
          for move in pairs(proof.moves) do moves[#moves + 1] = move end
          table.sort(moves)
          for _, move in ipairs(moves) do
            lines[#lines + 1] = "Parent-chain depth " .. depth .. ": species " .. proof.species .. ", move " .. move .. " via " .. proof.moves[move] .. "."
          end
          for _, stage in ipairs(proof.history or {}) do
            lines[#lines + 1] = "Parent has species " .. stage.species .. " by Lv." .. stage.sourceLevel .. ", learns level-up moves through Lv." .. stage.teachingLevel .. ", then evolves at Lv." .. stage.evolutionLevel .. "."
          end
          if proof.parents then
            describe(proof.parents.fatherProof, depth + 1)
            describe(proof.parents.motherProof, depth + 1)
          end
        end
        describe(prepared.eggMoveFather.fatherProof, 1)
        describe(prepared.eggMoveFather.motherProof, 1)
      end
      if encounter.incense then lines[#lines + 1] = "Parent holds " .. encounter.incense .. "." end
      for index, stat in ipairs(frame.inherited) do lines[#lines + 1] = "Parent " .. frame.parents[index] .. " supplies " .. stat .. "=" .. frame.ivs[stat] end
      lines[#lines + 1] = "Other IVs come from the collection RNG. Assumes these parental IVs were obtained through legitimate breeding/import; parent PID/IV ancestry is not reconstructed."
    end
    if encounter.event then lines[#lines + 1] = "EVENT origin: requires historical distribution/ticket rules, not a normal wild acquisition." end
    if encounter.ot then lines[#lines + 1] = "Fixed NPC/event OT " .. encounter.ot.name .. "; gender " .. frame.otGender .. "; never replaced with the player's OT." end
    if encounter.playerSID then lines[#lines + 1] = "XD trade: NPC name/TID, with the receiving trainer's SID. This is not a purified Shadow encounter." end
    if encounter.nickname then lines[#lines + 1] = "Acquisition nickname: " .. encounter.nickname end
    lines[#lines + 1] = string.format("Nature %d; gender %s; shiny %s", frame.pid % 25,
      Solver.gender(frame.pid, prepared.row.ratio), tostring(Solver.shiny(frame.pid, Solver.resultTrainer(prepared))))
    if prepared.gamecube then lines[#lines + 1] = "GameCube RNG; ability roll " .. frame.gcAbility .. "; PID rolls " .. frame.pidRolls .. "; purified " .. tostring(encounter.purified) .. "; fateful " .. tostring(encounter.fateful) end
    if frame.teamSeed then lines[#lines + 1] = string.format("NPC team start %08X; %d PID pairs including rejection rerolls. NPC traits and CPU/player anti-shiny checks replayed. Target IV seed %s.", frame.teamSeed, frame.teamRolls, frame.ivSeed and string.format("%08X", frame.ivSeed) or "fixed zero (e-Reader)") end
    if frame.pokePidSeed then lines[#lines + 1] = string.format("Poke Spot PID seed %08X; activation %08X; IV seed %08X; animation %08X. PID and collection IV/level stages are independent.", frame.pokePidSeed, frame.activationSeed, frame.seed, frame.animationSeed) end
    if encounter.ereader then lines[#lines + 1] = "Japanese e-Reader acquisition: fixed zero IVs, locked nature/gender, National Ribbon, Latin nickname MON. No Japanese ROM assets are bundled." end
    if prepared.seedChoices then lines[#lines + 1] = "Starter PID/IV seed derived from exact OT IDs and startup sequence; " .. #prepared.seedChoices .. " supported seed choices. Colosseum Espeon includes preceding Umbreon generation. Naming ball-spawn branches are checked with a bounded traversal." end
    local slot = Solver.abilitySlot(frame, prepared)
    lines[#lines + 1] = "Ability " .. prepared.row.abilities[slot + 1] .. "; slot " .. (slot + 1)
    local trainer = Solver.resultTrainer(prepared)
    if prepared.otSeed then lines[#lines + 1] = string.format("Trainer-ID RNG proof seed %08X", prepared.otSeed) end
    lines[#lines + 1] = "Original trainer ID " .. trainer.tid .. "; secret ID " .. trainer.sid
    local values = {}
    for _, stat in ipairs(Solver.stats) do values[#values + 1] = stat .. "=" .. frame.ivs[stat] end
    lines[#lines + 1] = table.concat(values, " ")
    local hiddenType, power = Solver.hiddenPower(frame.ivs)
    lines[#lines + 1] = "Hidden Power: " .. Solver.hiddenTypes[hiddenType] .. " / " .. power
    for index, move in ipairs(prepared.moves) do
      lines[#lines + 1] = "Move " .. move .. ": " .. prepared.sources[index]
    end
    lines[#lines + 1] = "Host: " .. prepared.row.hostVersion .. "; source: " .. encounter.version
    lines[#lines + 1] = "Scope: implemented acquisition method; Gen 3 level-up/reminder, proven pre-evolution histories, bounded parent move chains and witnessed Sketch, final-species TM/HM and supported tutors from the active host game after any transfer."
    lines[#lines + 1] = "Generated provenance, not proof of an actual capture."
    return lines
  end

  return Adapter
end
