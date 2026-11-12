-- Example GCapture submod. Copy this folder, rename "example_submod" (folder name = submod id) and edit.
-- shared.lua runs on server AND client, in the same order, so ids of structures/actions match on both sides.
local GC = GCapture
local M = GC.Mods

M.Register({
    name = "Example Submod",
    version = "1.0",
    author = "you",
    desc = "Shows how to add spirits, a structure and actions.",
    api = 1,                -- minimal GCapture Submod API version this mod needs
    -- workshop = "1234567890", -- id of YOUR submod on the Workshop: the server will make clients download it
})

-- 1) a new spirit modifier. income = "coins" means: the value is added to coins per second automatically
M.AddModifier("taxIncome", { label = "Tax income", income = "coins" })

-- 2) spirits (they are picked up by the normal "choose 1 of 3" screen automatically)
M.AddSpirit("example_taxmen", { name = "Tax Collectors", mods = { taxIncome = 2, pop = -1 } })
-- rare = true: only from chests
M.AddSpirit("example_titan", { name = "Titan Doctrine", rare = true, mods = { attack = 0.10, hp = 2 } })
-- biome-specific spirit
M.AddSpirit("example_marsh", { name = "Marsh Hunters", biome = { [GC.FOREST] = { attack = 0.06, defense = 0.06 } } })

-- 3) a structure. icon = path inside materials/ (here we reuse a core icon; ship your own png in materials/)
M.AddBuild("example_tower", { name = "Watchtower", icon = "gcapture/gc_fortress.png", coin = 1, lifetime = nil })

-- 4) actions in the right-click menu
M.AddAction("example_build_tower", {
    name = "Build Watchtower", coins = 120,
    build = "example_tower",                      -- uses the standard build logic of the core
    desc = "Gives +1 coin per second.",
})

GC.ExampleCooldown = GC.ExampleCooldown or {} -- [cell] = CurTime() when it can be used again
M.AddAction("example_tax", {
    name = "Collect Tribute", on = "example_tower", -- only on your own Watchtower
    can = function(ply, slot, cell)                 -- server side check
        if (GC.ExampleCooldown[cell] or 0) > CurTime() then return false, "The tower is recharging." end
        return true
    end,
    run = function(ply, slot, cell, cell2, P)       -- server side effect (resources of the action are already paid)
        GC.ExampleCooldown[cell] = CurTime() + 30
        P.coins = math.min(GC.CoinLimit, P.coins + 40)
    end,
    show = function(slot, cell) return true end,    -- optional, client side
    desc = "+40 coins, 30 s cooldown per tower.",
})
