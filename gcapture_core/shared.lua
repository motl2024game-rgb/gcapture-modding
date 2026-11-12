GCapture = GCapture or {}
local GC = GCapture

GCW, GCH = 32, 32
GCN = GCW * GCH
GCIB = 1
GC.SizeList = { [0] = 16, [1] = 32, [2] = 64, [3] = 128 }

GC.BuildBits, GC.ActBits = 6, 8

function GC.SetSize(w, h)
    h = h or w
    GCW, GCH = w, h
    GCN = GCW * GCH
    GCIB = 1
    while 2 ^ GCIB < GCN do GCIB = GCIB + 1 end
    GC.W, GC.H, GC.N, GC.IB = GCW, GCH, GCN, GCIB
    if GC.RebuildNB then GC.RebuildNB() end
end
GC.SetSize(32)

function GC.XY(i) return (i - 1) % GCW, math.floor((i - 1) / GCW) end
local XY = GC.XY

GC.PLAINS, GC.FOREST, GC.DESERT, GC.TUNDRA, GC.WATER = 1, 2, 3, 4, 5

GC.Biomes = {
    [0] = { name = "Unknown", color = Color(8, 10, 16), coin = 0, pop = 0 },
    [1] = { name = "Plains", color = Color(96, 184, 72),   coin = 0.3,   pop = 1 },
    [2] = { name = "Forest", color = Color(24, 96, 44),    coin = 0.4,   pop = 0.5 },
    [3] = { name = "Desert", color = Color(226, 200, 100), coin = 0.4, pop = 0.4 },
    [4] = { name = "Tundra", color = Color(196, 214, 224), coin = 0.3, pop = 0.5 },
    [5] = { name = "Water",  color = Color(16, 36, 110),   coin = 0,   pop = 0, water = true },
}

GC.BiomeSpawnChance = { [1] = 0.9, [2] = 0.85, [3] = 0.65, [4] = 0.55 }

GC.Build = {
    [1]  = { name = "Capital",     icon = "gcapture/gc_capital.png" },
    [2]  = { name = "Village",     icon = "gcapture/gc_village.png", coin = 2 },
    [3]  = { name = "Weaponry",    icon = "gcapture/gc_weaponry.png", weapon = 1 },
    [4]  = { name = "Fortress",   icon = "gcapture/gc_fortress.png" },
    [5]  = { name = "Oil Rig",     icon = "gcapture/gc_oilrig.png", coin = 30, lifetime = 15 },
    [6]  = { name = "Coast Guard", icon = "gcapture/gc_coastguard.png" },
    [7]  = { name = "Trap",        icon = "gcapture/gc_trap.png" },
    [8]  = { name = "Airbase",     icon = "gcapture/gc_airbase.png" },
    [9]  = { name = "Chest",       icon = "gcapture/gc_chest.png" },
    [10] = { name = "Fire",        icon = "gcapture/gc_fire.png" },
    [11] = { name = "Army Center", icon = "gcapture/gc_army_center.png" },
    [12] = { name = "Cavalry Center", icon = "gcapture/gc_cav_center.png" },
    [13] = { name = "Crater", icon = "gcapture/gc_crater.png" },
}
GC.B_CAPITAL, GC.B_VILLAGE, GC.B_WEAPONRY, GC.B_BARRICADE, GC.B_OIL, GC.B_COAST, GC.B_TRAP = 1, 2, 3, 4, 5, 6, 7
GC.B_AIR, GC.B_CHEST, GC.B_FIRE = 8, 9, 10
GC.B_ARMYC, GC.B_CAVC = 11, 12
GC.B_CRATER = 13

GC.ShipIcon = "gcapture/gc_ship.png"
GC.ArmyIcon = "gcapture/gc_army.png"
GC.CavIcon = "gcapture/gc_cavalry.png"

GC.Actions = {
    [1]  = { name = "Expand",         coins = 10,  pop = 10, icon = "gcapture/gc_act_green.png" },
    [2]  = { name = "Build Village",  coins = 200, build = 2, icon = "gcapture/gc_act_brown.png" },
    [3]  = { name = "Build Weaponry", coins = 300, build = 3, icon = "gcapture/gc_act_brown.png" },

    [5]  = { name = "Build Fortress",      coins = 150, build = 4, icon = "gcapture/gc_act_brown.png" },
    [6]  = { name = "Build Oil Rig",  coins = 450, pop = 50, build = 5, biome = 3, icon = "gcapture/gc_act_brown.png" },
    [7]  = { name = "Build Coast Guard", coins = 150, weapons = 20, build = 6, coast = true, icon = "gcapture/gc_act_brown.png" },
    [8]  = { name = "Trap",           coins = 250, build = 7, icon = "gcapture/gc_act_brown.png" },

    [9]  = { name = "Build Ship",     coins = 100, pop = 30, water = true, icon = "gcapture/gc_act_blue.png" },
    [10] = { name = "Disassemble", water = true, refund = { coins = 90, pop = 5 }, icon = "gcapture/gc_act_black.png" },
    [11] = { name = "Sail",           water = true, icon = "gcapture/gc_act_green.png" },
    [12] = { name = "Sink",           weapons = 25, water = true, icon = "gcapture/gc_act_red.png" },

    [13] = { name = "Recruit Army",   weapons = 60, pop = 60, icon = "gcapture/gc_act_green.png" },
    [14] = { name = "Move",           any = true, icon = "gcapture/gc_act_green.png" },
    [15] = { name = "Attack",         any = true, icon = "gcapture/gc_act_red.png" },
    [16] = { name = "Stop Attack",    any = true, icon = "gcapture/gc_act_red.png" },
    [17] = { name = "Retreat",        any = true, icon = "gcapture/gc_act_black.png" },
    [18] = { name = "Disembark",      any = true, icon = "gcapture/gc_act_red.png" },

    [19] = { name = "Build Airbase",  coins = 700, weapons = 50, build = 8, icon = "gcapture/gc_act_brown.png" },
    [20] = { name = "Bombard",        weapons = 1000, icon = "gcapture/gc_act_red.png" },
    [21] = { name = "Open",           coins = 300, icon = "gcapture/gc_act_purple.png" },
    [22] = { name = "Go To Border",   any = true, icon = "gcapture/gc_act_green.png" },
    [23] = { name = "Stop",           any = true, icon = "gcapture/gc_act_green.png" },
    [24] = { name = "Delete Army",    any = true, icon = "gcapture/gc_act_black.png" },
    [25] = { name = "Delete Structure", icon = "gcapture/gc_act_black.png" },
    [26] = { name = "Build Army Center", coins = 350, build = 11, icon = "gcapture/gc_act_brown.png" },
    [27] = { name = "Build Cavalry Center", coins = 450, build = 12, icon = "gcapture/gc_act_brown.png" },
    [28] = { name = "Recruit Cavalry", weapons = 120, pop = 60, icon = "gcapture/gc_act_green.png" },
    [29] = { name = "Upgrade Fortress", icon = "gcapture/gc_act_purple.png" },
    [30] = { name = "Auto Attack", any = true, icon = "gcapture/gc_act_red.png" },
    [31] = { name = "Ship Order", water = true },
}

GC.DeployTime = 10
GC.MaxBots = 40
GC.StartResources = { coins = 30, pop = 30, weapons = 0 }
GC.CoinLimit = 1000
GC.PopPerCell = 300
GC.SupplyRadius = 3
GC.WinsForChoice = 5
GC.ChoiceInterval = 420
GC.BuildSound = "gcapture/gc_build.wav"
GC.TrapPenalty = 50
GC.ExpandTime = 3
GC.ExpandMax = 100
GC.CoastRadius = 4
GC.FogRadius = 3
GC.AirRadius = 5
GC.AirbaseMinDay = 4
function GC.AirbaseUnlocked() return GC.CycleNow() >= (GC.AirbaseMinDay - 1) * GC.CycleLen end
GC.AirCooldown = 30
GC.FireTime = 8
GC.BombDamage = 5
GC.BombHP = { 2, 3 }
GC.BombOrg = { 1, 3 }
GC.CapitalBombPenalty = 10
GC.PactTime = 60
GC.DiscontentPer = 0.3
GC.DiscontentTime = 60
GC.BotAccessTime = 180
GC.LetterMax = 100
GC.ChoiceTime = 30
GC.NameMax = 25
function GC.CutName(s)
    s = string.gsub(tostring(s or ""), "%c", "")
    local len = utf8.len(s)
    if not len then return string.sub(s, 1, GC.NameMax) end
    if len > GC.NameMax then s = string.sub(s, 1, utf8.offset(s, GC.NameMax + 1) - 1) end
    return s
end
function GC.TrimName(s) return string.Trim(GC.CutName(s)) end
function GC.DefaultName(ply)
    return GC.TrimName((IsValid(ply) and ply:Nick() or "Player") .. "'s Kingdom")
end
GC.BarricadeMaxLevel = 3
GC.BarricadeUpgrade = { 50, 60 }

GC.Combat = {
    MaxOrg = 10,
    MaxHP = 10,
    MoveCooldown = 1,
    CaptureDelay = 2,
    AttackChance = 0.50,
    DefenseChance = 0.55,
    TrainTime = 15,
    BorderStep = 0.6,
    BorderOrgCost = 1,
    UpkeepCoins = 15,
    CavUpkeepCoins = 30,
    CavHP = -5,
    CavOrg = 5,
    CavAttack = 0.10,
    CavDefense = -0.15,
    CavMove = 0.5,
    UpkeepInterval = 20,
    DesertMoveMult = 2,
    TundraAttack = -0.15,
    TundraDefense = -0.10,
}

GC.DayLen, GC.DayTrans = 180, 40
GC.CycleLen = 2 * (GC.DayLen + GC.DayTrans)
function GC.NightAmount(t)
    t = t % GC.CycleLen
    local D, T = GC.DayLen, GC.DayTrans
    local k
    if t < D then return 0
    elseif t < D + T then k = (t - D) / T
    elseif t < 2 * D + T then return 1
    else k = 1 - (t - (2 * D + T)) / T end
    return k * k * (3 - 2 * k)
end
GC.NightAttackPenalty = 0.03
function GC.NightAtk()

    if (SERVER and GC.Opts and GC.Opts.nonight) or (CLIENT and GC.noNight) then return 0 end
    return -GC.NightAttackPenalty * GC.NightAmount(GC.CycleNow())
end

GC.OptFlags = { "nochests", "nospirits", "novillages", "noplains", "noforest", "notundra", "nodesert", "noocean", "nonight", "nopresets" }
GC.OptBiomeFlag = { [1] = "noplains", [2] = "noforest", [3] = "nodesert", [4] = "notundra", [5] = "noocean" }

GC.ST_IDLE, GC.ST_ATTACK, GC.ST_DEFENSE, GC.ST_BORDER = 0, 1, 2, 3

GC.army = {}

GC.pacts = GC.pacts or {}
GC.access = GC.access or {}
GC.muted = GC.muted or {}
GC.blevel = GC.blevel or {}
GC.oilUsed = GC.oilUsed or {}
function GC.PactKey(a, b)
    if a > b then a, b = b, a end
    return a * 256 + b
end
function GC.HasPact(a, b)
    if not a or not b or a == 0 or b == 0 or a == b then return false end
    local t = GC.pacts[GC.PactKey(a, b)]
    return t ~= nil and CurTime() < t
end

GC.ModOrder = { "coins", "pop", "weapons", "oilCoin", "oilLife", "coastRange", "org", "hp", "attack", "defense", "fog", "airRange", "train", "upkeep",
    "cavAttack", "cavDefense", "cavMove", "cavHp", "cavOrg", "cavTrain", "cavUpkeep" }
GC.ModInfo = {
    coins      = { label = "Coins per second" },
    pop        = { label = "Population per second" },
    weapons    = { label = "Weapons per second" },
    oilCoin    = { label = "Oil Rig income" },
    oilLife    = { label = "Oil Rig lifetime", unit = " sec" },
    coastRange = { label = "Coast Guard range", pct = true },
    org        = { label = "Army Org. limit" },
    hp         = { label = "Army HP limit" },
    attack     = { label = "Army Attack Chance", pct = true },
    defense    = { label = "Army Defense Chance", pct = true },
    fog        = { label = "Fog of war range", unit = " cells" },
    airRange   = { label = "Airbase range", unit = " cells" },
    train      = { label = "Army training time", unit = " sec" },
    upkeep     = { label = "Army upkeep", pct = true },
    cavAttack  = { label = "Cavalry Attack Chance", pct = true },
    cavDefense = { label = "Cavalry Defense Chance", pct = true },
    cavMove    = { label = "Cavalry move cooldown", pct = true },
    cavHp      = { label = "Cavalry HP limit" },
    cavOrg     = { label = "Cavalry Org. limit" },
    cavTrain   = { label = "Cavalry training time", unit = " sec" },
    cavUpkeep  = { label = "Cavalry upkeep", pct = true },
}

GC.BiomeModOrder = { "attack", "defense", "move", "cavAttack", "cavDefense", "cavMove" }
GC.BiomeModInfo = {
    attack  = { label = "Army Attack Chance" },
    defense = { label = "Army Defense Chance" },
    move    = { label = "Army move cooldown" },
    cavAttack  = { label = "Cavalry Attack Chance" },
    cavDefense = { label = "Cavalry Defense Chance" },
    cavMove    = { label = "Cavalry move cooldown" },
}

GC.SpiritOrder = { "offensive", "hate", "war", "oil", "ironwall", "goldrush", "baby", "eagle", "sky", "sea", "blackgold", "drill", "glass",
    "peoples", "hawks", "fortress", "scouts", "industry", "blitz", "laststand", "veterans", "baron", "mercs", "mobil", "hardy",
    "bastion", "radar", "arsenal", "harbor", "refinery", "fanatics", "diplomat",
    "lean", "conscript", "quarter", "trade", "quarry", "elite", "militia", "airdoc", "smuggler", "prophets", "wildcat",
    "genius", "hunters", "barracks", "legends", "martyrs", "scorched", "golden", "carto", "nostepback", "legrishand", "everypatriot",
    "horselords", "steelhorse", "hussars", "stable", "endless", "lancers", "heavycav", "raiders", "horde", "cavdoc", "breeders", "dragoons",
    "plainshorse", "woodriders", "desertriders",
    "rangers", "nomads", "arctic", "cavalry", "ambush", "dunes", "frost", "openfield", "jungle", "sandwalk", "icewolves", "steppe" }
GC.SpiritDefs = {
    offensive = { name = "Offensive Army",   mods = { attack = 0.05 } },
    hate      = { name = "Hate", target = true, vs = { attack = 0.05 } },
    war       = { name = "War Spirit",       mods = { weapons = 1.5, org = 2, train = -3 } },
    oil       = { name = "Oil Man",         mods = { oilLife = 5 } },
    ironwall  = { name = "Iron Wall",        mods = { defense = 0.15, hp = 3 } },
    goldrush  = { name = "Gold Rush",        mods = { coins = 1 } },
    baby      = { name = "Chinese People",        mods = { pop = 5 } },
    eagle     = { name = "Eagle Eye",        mods = { fog = 2 } },
    sky       = { name = "Sky Dominion",     mods = { airRange = 2 } },
    sea       = { name = "Sea Wolf",         mods = { coastRange = 0.5 } },
    blackgold = { name = "Black Gold",       mods = { oilCoin = 3, oilLife = -3 } },
    drill     = { name = "Drill Sergeant",   mods = { train = -5, org = -1 } },
    glass     = { name = "Glass Cannon",     mods = { attack = 0.10, hp = -2 } },
    peoples   = { name = "People's Army",    mods = { pop = 3, org = 1 } },
    hawks     = { name = "Sky Hawks",        mods = { airRange = 3, weapons = -0.5 } },
    fortress  = { name = "Coastal Fortress", mods = { coastRange = 0.75, defense = 0.03 } },
    scouts    = { name = "Scouts",           mods = { fog = 3, train = 2 } },
    industry  = { name = "Industrial Might", mods = { weapons = 2, coins = 1 } },
    blitz     = { name = "Blitzkrieg",       mods = { attack = 0.20, defense = -0.10 } },
    laststand = { name = "Last Stand",       mods = { defense = 0.10, attack = -0.05 } },
    veterans  = { name = "Veteran Corps",    mods = { org = 3, train = 3 } },
    baron     = { name = "Oil Baron",        mods = { oilCoin = 2, oilLife = 3 } },
    mercs     = { name = "Mercenary Pact",   mods = { coins = 2, pop = -5 } },
    mobil     = { name = "Rapid Mobilization", mods = { train = -7, hp = -1 } },
    hardy     = { name = "Hardy People",     mods = { pop = 3.5, coins = -0.5 } },
    bastion   = { name = "Bastion",          mods = { defense = 0.08, fog = -1 } },
    radar     = { name = "Radar Network",    mods = { fog = 10, airRange = 6, coins = -0.5 } },
    arsenal   = { name = "Arsenal",          mods = { weapons = 2, pop = -1.5 } },
    harbor    = { name = "Harbor Masters",   mods = { coastRange = 0.35, coins = 0.5 } },
    refinery  = { name = "Refinery Complex", mods = { oilCoin = 4, oilLife = -4 } },
    fanatics  = { name = "Fanatics",         mods = { attack = 0.07, org = 1, hp = -1 } },
    diplomat  = { name = "Silver Tongue",    mods = { coins = 1.5, defense = -0.03 } },
    lean      = { name = "Lean Logistics",   mods = { upkeep = -0.3, org = -1 } },
    conscript = { name = "Mass Conscription", mods = { pop = 5, train = -3, upkeep = 0.25 } },
    quarter   = { name = "Quartermasters",   mods = { upkeep = -0.2, weapons = 0.5 } },
    trade     = { name = "Trade Winds",      mods = { coins = 1, defense = -0.02 } },
    quarry    = { name = "Quarry Workers",   mods = { weapons = 0.5, coins = 0.5, pop = -3.5 } },
    elite     = { name = "Elite Guard",      mods = { hp = 2, org = 2, upkeep = 0.4 } },
    militia   = { name = "Militia",          mods = { org = -1, upkeep = -0.35, pop = 3.5 } },
    airdoc    = { name = "Air Doctrine",     mods = { airRange = 4, coins = -0.7 } },
    smuggler  = { name = "Smugglers",        mods = { coins = 2.5, fog = -2 } },
    prophets  = { name = "Oil Prophets",     mods = { oilLife = 8, oilCoin = -1 } },
    wildcat   = { name = "Wildcat Drillers", mods = { oilCoin = 5, oilLife = -6, pop = -3.5 } },
    genius    = { name = "Tactical Genius",  mods = { attack = 0.04, defense = 0.04, upkeep = 0.15 } },
    hunters   = { name = "Hunters",          mods = { fog = 1, attack = 0.03, train = -1 } },
    barracks  = { name = "Barracks Culture", mods = { train = -4, weapons = -0.3 } },
    legends   = { name = "Sea Legends",      mods = { coastRange = 1.0, pop = -3.5 } },
    martyrs   = { name = "Martyrs",          mods = { defense = 0.12, hp = -2 } },
    scorched  = { name = "Scorched Earth",   mods = { defense = 0.06, coins = -0.8 } },
    golden    = { name = "Golden Age",       mods = { coins = 5, weapons = 0.5, attack = 0.03 } },
    carto     = { name = "Cartographers",    mods = { fog = 4, coins = -1 } },
    nostepback  = { name = "No Step Back",    mods = { defense = 0.20, pop = -8 } },
    legrishand  = { name = "Legris's hand",    mods = { defense = 0.30, attack = 0.30 } },
    everypatriot  = { name = "Every Patriot",    mods = { weapons = 2 } },

    rangers   = { name = "Forest Rangers",   biome = { [2] = { attack = 0.08, defense = 0.05 } } },
    nomads    = { name = "Desert Nomads",    biome = { [3] = { move = -0.5, defense = 0.05 } } },
    arctic    = { name = "Arctic Troops",    biome = { [4] = { attack = 0.15, defense = 0.20 } } },
    cavalry   = { name = "Plains Cavalry",   biome = { [1] = { move = -0.3, attack = 0.05 } } },
    ambush    = { name = "Woodland Ambush",  biome = { [2] = { defense = 0.12 }, [1] = { defense = -0.05 } } },
    dunes     = { name = "Dune Raiders",     biome = { [3] = { attack = 0.10, defense = -0.03 } } },
    frost     = { name = "Frostbitten",      biome = { [4] = { defense = 0.15 }, [1] = { attack = -0.05 } } },
    openfield = { name = "Open Field Doctrine", biome = { [1] = { attack = 0.08, defense = 0.05 }, [2] = { attack = -0.06 } } },
    jungle    = { name = "Jungle Fighters",  biome = { [2] = { move = -0.3 }, [3] = { attack = -0.05 } } },
    sandwalk  = { name = "Sand Walkers",     biome = { [3] = { move = -0.4, attack = 0.05 }, [4] = { defense = -0.05 } } },
    icewolves = { name = "Ice Wolves",       biome = { [4] = { attack = 0.10, move = -0.3 }, [3] = { defense = -0.05 } } },
    steppe    = { name = "Steppe Riders",    biome = { [1] = { move = -0.4 }, [2] = { move = 0.3 } } },

    horselords = { name = "Horse Lords",     mods = { cavAttack = 0.15, cavMove = -0.05 } },
    steelhorse = { name = "Steel Horsemen",  mods = { cavHp = 2, cavDefense = 0.05 } },
    hussars    = { name = "Winged Hussars",  mods = { cavAttack = 0.12, cavHp = -1 } },
    stable     = { name = "Stable Masters",  mods = { cavUpkeep = -0.25, cavTrain = -4 } },
    endless    = { name = "Endless Riders",  mods = { cavOrg = 3, cavMove = -0.1 } },
    lancers    = { name = "Lancers",         mods = { cavAttack = 0.10, cavDefense = -0.05 } },
    heavycav   = { name = "Heavy Cavalry",   mods = { cavHp = 3, cavDefense = 0.08, cavMove = 0.2 } },
    raiders    = { name = "Raiding Party",   mods = { cavMove = -0.3, cavUpkeep = 0.2 } },
    horde      = { name = "Horde Tactics",   mods = { cavAttack = 0.06, cavOrg = 2, cavHp = -1, cavUpkeep = -0.15 } },
    cavdoc     = { name = "Cavalry Doctrine", mods = { cavAttack = 0.05, cavDefense = 0.05 } },
    breeders   = { name = "Horse Breeders",  mods = { cavUpkeep = -0.4, cavTrain = 3 } },
    dragoons   = { name = "Dragoons",        mods = { cavAttack = 0.07, attack = 0.03 } },
    plainshorse = { name = "Plains Horsemen", biome = { [1] = { cavMove = -0.3, cavAttack = 0.10 } } },
    woodriders = { name = "Woodland Riders", biome = { [2] = { cavMove = 0.3, cavDefense = -0.05 }, [1] = { cavDefense = 0.05 } } },
    desertriders = { name = "Desert Riders", biome = { [3] = { cavMove = -0.5, cavAttack = 0.05 }, [4] = { cavDefense = -0.05 } } },
}

GC.SpiritDefs.warlord  = { name = "Warlord",       mods = { attack = 0.15, defense = 0.05, org = 2 } }
GC.SpiritDefs.empire   = { name = "Golden Empire", mods = { coins = 5, pop = 10, weapons = 5 } }
GC.SpiritDefs.unbreak  = { name = "Unbreakable",   mods = { hp = 5, org = 5, defense = 0.05 } }
GC.SpiritDefs.ghostcav = { name = "Ghost Riders",  mods = { cavAttack = 0.12, cavDefense = 0.08, cavMove = 0.25, cavHp = 2 } }
GC.SpiritDefs.oilemp   = { name = "Oil Empire",    mods = { oilCoin = 10, oilLife = 10 } }
for _, id in ipairs({ "warlord", "empire", "unbreak", "ghostcav", "oilemp" }) do
    GC.SpiritOrder[#GC.SpiritOrder + 1] = id
end

for _, id in ipairs({ "ironwall", "veterans", "baron", "golden", "arctic", "horselords", "steelhorse",
    "warlord", "empire", "unbreak", "ghostcav", "oilemp", "industry", "blitz", "radar", "legrishand" }) do
    GC.SpiritDefs[id].rare = true
end
GC.UncommonChance = 0.5
GC.UncommonColor = Color(235, 60, 60)

local function SD(slot)
    if SERVER then return GC.Slots and GC.Slots[slot] end
    return GC.players and GC.players[slot]
end

function GC.Mod(slot, key)
    local P, v = SD(slot or 0), 0
    if P and P.spirits then
        for _, s in ipairs(P.spirits) do
            local d = GC.SpiritDefs[s.id]
            if d and d.mods and d.mods[key] then v = v + d.mods[key] end
        end
    end
    return v
end

function GC.ModVs(slot, key, vs)
    local P, v = SD(slot or 0), 0
    if P and P.spirits then
        for _, s in ipairs(P.spirits) do
            local d = GC.SpiritDefs[s.id]
            if d and d.vs and d.vs[key] and s.target == vs then v = v + d.vs[key] end
        end
    end
    return v
end

function GC.HueName(col)
    local h = ColorToHSV(col)
    if h < 15 or h >= 345 then return "Red"
    elseif h < 45 then return "Orange"
    elseif h < 70 then return "Yellow"
    elseif h < 165 then return "Green"
    elseif h < 200 then return "Cyan"
    elseif h < 260 then return "Blue"
    elseif h < 290 then return "Purple" end
    return "Pink"
end

function GC.SpiritName(inst, plist)
    local d = GC.SpiritDefs[inst.id]
    if not d then return "?" end
    if d.target then
        local T = plist[inst.target or 0]
        return (T and GC.HueName(T.color) or "?") .. " Hate"
    end
    return d.name
end

function GC.ModValue(key, v)
    local info = GC.ModInfo[key]
    if info.pct then return string.format("%+g%%", math.Round(v * 100, 2)) end
    return string.format("%+g", v) .. (info.unit or "")
end

function GC.MaxOrg(slot, cav)
    local v = GC.Combat.MaxOrg
    if cav then v = v + GC.Combat.CavOrg + GC.Mod(slot, "cavOrg") else v = v + GC.Mod(slot, "org") end
    return math.max(1, v)
end
function GC.MaxHP(slot, cav)
    local v = GC.Combat.MaxHP
    if cav then v = v + GC.Combat.CavHP + GC.Mod(slot, "cavHp") else v = v + GC.Mod(slot, "hp") end
    return math.max(1, v)
end
function GC.TrainTime(slot, cav)
    local v = GC.Combat.TrainTime + GC.Mod(slot, cav and "cavTrain" or "train")
    return math.max(1, v)
end

function GC.AttackMods(slot, cav, biome, vs)
    if cav then
        return GC.Combat.CavAttack + GC.Mod(slot, "cavAttack") + GC.BiomeMod(slot, biome, "cavAttack")
    end
    return GC.Mod(slot, "attack") + (vs and GC.ModVs(slot, "attack", vs) or 0) + GC.BiomeMod(slot, biome, "attack")
end
function GC.DefenseMods(slot, cav, biome)
    if cav then
        return GC.Combat.CavDefense + GC.Mod(slot, "cavDefense") + GC.BiomeMod(slot, biome, "cavDefense")
    end
    return GC.Mod(slot, "defense") + GC.BiomeMod(slot, biome, "defense")
end
function GC.AirRange(slot) return math.max(1, GC.AirRadius + GC.Mod(slot, "airRange")) end
function GC.CoastRange(slot) return math.max(1, math.floor(GC.CoastRadius * (1 + GC.Mod(slot, "coastRange")) + 0.5)) end
function GC.FogRange(slot) return math.max(1, GC.FogRadius + GC.Mod(slot, "fog")) end

function GC.UpkeepPerArmy(slot, cav)
    local C = GC.Combat
    local mult = 1 + GC.Mod(slot, cav and "cavUpkeep" or "upkeep")
    return (cav and C.CavUpkeepCoins or C.UpkeepCoins) / C.UpkeepInterval * math.max(0, mult)
end

function GC.BiomeMod(slot, biome, key)
    local P, v = SD(slot or 0), 0
    if P and P.spirits then
        for _, s in ipairs(P.spirits) do
            local d = GC.SpiritDefs[s.id]
            local bm = d and d.biome and d.biome[biome]
            if bm and bm[key] then v = v + bm[key] end
        end
    end
    return v
end

function GC.MoveMult(slot, cell, cav)
    local b = GC.biome[cell]
    local m = (b == GC.DESERT) and GC.Combat.DesertMoveMult or 1
    local mod
    if cav then
        m = m * GC.Combat.CavMove
        mod = GC.BiomeMod(slot, b, "cavMove") + GC.Mod(slot, "cavMove")
    else
        mod = GC.BiomeMod(slot, b, "move")
    end
    return m * math.max(0.25, 1 + mod)
end

function GC.SpiritLines(inst, plist)
    local d = GC.SpiritDefs[inst.id]
    if not d then return "?", { "?" } end
    local name = GC.SpiritName(inst, plist)
    local lines = { name }
    if d.mods then
        for _, key in ipairs(GC.ModOrder) do
            local v = d.mods[key]
            if v then lines[#lines + 1] = GC.ModInfo[key].label .. ": " .. GC.ModValue(key, v) end
        end
    end
    if d.vs then
        local T = plist[inst.target or 0]
        for _, key in ipairs(GC.ModOrder) do
            local v = d.vs[key]
            if v then lines[#lines + 1] = GC.ModInfo[key].label .. " against " .. (T and T.name or "?") .. ": " .. GC.ModValue(key, v) end
        end
    end
    if d.biome then
        for b = 1, 4 do
            local bm = d.biome[b]
            if bm then
                for _, key in ipairs(GC.BiomeModOrder) do
                    local v = bm[key]
                    if v then
                        lines[#lines + 1] = GC.BiomeModInfo[key].label .. " on " .. GC.Biomes[b].name .. ": " .. string.format("%+g%%", math.Round(v * 100, 2))
                    end
                end
            end
        end
    end
    return name, lines
end

function GC.PopLimit(slot)
    local c = 0
    for i = 1, GCN do
        if GC.owner[i] == slot then c = c + 1 end
    end
    return c * GC.PopPerCell
end

function GC.InSupply(slot, cell)
    local cx, cy = XY(cell)
    local R = GC.SupplyRadius
    for y = math.max(0, cy - R), math.min(GCH - 1, cy + R) do
        for x = math.max(0, cx - R), math.min(GCW - 1, cx + R) do
            local j = y * GCW + x + 1
            if GC.build[j] == GC.B_VILLAGE and (GC.owner[j] == slot or GC.HasAccess(slot, GC.owner[j])) then return true end
        end
    end
    return false
end

function GC.Neighbors(i)
    local x, y = (i - 1) % GCW, math.floor((i - 1) / GCW)
    local t = {}
    if x > 0     then t[#t + 1] = i - 1 end
    if x < GCW - 1 then t[#t + 1] = i + 1 end
    if y > 0     then t[#t + 1] = i - GCW end
    if y < GCH - 1 then t[#t + 1] = i + GCW end
    return t
end

function GC.Neighbors8(i)
    local x, y = (i - 1) % GCW, math.floor((i - 1) / GCW)
    local t = {}
    for dy = -1, 1 do
        for dx = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local nx, ny = x + dx, y + dy
                if nx >= 0 and nx < GCW and ny >= 0 and ny < GCH then t[#t + 1] = ny * GCW + nx + 1 end
            end
        end
    end
    return t
end

function GC.HasNeighbor(owner, i, slot, ship)
    for _, j in ipairs(GC.Neighbors(i)) do
        if owner[j] == slot or (ship and ship[j] == slot) then return true end
    end
    return false
end

function GC.HasLandNeighbor(i)
    for _, j in ipairs(GC.Neighbors(i)) do
        if not GC.Biomes[GC.biome[j]].water then return true end
    end
    return false
end

function GC.IsCoast(i)
    if GC.Biomes[GC.biome[i]].water then return false end
    for _, j in ipairs(GC.Neighbors(i)) do
        if GC.Biomes[GC.biome[j]].water then return true end
    end
    return false
end

function GC.CoastGuardNear(i, slot)
    local cx, cy = (i - 1) % GCW, math.floor((i - 1) / GCW)
    local R = GC.CoastRange(slot)
    for y = math.max(0, cy - R), math.min(GCH - 1, cy + R) do
        for x = math.max(0, cx - R), math.min(GCW - 1, cx + R) do
            if (x - cx) ^ 2 + (y - cy) ^ 2 <= R * R then
                local j = y * GCW + x + 1
                if GC.build[j] == GC.B_COAST and GC.owner[j] == slot then return true end
            end
        end
    end
    return false
end

function GC.AirbaseNear(i, slot)
    local cx, cy = XY(i)
    local R = GC.AirRange(slot)
    for j = 1, GCN do
        if GC.build[j] == GC.B_AIR and GC.owner[j] == slot then
            local x, y = XY(j)
            if math.abs(x - cx) <= R and math.abs(y - cy) <= R then return j end
        end
    end
end

function GC.CapitalConnected(slot)
    local seen, q = {}, {}
    for i = 1, GCN do
        if GC.owner[i] == slot and GC.build[i] == GC.B_CAPITAL then
            seen[i] = true
            q[#q + 1] = i
        end
    end
    local h = 1
    while h <= #q do
        local c = q[h]
        h = h + 1
        for _, j in ipairs(GC.Neighbors(c)) do
            if not seen[j] and GC.owner[j] == slot then
                seen[j] = true
                q[#q + 1] = j
            end
        end
    end
    return seen
end

local function Components(pred)
    local comp, nc = {}, 0
    for i = 1, GCN do
        if not comp[i] and pred(i) then
            nc = nc + 1
            comp[i] = nc
            local q, h = { i }, 1
            while h <= #q do
                local c = q[h]
                h = h + 1
                for _, j in ipairs(GC.Neighbors(c)) do
                    if not comp[j] and pred(j) then
                        comp[j] = nc
                        q[#q + 1] = j
                    end
                end
            end
        end
    end
    return comp
end

function GC.CanBuildAt(slot, i)
    if GC.owner[i] ~= slot then return false end
    local conn = GC.CapitalConnected(slot)
    if conn[i] then return true end

    local land = Components(function(c) local b = GC.biome[c] return b ~= 0 and b ~= GC.WATER end)
    local capLand = {}
    for c in pairs(conn) do
        local lc = land[c]
        if lc then capLand[lc] = true end
    end
    if land[i] and capLand[land[i]] then return true end

    local function IsW(c)
        local b = GC.biome[c]
        return b == GC.WATER or (CLIENT and b == 0)
    end
    local water = Components(IsW)

    local capLakes = {}
    for c = 1, GCN do
        local lc = land[c]
        if lc and capLand[lc] then
            for _, j in ipairs(GC.Neighbors8(c)) do
                if water[j] then capLakes[water[j]] = true end
            end
        end
    end

    local cluster, q, h = { [i] = true }, { i }, 1
    while h <= #q do
        local c = q[h]
        h = h + 1
        for _, j in ipairs(GC.Neighbors(c)) do
            if not cluster[j] and GC.owner[j] == slot then
                cluster[j] = true
                q[#q + 1] = j
            end
        end
    end
    local tgtLakes = {}
    for c in pairs(cluster) do
        for _, j in ipairs(GC.Neighbors8(c)) do
            if water[j] then tgtLakes[water[j]] = true end
        end
    end

    for j = 1, GCN do
        local w = water[j]
        if w and GC.ship[j] == slot and capLakes[w] and tgtLakes[w] then return true end
    end
    return false
end

function GC.CanArmyMoveTo(slot, from, to)
    if not to or to < 1 or to > GCN then return false end
    if not table.HasValue(GC.Neighbors8(from), to) then return false end
    if GC.army[to] then return false end
    if GC.build[to] == GC.B_CRATER then return false end
    if GC.Biomes[GC.biome[to]].water then return GC.ship[to] == slot end
    return GC.owner[to] == slot or GC.HasAccess(slot, GC.owner[to])
end

function GC.CanArmyLand(slot, from, to)
    if not to or to < 1 or to > GCN then return false end
    if not table.HasValue(GC.Neighbors8(from), to) then return false end
    if GC.Biomes[GC.biome[to]].water then return false end
    if GC.build[to] == GC.B_CRATER then return false end
    local D = GC.army[to]
    if D and D.owner == slot then return false end
    local eo = D and D.owner or GC.owner[to]
    if eo ~= 0 and eo ~= slot and GC.HasPact(slot, eo) then return false end
    if GC.AccessTie(slot, eo) and (D or not GC.HasAccess(slot, eo)) then return false end
    return true
end

function GC.CanArmyAttack(slot, from, to)
    if not to or to < 1 or to > GCN then return false end
    if not table.HasValue(GC.Neighbors8(from), to) then return false end
    if GC.Biomes[GC.biome[to]].water then return false end
    local D = GC.army[to]
    local o = D and D.owner or GC.owner[to]
    if o == 0 or o == slot then return false end
    return not GC.HasPact(slot, o) and not GC.AccessTie(slot, o)
end

function GC.HasAccess(slot, owner)
    return owner ~= nil and owner ~= 0 and owner ~= slot and GC.access[owner * 256 + slot] == true
end

function GC.AccessTie(a, b)
    if not a or not b or a == 0 or b == 0 or a == b then return false end
    return GC.access[a * 256 + b] == true or GC.access[b * 256 + a] == true
end

function GC.Friendly(a, b)
    return GC.HasPact(a, b) or GC.AccessTie(a, b)
end

function GC.CanStand(slot, cell)
    if not cell or cell < 1 or cell > GCN or GC.Biomes[GC.biome[cell]].water then return false end
    if GC.build[cell] == GC.B_CRATER then return false end
    local o = GC.owner[cell]
    return o == slot or GC.HasAccess(slot, o)
end

function GC.CanSpawnArmy(slot, i, cav)
    if GC.Biomes[GC.biome[i]].water or GC.owner[i] ~= slot or GC.army[i] then return false end
    return GC.build[i] == (cav and GC.B_CAVC or GC.B_ARMYC)
end

GC.Mods = GC.Mods or {}
local M = GC.Mods
M.API = 1
M.Dir = "gcapture/mods"
M.list, M.byId = {}, {}
M.Actions, M.ActionByKey = {}, {}
M.BuildId = {}
M.IncomeMods = {}
M.cur = nil
M.NextBuild, M.NextAct = 14, 32

local function Log(fmt, ...)
    MsgC(Color(60, 210, 110), "[GCapture/mods] ", color_white, string.format(fmt, ...) .. "\n")
end
local function Err(fmt, ...)
    MsgC(Color(255, 90, 90), "[GCapture/mods] ", color_white, string.format(fmt, ...) .. "\n")
end
M.Log, M.Err = Log, Err

function M.Register(info)
    local cur = M.cur
    if not cur then error("GCapture.Mods.Register must be called while a submod file is loading", 2) end
    info = info or {}
    if info.api and info.api > M.API then
        error(string.format("submod '%s' needs GCapture Submod API %d, installed is %d", cur.id, info.api, M.API), 2)
    end
    cur.name = info.name or cur.name
    cur.version = info.version or cur.version
    cur.author = info.author or cur.author
    cur.desc = info.desc or cur.desc
    cur.workshop = info.workshop or cur.workshop
    if SERVER and cur.workshop then resource.AddWorkshop(tostring(cur.workshop)) end
end

local function Need(cond, msg)
    if not cond then error(msg, 3) end
end

function M.AddSpirit(id, def)
    Need(type(id) == "string" and id ~= "" and not id:find("[:%s]"), "spirit id must be a non-empty string without ':' or spaces")
    Need(type(def) == "table" and def.name, "spirit '" .. id .. "' needs a name")
    Need(not GC.SpiritDefs[id], "spirit id '" .. id .. "' is already taken (prefix ids with your submod id)")
    for key in pairs(def.mods or {}) do
        Need(GC.ModInfo[key], "spirit '" .. id .. "': unknown modifier '" .. tostring(key) .. "' (use GCapture.Mods.AddModifier first)")
    end
    for key in pairs(def.vs or {}) do
        Need(GC.ModInfo[key], "spirit '" .. id .. "': unknown modifier '" .. tostring(key) .. "' in vs")
    end
    for b, bm in pairs(def.biome or {}) do
        Need(GC.Biomes[b] and b >= 1 and b <= 4, "spirit '" .. id .. "': biome must be 1-4")
        for key in pairs(bm) do
            Need(GC.BiomeModInfo[key], "spirit '" .. id .. "': unknown biome modifier '" .. tostring(key) .. "'")
        end
    end
    def.mod = M.cur and M.cur.id
    GC.SpiritDefs[id] = def
    GC.SpiritOrder[#GC.SpiritOrder + 1] = id
    return id
end

function M.AddModifier(key, info)
    Need(type(key) == "string" and key ~= "", "modifier key must be a string")
    Need(not GC.ModInfo[key], "modifier '" .. key .. "' already exists")
    info = info or {}
    GC.ModInfo[key] = { label = info.label or key, pct = info.pct, unit = info.unit }
    GC.ModOrder[#GC.ModOrder + 1] = key
    if info.income then
        local idx = ({ coins = 1, pop = 2, weapons = 3 })[info.income]
        Need(idx, "modifier income must be 'coins', 'pop' or 'weapons'")
        M.IncomeMods[#M.IncomeMods + 1] = { key = key, idx = idx }
    end
end

function M.AddBuild(key, def)
    Need(type(key) == "string" and key ~= "", "build key must be a string")
    Need(not M.BuildId[key], "build '" .. key .. "' already exists")
    Need(type(def) == "table" and def.name and def.icon, "build '" .. key .. "' needs name and icon")
    local id = M.NextBuild
    Need(id < 2 ^ GC.BuildBits, "too many structures (max " .. (2 ^ GC.BuildBits - 1) .. ")")
    M.NextBuild = id + 1
    def.mod, def.key = M.cur and M.cur.id, key
    GC.Build[id] = def
    M.BuildId[key] = id
    if CLIENT and GC.BuildMats then GC.BuildMats[id] = Material(def.icon) end
    return id
end

function M.AddAction(key, def)
    Need(type(key) == "string" and key ~= "", "action key must be a string")
    Need(not M.ActionByKey[key], "action '" .. key .. "' already exists")
    Need(type(def) == "table" and def.name, "action '" .. key .. "' needs a name")
    local id = M.NextAct
    Need(id < 2 ^ GC.ActBits, "too many actions")
    M.NextAct = id + 1
    if type(def.build) == "string" then
        Need(M.BuildId[def.build], "action '" .. key .. "': unknown build '" .. def.build .. "' (call AddBuild first)")
        def.build = M.BuildId[def.build]
    end
    if type(def.on) == "string" then
        Need(M.BuildId[def.on], "action '" .. key .. "': unknown build '" .. def.on .. "' in 'on'")
        def.on = M.BuildId[def.on]
    end
    Need(def.build or def.run, "action '" .. key .. "' needs either 'build' or 'run'")
    def.icon = def.icon or "gcapture/gc_act_brown.png"
    def.where = def.where or (def.build and "empty_own" or "own")
    def.mod, def.key, def.id = M.cur and M.cur.id, key, id
    GC.Actions[id] = def
    M.Actions[#M.Actions + 1] = def
    M.ActionByKey[key] = def
    return id
end

function M.CellMatches(a, slot, cell)
    local owner, bl = GC.owner[cell], GC.build[cell]
    if a.on and not (owner == slot and bl == a.on) then return false end
    local w = a.where
    if w == "any" then return true
    elseif w == "empty_own" then return owner == slot and bl == 0 and GC.CanBuildAt(slot, cell)
    elseif w == "own" then return owner == slot
    elseif w == "enemy" then return owner ~= 0 and owner ~= slot
    elseif w == "neutral" then return owner == 0 end
    return false
end

function M.CheckAction(a, ply, slot, cell, cell2)
    if a.run and not M.CellMatches(a, slot, cell) then return false, "You can't do that here." end
    if a.can then
        local ok, r, msg = pcall(a.can, ply, slot, cell, cell2)
        if not ok then
            Err("action '%s' can() failed: %s", tostring(a.key), tostring(r))
            return false, "Error in submod."
        end
        if not r then return false, msg or "You can't do that here." end
    end
    return true
end

function M.PopulateMenu(menu, cell, slot, Add, army)
    if #M.Actions == 0 then return end
    local water = GC.Biomes[GC.biome[cell]].water and true or false
    for _, a in ipairs(M.Actions) do
        if (a.any or (a.water and true or false) == water) and M.CellMatches(a, slot, cell)
            and not (a.biome and GC.biome[cell] ~= a.biome) and not (a.coast and not GC.IsCoast(cell)) then
            local okShow = true
            if a.show then
                local ok, r = pcall(a.show, slot, cell)
                okShow = ok and r ~= false
                if not ok then Err("action '%s' show() failed: %s", tostring(a.key), tostring(r)) end
            end
            if okShow then
                local opt = Add(a.id)
                if opt and a.desc then opt:SetTooltip(a.desc) end
            end
        end
    end
end

if SERVER then
    hook.Add("GCapture_Income", "GCapture_Mods_Income", function(slot, I)
        for _, m in ipairs(M.IncomeMods) do
            local v = GC.Mod(slot, m.key)
            if v ~= 0 then I[m.idx] = I[m.idx] + v end
        end
    end)
end

local function ModPath(id, fname) return M.Dir .. "/" .. id .. "/" .. fname end

local function SafeInclude(info, fname)
    local path = ModPath(info.id, fname)
    if not file.Exists(path, "LUA") then return end
    M.cur = info
    local ok, err = xpcall(include, function(e) return debug.traceback(tostring(e), 2) end, path)
    M.cur = nil
    if not ok then
        info.failed = true
        Err("submod '%s' failed in %s:\n%s", info.id, fname, tostring(err))
        return false
    end
    return true
end

local function NewInfo(id)
    local info = { id = id, name = id, version = "1.0", author = "?", desc = "" }
    M.list[#M.list + 1], M.byId[id] = info, info
    return info
end

function M.LoadShared(id)
    if M.byId[id] then return M.byId[id] end
    local info = NewInfo(id)
    SafeInclude(info, "shared.lua")
    return info
end

function M.LoadRealm(id)
    local info = M.byId[id]
    if not info or info.failed then return end
    SafeInclude(info, SERVER and "server.lua" or "client.lua")
end

function M.Finish()
    if M.finished then return end
    M.finished = true
    if #M.list > 0 then
        Log("%d submod(s) loaded (%s):", #M.list, SERVER and "server" or "client")
        for _, m in ipairs(M.list) do
            Log("  %s [%s] v%s by %s%s", m.name, m.id, m.version, m.author, m.failed and "  (FAILED)" or "")
        end
    end
    hook.Run("GCapture_ModsLoaded")
end

local function DisabledList()
    local t = {}
    local raw = file.Read("gcapture_disabled_mods.txt", "DATA")
    if raw then
        for line in raw:gmatch("[^\r\n]+") do
            line = string.Trim(line)
            if line ~= "" and line:sub(1, 1) ~= "#" then t[line] = true end
        end
    end
    return t
end

if SERVER then
    util.AddNetworkString("GCapture_ModList")

    local _, dirs = file.Find(M.Dir .. "/*", "LUA")
    local off = DisabledList()
    M.serverIds = {}
    for _, id in ipairs(dirs or {}) do
        if id:sub(1, 1) ~= "_" and id:sub(1, 1) ~= "." and not off[id] then
            for _, f in ipairs({ "shared.lua", "client.lua" }) do
                if file.Exists(ModPath(id, f), "LUA") then AddCSLuaFile(ModPath(id, f)) end
            end
            M.serverIds[#M.serverIds + 1] = id
            M.LoadShared(id)
        end
    end

    hook.Add("Initialize", "GCapture_Mods_Server", function()
        for _, id in ipairs(M.serverIds) do M.LoadRealm(id) end
        M.Finish()
    end)

    net.Receive("GCapture_ModList", function(_, ply)
        net.Start("GCapture_ModList")
        net.WriteUInt(#M.serverIds, 8)
        for _, id in ipairs(M.serverIds) do net.WriteString(id) end
        net.Send(ply)
    end)
else
    net.Receive("GCapture_ModList", function()
        if M.clientLoaded then return end
        M.clientLoaded = true
        local ids = {}
        for _ = 1, net.ReadUInt(8) do ids[#ids + 1] = net.ReadString() end
        for _, id in ipairs(ids) do M.LoadShared(id) end
        for _, id in ipairs(ids) do M.LoadRealm(id) end
        M.Finish()
    end)
    hook.Add("InitPostEntity", "GCapture_Mods_Request", function()
        net.Start("GCapture_ModList")
        net.SendToServer()
    end)
end

concommand.Add("gc_mods", function()
    if #M.list == 0 then Log("no submods installed") return end
    for _, m in ipairs(M.list) do
        Log("%s [%s] v%s by %s%s", m.name, m.id, m.version, m.author, m.failed and "  (FAILED)" or "")
    end
end)
