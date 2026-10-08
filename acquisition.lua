return function(version, national)
  local rows = {}
  -- Verified FireRed Pokemon Mansion land slot. A small transfer fallback keeps
  -- Ditto available even when no other game's ROM has been imported.
  rows[#rows+1]={species=132,level=30,minimum=30,maxLevel=30,location=135,
    version='firered',kind='wild land (transfer)',method='Method H1',ball=4,
    slotLow=50,slotHigh=60,slot=4,map='1:62'}
  local function add(species, level, location, kind)
    rows[#rows + 1] = { species = species, level = level, minimum = level,
      location = location, kind = kind, version = version, method = "Method 1", ball = 4 }
  end
  if version == "firered" or version == "leafgreen" then
  for _, species in ipairs({ 1, 4, 7 }) do add(species, 5, 88, "starter") end
  for _, species in ipairs({ 138, 140, 142 }) do add(species, 5, 96, "fossil") end
  add(106, 25, 98, "gift")
  add(107, 25, 98, "gift")
  add(129, 5, 104, "gift")
  add(131, 25, 134, "gift")
  add(133, 25, 94, "gift")
  add(143, 30, 112, "stationary")
  add(143, 30, 116, "stationary")
  add(101, 34, 142, "stationary")
  add(97, 30, 176, "stationary")
  add(144, 50, 139, "stationary")
  add(145, 50, 142, "stationary")
  add(146, 50, 175, "stationary")
  add(150, 70, 141, "stationary")
  if version == "firered" then
    add(63, 9, 94, "prize")
    add(35, 8, 94, "prize")
    add(123, 25, 94, "prize")
    add(147, 18, 94, "prize")
    add(137, 26, 94, "prize")
  elseif version == "leafgreen" then
    add(63, 7, 94, "prize")
    add(35, 12, 94, "prize")
    add(127, 18, 94, "prize")
    add(147, 24, 94, "prize")
    add(137, 18, 94, "prize")
  else
    return {}
  end
  end
  if version == "emerald" or version == "ruby" or version == "sapphire" then
    -- Tanoby Chambers transfer origins verified against the native FRLG import.
    -- Emerald has no native Unown encounter; preserve FireRed provenance.
    for _,u in ipairs({
      {0,25,25,0,20,188},
      {1,25,25,98,99,193},
      {2,25,25,0,20,189},
      {3,25,25,50,60,189},
      {4,25,25,98,99,190},
      {5,25,25,85,90,192},
      {6,25,25,60,70,192},
      {7,25,25,80,85,189},
      {8,25,25,90,94,190},
      {9,25,25,60,70,191},
      {10,25,25,98,99,192},
      {11,25,25,40,50,191},
      {12,25,25,90,94,193},
      {13,25,25,0,20,190},
      {14,25,25,99,100,189},
      {15,25,25,0,20,191},
      {16,25,25,94,98,191},
      {17,25,25,80,85,191},
      {18,25,25,60,70,190},
      {19,25,25,40,50,192},
      {20,25,25,94,98,189},
      {21,25,25,0,20,193},
      {22,25,25,50,60,193},
      {23,25,25,80,85,193},
      {24,25,25,0,20,192},
      {25,25,25,0,20,194},
      {26,25,25,99,100,194},
      {27,25,25,99,100,188},
    }) do
      rows[#rows+1]={species=201,level=u[2],minimum=u[2],maxLevel=u[3],form=u[1],slotLow=u[4],slotHigh=u[5],
        location=u[6],version="firered",method="Unown H1",kind="wild land (transfer)",ball=4}
    end
  end
  local function foreign(species, level, location, origin, kind)
    local internal = national and national.toSpecies and national.toSpecies[species] or species <= 251 and species
    if not internal then return end
    rows[#rows + 1] = { species = internal, level = level, minimum = level, location = location,
      kind = kind or "stationary", version = origin, method = "Method 1", ball = 4 }
  end
  for _, origin in ipairs({ "ruby", "sapphire", "emerald" }) do
    for _, species in ipairs({ 252, 255, 258 }) do foreign(species, 5, 16, origin, "starter") end
    for _, species in ipairs({ 345, 347 }) do foreign(species, 20, 10, origin, "fossil") end
    foreign(351, 25, 34, origin, "gift")
    foreign(374, 5, 13, origin, "gift")
    foreign(352, 30, 34, origin)
    foreign(100, 25, 62, origin)
    foreign(377, 40, 82, origin)
    foreign(378, 40, 81, origin)
    foreign(379, 40, 83, origin)
    foreign(384, 70, 85, origin)
  end
  for _, origin in ipairs({'ruby','sapphire'}) do
    foreign(origin=='ruby' and 381 or 380,40,16,origin,'roamer')
    rows[#rows].method='RS roamer'
    foreign(origin=='ruby' and 380 or 381,50,73,origin,'event-ticket stationary')
    rows[#rows].event=true
  end
  foreign(383, 45, 72, "ruby")
  foreign(382, 45, 72, "sapphire")
  foreign(101, 30, 66, "ruby")
  foreign(101, 30, 66, "sapphire")
  foreign(101, 30, 197, "emerald")
  foreign(382, 70, 203, "emerald")
  foreign(383, 70, 205, "emerald")
  for _, species in ipairs({ 152, 155, 158 }) do foreign(species, 5, 0, "emerald", "starter") end
  foreign(185, 40, 58, "emerald")
  for _, species in ipairs({ 380, 381 }) do foreign(species, 40, 16, "emerald", "roamer") end
  if version == "firered" or version == "leafgreen" then
  for _, species in ipairs({ 243, 244, 245 }) do
    add(species, 50, 101, "roamer")
    rows[#rows].method = "FRLG roamer"
  end
  for _, species in ipairs({ 249, 250, 386 }) do
    local internal = national and national.toSpecies[species] or species <= 251 and species
    if internal then
      add(internal, species == 386 and 30 or 70, species == 386 and 187 or 174, "event-ticket stationary")
      rows[#rows].fateful, rows[#rows].event = true, true
    end
  end
  else
    for _, species in ipairs({249,250,386,380,381}) do
      foreign(species, species==386 and 30 or (species==380 or species==381) and 50 or 70,
        (species==380 or species==381) and 73 or species==386 and 200 or 211, 'emerald', 'event-ticket stationary')
      rows[#rows].fateful,rows[#rows].event=true,true
    end
  end
  for _, event in ipairs({
    { species = 151, level = 10, name = "Aura", tid = 20078, antishiny = true, fateful = true },
    { species = 251, level = 70, name = "10 ANIV", tid = 10, antishiny = true },
    { species = 385, level = 5, name = "WISHMKR", tid = 20043 },
  }) do
    local internal = national and national.toSpecies[event.species] or event.species <= 251 and event.species
    if internal then
      rows[#rows + 1] = { species = internal, level = event.level, minimum = event.level, location = 255,
        version = "ruby", method = "Restricted event", kind = event.name .. " distribution", ball = 4,
        ot = { name = event.name, tid = event.tid, sid = 0 }, antishiny = event.antishiny,
        fateful = event.fateful, event = true }
    end
  end
  local function cube(species, level, location, origin, shadow)
    local internal = national and national.toSpecies[species] or species <= 251 and species
    if not internal then return end
    rows[#rows + 1] = { species = internal, level = level, minimum = level, location = location,
      version = origin, method = "GameCube", kind = shadow and "purified Shadow (no prior locks)" or "Mt. Battle gift",
      ball = 4, purified = shadow or false, fateful = origin == "xd", shinyLocked = origin == "xd" and shadow or false }
  end
  for _, profile in ipairs({ { 153, 30, 3 }, { 156, 30, 3 }, { 159, 30, 3 }, { 164, 30, 15 },
    { 180, 30, 15 }, { 188, 30, 15 }, { 195, 30, 15 }, { 200, 30, 15 }, { 193, 33, 25 },
    { 162, 33, 15 }, { 218, 30, 15 }, { 223, 20, 28 }, { 226, 33, 28 }, { 211, 33, 15 },
    { 307, 33, 31 }, { 206, 33, 29 }, { 333, 33, 32 }, { 237, 38, 39 }, { 185, 35, 30 },
    { 244, 40, 76 }, { 245, 40, 55 }, { 243, 40, 69 },
    { 166, 40, 47 }, { 234, 43, 58 }, { 221, 43, 58 }, { 215, 43, 58 },
    { 190, 43, 67 }, { 198, 43, 67 }, { 205, 43, 67 }, { 210, 43, 69 },
    { 329, 43, 68 }, { 168, 43, 69 }, { 192, 45, 109 }, { 225, 45, 109 },
    { 214, 45, 132 }, { 227, 47, 117 }, { 241, 48, 118 }, { 359, 48, 118 },
    { 229, 48, 118 }, { 357, 49, 118 }, { 376, 50, 118 }, { 248, 55, 118 },
    { 235, 45, 132 }, { 213, 45, 125 }, { 176, 20, 1 } }) do
    cube(profile[1], profile[2], profile[3], "colosseum", true)
  end
  for _, profile in ipairs({ { 216, 11, 143 }, { 343, 17, 11 }, { 179, 17, 11 }, { 318, 15, 8 }, { 228, 17, 11 },
    { 335, 28, 71 }, { 90, 29, 65 }, { 15, 30, 66 }, { 277, 43, 87 },
    { 249, 50, 74 }, { 112, 46, 74 }, { 175, 25, 164 } }) do
    cube(profile[1], profile[2], profile[3], "xd", true)
  end
  for _, species in ipairs({ 152, 155, 158 }) do cube(species, 5, 16, "xd", false) end
  for _, profile in ipairs({ { 133, 10, "xd", "eevee" }, { 196, 25, "colosseum", "espeon" }, { 197, 26, "colosseum", "umbreon" } }) do
    cube(profile[1], profile[2], profile[3] == "colosseum" and 254 or 0, profile[3], false)
    rows[#rows].starter, rows[#rows].kind = profile[4], "ID-correlated starter"
    rows[#rows].shinyLocked = profile[3] == "colosseum"
  end
  for _, profile in ipairs({
    { 296, 30, 5, { { 24, 0, 127 }, { 0, 1, 127 } } },
    { 207, 43, 58, { { 12, 0, 127 }, { 6, 1, 191 }, { 18, 0, 127 } } },
    { 217, 45, 132, { { 20, 1, 63 }, { 16, 0, 31 }, { 21, 1, 127 } } },
  }) do
    local internal = national and national.toSpecies[profile[1]] or profile[1] <= 251 and profile[1]
    if internal then
      cube(profile[1], profile[2], profile[3], "colosseum", true)
      rows[#rows].locks, rows[#rows].kind = profile[4], "purified Shadow (NPC team replay)"
    end
  end
  for _, profile in ipairs({
    {37,18,109,{{0,0,127},{6,1,127},{18,0,127}}},
    {363,17,11,{{24,0,63},{12,1,127}}},
    {316,17,11,{{12,1,127},{6,0,127}}},
    {273,17,11,{{6,0,127},{24,1,127},{18,1,127},{0,0,127},{12,0,127}}},
    {167,14,10,{{12,1,127},{6,0,127}}},
    {322,14,9,{{6,0,127},{0,2,255},{24,1,127}}},
    {315,22,94,{{6,0,127},{18,0,127}}},
    {301,18,8,{{6,1,191},{0,0,127},{24,0,127}}},
    {299,26,90,{{0,0,127},{18,0,127},{12,1,127}}},
    {296,18,109,{{6,0,127},{18,1,127}}},
    {355,19,110,{{12,0,127},{18,1,127},{24,0,127}}},
    {280,20,119,{{0,0,63},{6,1,127},{18,0,127}}},
    {303,22,111,{{6,0,127},{18,1,127}}},
    {361,20,97,{{6,1,127}}}, {204,20,96,{{6,0,127}}},
    {220,22,100,{{18,1,127},{0,0,127}}}, {177,22,94,{{0,0,127},{0,1,127}}},
    {285,15,8,{{24,1,191},{0,1,127}}}, {52,22,94,{{6,0,63},{0,1,127},{18,1,127}}},
    {21,22,107,{{18,0,127},{6,1,127}}}, {88,23,107,{{12,0,127},{18,0,127}}},
    {86,23,107,{{6,0,127},{18,0,127},{18,1,127}}}, {337,25,107,{{0,1,127},{18,0,127}}},
    {100,19,92,{{0,0,127},{18,0,127},{12,1,127}}},
    {58,28,64,{{24,0,127},{6,1,127},{shadow=true}}}, {46,28,64,{{24,0,127},{6,1,127}}},
    {17,30,66,{{shadow=true},{12,0,127},{18,0,31}}},
    {12,30,67,{{12,1,191},{6,0,127},{0,1,127},{shadow=true}}}, {114,30,67,{{12,1,191},{6,0,127},{0,1,127}}},
    {20,34,76,{{18,1,127},{shadow=true},{18,0,127}}}, {49,32,70,{{18,1,127},{24,0,0},{12,0,63}}},
    {70,32,70,{{18,1,127},{24,0,0},{12,0,63},{shadow=true}}}, {24,33,70,{{6,0,127},{0,1,127},{12,1,127},{18,1,127}}},
    {57,34,69,{{18,1,127},{12,1,127},{6,1,127},{24,0,127}}},
    {97,34,69,{{18,1,127},{12,1,127},{6,1,127},{24,0,127},{shadow=true}}},
    {55,33,88,{{24,0,127},{6,1,127},{18,1,127}}}, {302,33,88,{{24,0,127},{6,1,127},{18,1,127},{shadow=true}}},
    {82,30,67,{{18,2,255},{0,0,127},{12,1,127}}}, {85,34,76,{{18,1,127}}},
    {83,36,76,{{12,0,127},{0,1,127},{24,0,127}}}, {334,36,76,{{12,0,127},{0,1,127},{24,0,127},{shadow=true}}},
    {115,35,85,{{0,2,255},{18,1,127},{12,2,255}}}, {354,37,85,{{0,2,255},{18,1,127},{12,2,255},{shadow=true}}},
    {126,36,77,{{18,0,127},{18,0,191},{0,1,127}}}, {127,35,77,{{18,0,127},{18,0,191},{0,1,127},{shadow=true}}},
    {219,38,80,{{24,0,127},{6,0,127},{12,1,127},{shadow=true}}}, {78,40,80,{{24,0,127},{6,0,127},{12,1,127}}},
    {107,38,81,{{24,0,127},{6,1,127},{18,1,127}}}, {106,38,81,{{18,0,127},{12,1,127},{6,2,255},{24,1,63}}},
    {108,38,84,{{24,0,127},{6,2,255}}}, {123,40,84,{{6,1,127},{24,0,127}}},
    {113,39,84,{{6,1,127},{24,0,127},{shadow=true}}}, {338,41,87,{{24,2,255},{6,0,127},{0,1,127}}},
    {121,41,87,{{24,2,255},{6,0,127},{0,1,127},{shadow=true},{18,0,127}}},
    {125,43,87,{{shadow=true},{24,0,63},{6,1,127},{18,1,127}}},
    {143,43,87,{{shadow=true},{24,0,63},{6,1,127},{18,1,127},{shadow=true}}},
    {62,42,87,{{18,0,127},{18,0,127},{24,0,127},{6,1,127}}},
    {122,42,87,{{18,0,127},{18,0,127},{24,0,127},{6,1,127},{shadow=true}}},
    {51,40,75,{{0,0,127},{18,0,127},{6,1,127},{12,0,127}}}, {310,44,73,{{6,1,127}}},
    {373,50,73,{{6,1,127},{shadow=true}}}, {105,44,73,{{6,1,127},{shadow=true},{shadow=true},{24,0,127}}},
    {131,44,73,{{6,1,127},{shadow=true},{shadow=true},{24,0,127},{shadow=true}}},
    {145,50,74,{{shadow=true},{shadow=true},{shadow=true},{shadow=true},{shadow=true}}},
    {146,50,74,{{shadow=true}}}, {144,50,74,{{shadow=true},{shadow=true},{shadow=true},{shadow=true}}},
    {128,46,74,{{shadow=true},{shadow=true},{shadow=true}}}, {103,46,74,{{shadow=true},{shadow=true}}},
    {149,55,162,{{0,0,127},{18,0,127},{12,1,127},{12,1,127},{0,0,127}}},
    {261,10,162,{{12,1,127}}}, {165,10,153,{{0,1,127}}},
  }) do
    local internal = national and national.toSpecies[profile[1]] or profile[1] <= 251 and profile[1]
    if internal then
      cube(profile[1], profile[2], profile[3], "xd", true)
      rows[#rows].locks, rows[#rows].kind = profile[4], "purified Shadow (NPC team replay)"
    end
  end
  for _, area in ipairs({ {90,27,23,207,20,328,20}, {91,187,20,231,20,283,20}, {92,41,21,304,21,194,21} }) do
    for slot = 0, 2 do
      local species = area[2 + slot * 2]
      local internal = national and national.toSpecies[species] or species <= 251 and species
      if internal then
        cube(species, 10, area[1], "xd", false)
        rows[#rows].pokespot, rows[#rows].maxLevel = slot, area[3 + slot * 2]
        rows[#rows].kind = "Poke Spot (separate PID/IV stages)"
      end
    end
  end
  for _, profile in ipairs({
    {175,20,{{23,0,127},{8,0,127},{24,0,127},{22,1,31}}},
    {179,37,{{4,1,191},{10,1,127},{12,1,127},{16,1,127}}},
    {212,50,{{13,1,191},{2,2,255},{3,0,127},{11,0,127}}},
  }) do
    cube(profile[1], profile[2], 128, "colosseum", true)
    rows[#rows].locks, rows[#rows].ereader = profile[3], true
    rows[#rows].kind, rows[#rows].language, rows[#rows].nickname = "Japanese e-Reader purified Shadow", 1, "MON"
    rows[#rows].event = true
  end
  for _, trade in ipairs({
    { species = 311, level = 13, location = 254, version = "colosseum", name = "DUKING", tid = 37149, locked = true },
    { species = 239, level = 20, location = 164, version = "xd", name = "HORDEL", tid = 41400, nickname = "ZAPRONG" },
    { species = 307, level = 20, location = 116, version = "xd", name = "DUKING", tid = 37149 },
    { species = 213, level = 20, location = 116, version = "xd", name = "DUKING", tid = 37149 },
    { species = 246, level = 20, location = 116, version = "xd", name = "DUKING", tid = 37149 },
  }) do
    local internal = national and national.toSpecies[trade.species] or trade.species <= 251 and trade.species
    if internal then
      rows[#rows + 1] = { species = internal, level = trade.level, minimum = trade.level,
        location = trade.location, version = trade.version, method = "GameCube", kind = "NPC trade/gift",
        ball = 4, fateful = trade.version == "xd", shinyLocked = trade.locked,
        ot = { name = trade.name, tid = trade.tid, sid = 0, gender = 0 },
        playerSID = trade.version == "xd", nickname = trade.nickname }
    end
  end
  return rows
end
