-- server.lua: runs once on the server after the whole GCapture core is loaded
local GC = GCapture
local towerId = GC.Mods.BuildId.example_tower

hook.Add("GCapture_GameStarted", "example_submod", function()
    GC.ExampleCooldown = {}
end)

-- 3 or more towers: +1 weapon per second. I = { coins, pop, weapons } per second of this player
hook.Add("GCapture_Income", "example_submod", function(slot, I, P)
    local n = 0
    for i = 1, GCN do
        if GC.owner[i] == slot and GC.build[i] == towerId then n = n + 1 end
    end
    if n >= 3 then I[3] = I[3] + 1 end
end)

-- somebody lost a tower
hook.Add("GCapture_CellChanged", "example_submod", function(cell, oldOwner, newOwner, oldBuild, newBuild)
    if oldBuild == towerId and oldOwner ~= newOwner then
        print(("[example_submod] tower at cell %d changed owner: %d -> %d"):format(cell, oldOwner, newOwner))
    end
end)
