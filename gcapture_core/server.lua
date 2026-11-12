local GC = GCapture
local XY = GC.XY

if not SERVER then return end

resource.AddFile("sound/gcapture/gcapture_calm.mp3")
    resource.AddFile("sound/gcapture/gcapture_combat.mp3")
    resource.AddFile("sound/gcapture/gcapture_theme.mp3")
    resource.AddFile("materials/gcapture/logo.png")
    resource.AddFile("materials/gcapture/gc_discord.png")

    for _, n in ipairs({ "View", "Lobby", "Start", "Stop", "Full", "Cell", "Ship", "Army", "Stats", "Act", "Win", "Vis", "Spirits", "Diplo", "Pacts", "Choice", "Pick", "Oil", "Boom", "Msg", "Build", "ExpandSound", "AirCD", "Name", "Opts", "Time", "Snd", "Color", "Rec", "DemoSend", "SpecSp", "Access", "FullData", "MapUp", "Auto", "Event", "Biome", "Exp", "Deploy", "DeployData", "DeployPick", "Odds" }) do
        util.AddNetworkString("GCapture_" .. n)
    end

    GC.State = "lobby"
    GC.Viewers = {}
    GC.Slots = {}
    GC.SlotOf = {}
    GC.Winner = nil
    GC.biome, GC.owner, GC.build, GC.ship = {}, {}, {}, {}
    GC.expire = {}
    GC.shipOrd = {}
    GC.expPend = {}
    GC.airCd = {}
    GC.offers = {}
    GC.disc = {}
    GC.accessExp = {}
    GC.oilUsed = {}
    GC.Choices = {}
    GC.army = {}

    local C = GC.Combat

    local cvFog = CreateConVar("sv_gc_fog", "1", FCVAR_ARCHIVE + FCVAR_NOTIFY, "GCapture: fog of war (1 = on, 0 = off)", 0, 1)
    GC.VisOf = {}
    GC.Seen = {}
    GC.GameId = 0
    GC.DayT0 = CurTime()
    function GC.CycleNow() return CurTime() - GC.DayT0 end
    GC.Opts = GC.Opts or { mode = 0, rush = false, nofog = false, noevents = false, emperor = false, bots = 0, diff = 1, btype = 3, size = 1, observe = false, seed = "", map = "" }
    for _, k in ipairs(GC.OptFlags) do if GC.Opts[k] == nil then GC.Opts[k] = false end end
GC.Dead = GC.Dead or {}
    GC.Opts.map = GC.Opts.map or ""
    GC.CustomMap = nil
    GC.Names = GC.Names or {}
    GC.Colors = GC.Colors or {}

    local function IsHost(ply)
        if ply:IsListenServerHost() or (game.IsDedicated() and ply:IsSuperAdmin()) then return true end

        if not GC.Viewers[ply] then return false end
        for p in pairs(GC.Viewers) do
            if p ~= ply and IsValid(p) and not p:IsBot() then return false end
        end
        return true
    end

    local function ViewerList(noBots)
        local t = {}
        for p in pairs(GC.Viewers) do
            if IsValid(p) and not (noBots and p:IsBot()) then t[#t + 1] = p end
        end
        return t
    end

    function GC.SendTime(target)
        local v = target and { target } or ViewerList(true)
        if #v == 0 then return end
        net.Start("GCapture_Time")
        net.WriteFloat(GC.CycleNow())
        net.Send(v)
    end

    local function SendMsg(ply, msg)
        if not IsValid(ply) or ply:IsBot() then return end
        net.Start("GCapture_Msg")
        net.WriteString(msg)
        net.Send(ply)
    end

    local function Notify(slot, msg)
        local P = GC.Slots[slot]
        if P then SendMsg(P.ply, msg) end
    end

    local function AddCoins(P, d)
        local v = P.coins + d
        if d > 0 then v = math.max(P.coins, math.min(GC.CoinLimit, v)) end
        P.coins = math.max(0, v)
    end
    local function AddPop(slot, P, d)
        local lim = GC.PopLimit(slot)
        local v = P.pop + d
        if d > 0 then v = math.max(P.pop, math.min(lim, v)) end
        P.pop = math.max(0, v)
    end

    local function NewNoise(seed)
        math.randomseed(seed)
        local octs, freq, amp, total = {}, 4, 1, 0
        for o = 1, 3 do
            local lat = {}
            for i = 0, freq + 1 do
                lat[i] = {}
                for j = 0, freq + 1 do lat[i][j] = math.random() end
            end
            octs[o] = { f = freq, a = amp, l = lat }
            total = total + amp
            freq, amp = freq * 2, amp * 0.5
        end
        return function(x, y)
            local v = 0
            for _, o in ipairs(octs) do
                local fx, fy = x * o.f, y * o.f
                local ix, iy = math.floor(fx), math.floor(fy)
                local tx, ty = fx - ix, fy - iy
                tx = tx * tx * (3 - 2 * tx)
                ty = ty * ty * (3 - 2 * ty)
                local l = o.l
                local a = Lerp(tx, l[ix][iy], l[ix + 1][iy])
                local b = Lerp(tx, l[ix][iy + 1], l[ix + 1][iy + 1])
                v = v + Lerp(ty, a, b) * o.a
            end
            return v / total
        end
    end

    function GC.Generate(base)
        GC.blevel = {}
        local land
        for attempt = 1, 6 do
            local seed = (base or (os.time() + math.random(1, 100000))) + (attempt - 1) * 7919
            local elev, moist, temp = NewNoise(seed), NewNoise(seed + 101), NewNoise(seed + 202)

            local enabled, any = {}, false
            for b = 1, 4 do
                enabled[b] = not GC.Opts[GC.OptBiomeFlag[b]] and math.random() < GC.BiomeSpawnChance[b]
                any = any or enabled[b]
            end
            if not any then
                local pick = GC.PLAINS
                for b = 1, 4 do
                    if not GC.Opts[GC.OptBiomeFlag[b]] then pick = b break end
                end
                enabled[pick] = true
            end
            local fallback = { [1] = { 2, 3, 4 }, [2] = { 1, 3, 4 }, [3] = { 1, 4, 2 }, [4] = { 1, 3, 2 } }
            local function Resolve(b)
                if enabled[b] then return b end
                for _, f in ipairs(fallback[b]) do
                    if enabled[f] then return f end
                end
                return GC.PLAINS
            end

            land = 0
            for y = 0, GCH - 1 do
                for x = 0, GCW - 1 do
                    local i = y * GCW + x + 1
                    local nx, ny = (x + 0.5) / GCW, (y + 0.5) / GCH
                    local dx, dy = nx - 0.5, ny - 0.5
                    local d = math.sqrt(dx * dx + dy * dy) * 2
                    local e = elev(nx, ny) - 0.15 * d * d

                    local b
                    if e < 0.40 and not GC.Opts.noocean then
                        b = GC.WATER
                    else
                        land = land + 1
                        local lat = 1 - math.abs(ny - 0.5) * 2
                        local t = lat * 0.8 + temp(nx, ny) * 0.4 - 0.05 - math.max(0, e - 0.60) * 1.2
                        local m = moist(nx, ny)
                        if t < 0.45 then b = GC.TUNDRA
                        elseif m < 0.45 and t > 0.55 then b = GC.DESERT
                        elseif m > 0.55 then b = GC.FOREST
                        else b = GC.PLAINS end
                        b = Resolve(b)
                    end
                    GC.biome[i], GC.owner[i], GC.build[i], GC.ship[i] = b, 0, 0, 0
                end
            end
            if land >= math.floor(GCN * 0.2) then break end
        end
    end

    local function WriteSpirits(slot)
        local P = slot and GC.Slots[slot]
        local list = P and P.spirits or {}
        net.WriteUInt(#list, 8)
        for _, s in ipairs(list) do
            net.WriteString(s.id)
            net.WriteUInt(s.target or 0, 8)
        end
    end

    function GC.SendSpirits(slot)
        if GC.State ~= "playing" then return end
        local P = GC.Slots[slot]
        if not P or not IsValid(P.ply) or P.ply:IsBot() then return end
        net.Start("GCapture_Spirits")
        WriteSpirits(slot)
        net.Send(P.ply)
    end

    function GC.SendSpecSpirits(target)
        if GC.State ~= "playing" then return end
        local v = {}
        if target then v = { target } else
            for _, p in ipairs(ViewerList(true)) do
                if not GC.SlotOf[p] then v[#v + 1] = p end
            end
        end
        if #v == 0 then return end
        net.Start("GCapture_SpecSp")
        net.WriteUInt(#GC.Slots, 8)
        for s = 1, #GC.Slots do WriteSpirits(s) end
        net.Send(v)
    end

    function GC.RollSpirit(slot, rare)
        local others = {}
        for s2 in ipairs(GC.Slots) do
            if s2 ~= slot then others[#others + 1] = s2 end
        end
        if rare == nil then rare = math.random() < GC.UncommonChance end
        local pool = {}
        for _, id in ipairs(GC.SpiritOrder) do
            local d = GC.SpiritDefs[id]
            if (d.rare == true) == rare and (not d.target or #others > 0) then pool[#pool + 1] = id end
        end
        if #pool == 0 then return end
        local id = pool[math.random(#pool)]
        local inst = { id = id }
        if GC.SpiritDefs[id].target then inst.target = others[math.random(#others)] end
        return inst
    end
    function GC.GiveSpirit(slot, inst)
        local P = GC.Slots[slot]
        if not P or not inst then return end
        P.spirits[#P.spirits + 1] = inst
        GC.SendSpirits(slot)
        GC.SendSpecSpirits()
        if GC.State == "playing" then
            Notify(slot, "New " .. (GC.SpiritDefs[inst.id].rare and "RARE " or "") .. "spirit: " .. GC.SpiritName(inst, GC.Slots))
        end
    end

    function GC.RollChoices(slot, n)
        local others = {}
        for s2 in ipairs(GC.Slots) do
            if s2 ~= slot then others[#others + 1] = s2 end
        end
        local pool = {}
        for _, id in ipairs(GC.SpiritOrder) do
            if not GC.SpiritDefs[id].rare and (not GC.SpiritDefs[id].target or #others > 0) then pool[#pool + 1] = id end
        end
        table.Shuffle(pool)
        local out = {}
        for k = 1, math.min(n, #pool) do
            local inst = { id = pool[k] }
            if GC.SpiritDefs[inst.id].target then inst.target = others[math.random(#others)] end
            out[k] = inst
        end
        return out
    end

    function GC.OfferChoice(slot)
        local P = GC.Slots[slot]
        if not P then return end
        P.choiceQueue = (P.choiceQueue or 0) + 1
        GC.NextChoice(slot)
    end

    function GC.NextChoice(slot)
        local P = GC.Slots[slot]
        if not P or GC.Choices[slot] or (P.choiceQueue or 0) <= 0 then return end
        P.choiceQueue = P.choiceQueue - 1
        local opts = GC.RollChoices(slot, 3)
        if #opts == 0 then return end
        if IsValid(P.ply) and not P.ply:IsBot() and not GC.Opts.nospirits then
            GC.Choices[slot] = { opts = opts, deadline = CurTime() + GC.ChoiceTime }
            GC.SendChoice(P.ply)
            SendMsg(P.ply, "Choose a national spirit.")
        else
            GC.GiveSpirit(slot, GC.PickFor(slot, opts))
        end
    end

    function GC.AddWin(slot)
        local P = GC.Slots[slot]
        if not P then return end
        P.wins = (P.wins or 0) + 1
        if P.wins % GC.WinsForChoice == 0 then
            Notify(slot, P.wins .. " battles won.")
            GC.OfferChoice(slot)
        end
    end

    function GC.SendChoice(ply)
        local slot = GC.SlotOf[ply]
        local ch = slot and GC.Choices[slot]
        if not ch or ply:IsBot() then return end
        net.Start("GCapture_Choice")
        net.WriteUInt(math.Clamp(math.ceil(ch.deadline - CurTime()), 0, 127), 7)
        net.WriteUInt(#ch.opts, 2)
        for _, inst in ipairs(ch.opts) do
            net.WriteString(inst.id)
            net.WriteUInt(inst.target or 0, 8)
        end
        net.Send(ply)
    end

    function GC.SendLobby()
        local list = ViewerList()
        local npre = 0
        if (GC.Opts.map or "") ~= "" and GC.CustomMap and GC.CustomMap.pre then npre = math.min(255, #GC.CustomMap.pre) end
        for _, p in ipairs(list) do
            if p:IsBot() then continue end
            net.Start("GCapture_Lobby")
            net.WriteBool(IsHost(p))
            net.WriteUInt(GC.Opts.mode or 0, 2)
            net.WriteBool(GC.Opts.nofog)
            net.WriteUInt(GC.Opts.bots or 0, 6)
            net.WriteUInt(GC.Opts.diff or 1, 3)
            net.WriteUInt(GC.Opts.btype or 0, 2)
            net.WriteUInt(GC.Opts.size or 1, 2)
            net.WriteBool(GC.Opts.observe or false)
            net.WriteString(GC.Opts.seed or "")
            net.WriteString(GC.Opts.map or "")
            net.WriteBool(GC.Opts.noevents or false)
            net.WriteUInt(npre, 8)
            net.WriteBool(GC.Opts.emperor or false)
            for _, k in ipairs(GC.OptFlags) do net.WriteBool(GC.Opts[k] or false) end
            net.WriteUInt(#list, 8)
            for _, q in ipairs(list) do
                net.WriteEntity(q)
                net.WriteString(GC.Names[q] or GC.DefaultName(q))
                local c = GC.Colors[q]
                net.WriteBool(c ~= nil)
                if c then net.WriteUInt(c.r, 8) net.WriteUInt(c.g, 8) net.WriteUInt(c.b, 8) end
            end
            net.Send(p)
        end
    end

    local function WriteArmyFields(A)
        net.WriteUInt(A.id or 0, 16)
        net.WriteUInt(A.owner, 8)
        net.WriteUInt(A.org, 8)
        net.WriteUInt(A.hp, 8)
        net.WriteUInt(A.state, 2)
        net.WriteUInt(A.target or 0, GCIB + 1)
        net.WriteUInt(A.maxOrg, 8)
        net.WriteUInt(A.maxHp, 8)
        local tr = 0
        if A.trainEnd then tr = math.Clamp(math.ceil(A.trainEnd - CurTime()), 0, 127) end
        net.WriteUInt(tr, 7)
        net.WriteBool(A.cav == true)
        net.WriteBool(A.autoId ~= nil)
    end

    local function WriteArmy(A)
        net.WriteUInt(A.cell - 1, GCIB)
        WriteArmyFields(A)
    end

    local function FogOn() return cvFog:GetBool() and not GC.Opts.nofog and not GC.FogSuspend end

    local function ComputeVis(slot)
        local R = GC.FogRange(slot)
        local src = {}
        for i = 1, GCN do
            if GC.owner[i] == slot or GC.ship[i] == slot then src[i] = true end
        end
        local hor = {}
        for y = 0, GCH - 1 do
            for x = 0, GCW - 1 do
                for dx = -R, R do
                    local nx = x + dx
                    if nx >= 0 and nx < GCW and src[y * GCW + nx + 1] then
                        hor[y * GCW + x + 1] = true
                        break
                    end
                end
            end
        end
        local vis = {}
        for y = 0, GCH - 1 do
            for x = 0, GCW - 1 do
                for dy = -R, R do
                    local ny = y + dy
                    if ny >= 0 and ny < GCH and hor[ny * GCW + x + 1] then
                        vis[y * GCW + x + 1] = true
                        break
                    end
                end
            end
        end
        return vis
    end

    local function VisibleFor(ply)
        local slot = GC.SlotOf[ply]
        if not FogOn() or not slot or GC.Dead[slot] then return "all" end
        return ComputeVis(slot)
    end

    local function Sees(v, i)
        local vis = GC.VisOf[v]
        return vis == "all" or (vis ~= nil and vis[i] == true)
    end

    local function CanSee(slot, cell)
        if not FogOn() then return true end
        local P = GC.Slots[slot]
        local vis = P and P.ply and GC.VisOf[P.ply]
        if not vis or vis == "all" then return true end
        return vis[cell] == true
    end

    function GC.SendFull(ply)
        local slot = GC.SlotOf[ply]
        local vis = VisibleFor(ply)
        GC.VisOf[ply] = vis
        local seen
        if vis ~= "all" then
            seen = GC.Seen[slot] or {}
            GC.Seen[slot] = seen
            for i in pairs(vis) do seen[i] = true end
        end

        local parts = {}
        for i = 1, GCN do
            local st = 2
            if vis ~= "all" then st = vis[i] and 2 or (seen[i] and 1 or 0) end
            local b = GC.build[i]

            if b == GC.B_TRAP and slot and GC.owner[i] ~= slot then b = 0 end
            parts[i] = string.char(st)
            parts[GCN + i] = string.char(st >= 1 and GC.biome[i] or 0)
            parts[2 * GCN + i] = string.char(st == 2 and GC.owner[i] or 0)
            parts[3 * GCN + i] = string.char(st == 2 and b or 0)
            parts[4 * GCN + i] = string.char(st == 2 and GC.ship[i] or 0)
            parts[5 * GCN + i] = string.char(st == 2 and (GC.blevel[i] or 0) or 0)
        end
        local comp = util.Compress(table.concat(parts))
        local seq = ((ply.GCFullSeq or 0) + 1) % 256
        ply.GCFullSeq = seq

        net.Start("GCapture_Full")
        net.WriteUInt(GCW, 10)
        net.WriteUInt(GCH, 10)
        net.WriteBool(IsHost(ply))
        net.WriteUInt(#GC.Slots, 8)
        for s, P in ipairs(GC.Slots) do
            net.WriteEntity(P.ply or NULL)
            net.WriteString(P.name)
            net.WriteUInt(math.Round(P.color.r), 8)
            net.WriteUInt(math.Round(P.color.g), 8)
            net.WriteUInt(math.Round(P.color.b), 8)
            net.WriteFloat(P.coins)
            net.WriteFloat(P.pop)
            net.WriteFloat(P.weapons)
            net.WriteString(P.bot and P.bot.d.name or "")
            net.WriteBool(GC.Dead[s] == true)
        end
        WriteSpirits(slot)
        net.WriteUInt(GC.GameId, 16)
        net.WriteBool(vis ~= "all")
        net.WriteUInt(seq, 8)
        net.WriteString(GC.SeedText or "")
        net.WriteBool(GC.Opts.nonight or false)

        local armies = {}
        for _, A in pairs(GC.army) do
            if vis == "all" or vis[A.cell] then armies[#armies + 1] = A end
        end
        net.WriteUInt(#armies, 12)
        for _, A in ipairs(armies) do WriteArmy(A) end
        local oil = {}
        for i in pairs(GC.oilUsed) do oil[#oil + 1] = i end
        net.WriteUInt(#oil, 15)
        for _, i in ipairs(oil) do net.WriteUInt(i - 1, GCIB) end
        net.Send(ply)
        local CH = 30000
        local nCh = math.max(1, math.ceil(#comp / CH))
        for k = 1, nCh do
            timer.Simple((k - 1) * 0.05, function()
                if not IsValid(ply) then return end
                local part = string.sub(comp, (k - 1) * CH + 1, k * CH)
                net.Start("GCapture_FullData")
                net.WriteUInt(seq, 8)
                net.WriteUInt(#part, 16)
                net.WriteData(part, #part)
                net.WriteBool(k == nCh)
                net.Send(ply)
            end)
        end
        GC.SendPacts(ply)
        GC.SendChoice(ply)
        GC.SendAccess(ply)
        if not slot then GC.SendSpecSpirits(ply) end
        GC.SendTime(ply)
    end

    function GC.SendPacts(target)
        local v = target and { target } or ViewerList(true)
        if #v == 0 then return end
        local list, now = {}, CurTime()
        for k, t in pairs(GC.pacts) do
            if t > now then list[#list + 1] = { k, t - now } end
        end
        net.Start("GCapture_Pacts")
        net.WriteUInt(#list, 8)
        for _, e in ipairs(list) do
            net.WriteUInt(math.floor(e[1] / 256), 8)
            net.WriteUInt(e[1] % 256, 8)
            net.WriteUInt(math.Clamp(math.ceil(e[2]), 1, 127), 7)
        end
        net.Send(v)
    end

    local function SendVis(v, slot, newCells, hidCells)
        local CH, a, b = 2500, 1, 1
        repeat
            local nn, hh = {}, {}
            for k = a, math.min(#newCells, a + CH - 1) do nn[#nn + 1] = newCells[k] end
            for k = b, math.min(#hidCells, b + CH - 1) do hh[#hh + 1] = hidCells[k] end
            a, b = a + CH, b + CH

            net.Start("GCapture_Vis")
            net.WriteUInt(#nn, 15)
            for _, i in ipairs(nn) do
                local bl = GC.build[i]
                if bl == GC.B_TRAP and GC.SlotOf[v] and GC.owner[i] ~= slot then bl = 0 end
                net.WriteUInt(i - 1, GCIB)
                net.WriteUInt(GC.biome[i], 3)
                net.WriteUInt(GC.owner[i], 8)
                net.WriteUInt(bl, GC.BuildBits)
                net.WriteUInt(GC.blevel[i] or 0, 2)
                net.WriteUInt(GC.ship[i], 8)
                local A = GC.army[i]
                net.WriteBool(A ~= nil)
                if A then WriteArmyFields(A) end
            end
            net.WriteUInt(#hh, 15)
            for _, i in ipairs(hh) do net.WriteUInt(i - 1, GCIB) end
            net.Send(v)
        until a > #newCells and b > #hidCells
    end

    function GC.SendStats()
        local v = ViewerList(true)
        if #v == 0 then return end
        net.Start("GCapture_Stats")
        net.WriteUInt(#GC.Slots, 8)
        for s, P in ipairs(GC.Slots) do
            net.WriteFloat(P.coins)
            net.WriteFloat(P.pop)
            net.WriteFloat(P.weapons)
            net.WriteBool(GC.Dead[s] == true)
            local d, dv, rem = GC.disc[s], 0, 0
            if d and CurTime() < d.t then dv, rem = d.n * GC.DiscontentPer, d.t - CurTime() end
            net.WriteFloat(dv)
            net.WriteFloat(rem)
        end
        net.Send(v)
    end

    function GC.SendWin(target)
        local v = target and { target } or ViewerList(true)
        if #v == 0 then return end
        local P = GC.Winner and GC.Slots[GC.Winner]
        net.Start("GCapture_Win")
        net.WriteBool(P ~= nil)
        if P then
            net.WriteString(P.name)
            net.WriteUInt(math.Round(P.color.r), 8)
            net.WriteUInt(math.Round(P.color.g), 8)
            net.WriteUInt(math.Round(P.color.b), 8)
        end
        net.Send(v)
    end

    function GC.DiscontentOf(slot)
        local d = GC.disc[slot]
        if not d or CurTime() >= d.t then return 0 end
        return d.n * GC.DiscontentPer
    end

    function GC.AddDiscontent(slot, n)
        if GC.State ~= "playing" or not slot or slot == 0 or not GC.Slots[slot] or GC.Dead[slot] then return end
        local now = CurTime()
        local d = GC.disc[slot]
        if not d or now >= d.t then d = { n = 0 } GC.disc[slot] = d end
        d.n, d.t, d.msg = d.n + (n or 1), now + GC.DiscontentTime, true
    end

    function GC.SetCell(i, o, b, lvl)
        local prev, prevLvl = GC.build[i], GC.blevel[i]
        local prevOwner = GC.owner[i]
        if prevOwner ~= 0 and prevOwner ~= o and not GC.noDiscontent then GC.AddDiscontent(prevOwner) end
        GC.owner[i], GC.build[i] = o, b
        hook.Run("GCapture_CellChanged", i, prevOwner, o, prev, b)
        if b == GC.B_BARRICADE then
            GC.blevel[i] = lvl or (prev == GC.B_BARRICADE and prevLvl) or 1
        else
            GC.blevel[i] = 0
        end
        if b ~= GC.B_OIL and b ~= GC.B_FIRE and not (GC.Build[b] and GC.Build[b].lifetime) then GC.expire[i] = nil end
        for _, v in ipairs(ViewerList(true)) do
            if Sees(v, i) then
                local vb = b
                if b == GC.B_TRAP and GC.SlotOf[v] and GC.SlotOf[v] ~= o then vb = 0 end
                net.Start("GCapture_Cell")
                net.WriteUInt(i - 1, GCIB)
                net.WriteUInt(o, 8)
                net.WriteUInt(vb, GC.BuildBits)
                net.WriteUInt(GC.blevel[i], 2)
                net.Send(v)
            end
        end
    end

    function GC.SetShip(i, s)
        if s == 0 and GC.shipOrd then GC.shipOrd[i] = nil end
        GC.ship[i] = s
        for _, v in ipairs(ViewerList(true)) do
            if Sees(v, i) then
                net.Start("GCapture_Ship")
                net.WriteUInt(i - 1, GCIB)
                net.WriteUInt(s, 8)
                net.Send(v)
            end
        end
    end

    function GC.Place(i, slot, id)
        GC.SetCell(i, slot, id)
        if id == GC.B_OIL then

            if not GC.oilUsed[i] then
                GC.oilUsed[i] = true
                local v = ViewerList(true)
                if #v > 0 then
                    net.Start("GCapture_Oil")
                    net.WriteUInt(i - 1, GCIB)
                    net.Send(v)
                end
            end
            GC.expire[i] = CurTime() + math.max(1, GC.Build[GC.B_OIL].lifetime + GC.Mod(slot, "oilLife"))
        elseif id == GC.B_FIRE then
            GC.expire[i] = CurTime() + GC.FireTime
        elseif GC.Build[id] and GC.Build[id].lifetime then
            GC.expire[i] = CurTime() + GC.Build[id].lifetime
        end
        hook.Run("GCapture_Placed", i, slot, id)
    end

    function GC.BombCell(idx, owner)
        local bl = GC.build[idx]
        if bl == GC.B_CRATER then return end
        local lvl = GC.blevel[idx] or 1
        if bl == GC.B_BARRICADE and lvl > 1 then
            GC.SetCell(idx, owner, bl, lvl - 1)
        else
            GC.Place(idx, owner, GC.B_FIRE)
        end
    end

    function GC.SendArmy(A)
        for _, v in ipairs(ViewerList(true)) do
            if Sees(v, A.cell) then
                net.Start("GCapture_Army")
                net.WriteBool(true)
                WriteArmy(A)
                net.Send(v)
            end
        end
    end

    function GC.SendArmyGone(cell)
        for _, v in ipairs(ViewerList(true)) do
            if Sees(v, cell) then
                net.Start("GCapture_Army")
                net.WriteBool(false)
                net.WriteUInt(cell - 1, GCIB)
                net.Send(v)
            end
        end
    end

    local armyIdCounter = 0
    local function NextArmyId()
        armyIdCounter = armyIdCounter % 65535 + 1
        return armyIdCounter
    end

    local function IsTraining(A)
        return A.trainEnd ~= nil and CurTime() < A.trainEnd
    end

    local function CreateArmy(slot, cell, noTrain, cav)
        local mo, mh = GC.MaxOrg(slot, cav), GC.MaxHP(slot, cav)
        local A = {
            id = NextArmyId(), owner = slot, cell = cell, org = mo, hp = mh, maxOrg = mo, maxHp = mh,
            state = GC.ST_IDLE, target = 0, foe = nil, attackers = {}, claim = false,
            nextMove = 0, nextRegen = CurTime() + 1, nextRound = 0, captureAt = 0, nextBorder = 0,
            cav = cav or nil,
            trainEnd = (not noTrain) and (CurTime() + GC.TrainTime(slot, cav)) or nil,
        }
        GC.army[cell] = A
        GC.SendArmy(A)
        return A
    end

    local function Detach(A)
        local D = A.foe
        A.foe = nil
        if not D then return end
        for k, x in ipairs(D.attackers) do
            if x == A then table.remove(D.attackers, k) break end
        end
        if #D.attackers == 0 and not D.dead then
            D.state, D.target = GC.ST_IDLE, 0
            GC.SendArmy(D)
        end
    end

    local function EndAllBattles(D)
        local atks = D.attackers
        D.attackers = {}
        D.state, D.target = GC.ST_IDLE, 0
        for _, x in ipairs(atks) do
            x.foe, x.state, x.target, x.claim = nil, GC.ST_IDLE, 0, false
            GC.SendArmy(x)
        end
    end

    local function RemoveArmy(A)
        if A.dead then return end
        A.dead = true
        if GC.army[A.cell] == A then GC.army[A.cell] = nil end
        GC.SendArmyGone(A.cell)
        Detach(A)
        local atks = A.attackers
        A.attackers = {}
        for _, x in ipairs(atks) do
            x.foe, x.state, x.target, x.claim = nil, GC.ST_IDLE, 0, false
            GC.SendArmy(x)
        end
    end

    function GC.BombArmy(ca)
        ca.hp = ca.hp - math.random(GC.BombHP[1], GC.BombHP[2])
        ca.org = math.max(0, ca.org - math.random(GC.BombOrg[1], GC.BombOrg[2]))
        if ca.hp <= 0 then
            RemoveArmy(ca)
            Notify(ca.owner, "Bombing destroyed your army.")
            return true
        end
        GC.SendArmy(ca)
        return false
    end

    local function RawMoveArmy(A, to)
        if GC.army[A.cell] == A then GC.army[A.cell] = nil end
        GC.SendArmyGone(A.cell)
        A.cell = to
        GC.army[to] = A
        GC.SendArmy(A)
    end

    local function MoveArmy(A, to)
        RawMoveArmy(A, to)
        A.org = math.max(0, A.org - 1)
        A.nextMove = CurTime() + C.MoveCooldown * GC.MoveMult(A.owner, to, A.cav)
        GC.SendArmy(A)
    end

    local function CancelAttack(A)
        Detach(A)
        A.state, A.target, A.claim = GC.ST_IDLE, 0, false
        GC.SendArmy(A)
    end

    local function FindRetreat(D)
        local own = {}
        for _, j in ipairs(GC.Neighbors8(D.cell)) do
            if not GC.Biomes[GC.biome[j]].water and GC.build[j] ~= GC.B_CRATER and not GC.army[j] and GC.owner[j] == D.owner then
                own[#own + 1] = j
            end
        end
        if #own == 0 then return nil end
        return own[math.random(#own)]
    end

    local function NearestEnemy(A)
        local ax, ay = XY(A.cell)
        local best, bd
        for _, E in pairs(GC.army) do
            if E.owner ~= A.owner and not E.dead and CanSee(A.owner, E.cell) then
                local ex, ey = XY(E.cell)
                local d = (ex - ax) ^ 2 + (ey - ay) ^ 2
                if not bd or d < bd then best, bd = E, d end
            end
        end
        return best
    end

    local function BorderStep(A)
        local E = NearestEnemy(A)
        if not E then return false end
        local slot, from = A.owner, A.cell
        local ex, ey = XY(E.cell)

        local dist, prev = { [from] = 0 }, {}
        local queue, qh = { from }, 1
        while qh <= #queue do
            local c = queue[qh]
            qh = qh + 1
            for _, j in ipairs(GC.Neighbors8(c)) do
                if dist[j] == nil and not GC.Biomes[GC.biome[j]].water and GC.build[j] ~= GC.B_CRATER and GC.owner[j] == slot and not GC.army[j] then
                    dist[j] = dist[c] + 1
                    prev[j] = c
                    queue[#queue + 1] = j
                end
            end
        end

        local goal, gd, gp
        for c, d in pairs(dist) do
            local x, y = XY(c)
            local dd = (x - ex) ^ 2 + (y - ey) ^ 2
            if not gd or dd < gd or (dd == gd and d < gp) then goal, gd, gp = c, dd, d end
        end
        if not goal or goal == from then return false end

        local step = goal
        while prev[step] ~= from do step = prev[step] end
        RawMoveArmy(A, step)
        A.nextBorder = CurTime() + C.BorderStep * GC.MoveMult(A.owner, step, A.cav)
        A.org = math.max(0, A.org - C.BorderOrgCost)
        GC.SendArmy(A)
        return true
    end

    local function TransferAll(from, to)
        GC.noDiscontent = true
        for i = 1, GCN do
            if GC.owner[i] == from then
                local b = GC.build[i]
                if b == GC.B_CAPITAL or b == GC.B_TRAP then b = 0 end
                GC.SetCell(i, to, b)
            end
            if GC.ship[i] == from then GC.SetShip(i, to) end
        end
        GC.noDiscontent = nil
        local doomed = {}
        for _, A in pairs(GC.army) do
            if A.owner == from then doomed[#doomed + 1] = A end
        end
        for _, A in ipairs(doomed) do RemoveArmy(A) end
    end

    local function ResolveAttack(A, cell)
        A.state, A.target, A.foe, A.claim = GC.ST_IDLE, 0, nil, false
        local slot = A.owner
        local P = GC.Slots[slot]
        local o, bl = GC.owner[cell], GC.build[cell]

        if o == slot then GC.SendArmy(A) return end

        if bl == GC.B_BARRICADE then

            local lvl = GC.blevel[cell] or 1
            if lvl > 1 then GC.SetCell(cell, o, bl, lvl - 1) else GC.SetCell(cell, o, 0) end
            GC.SendArmy(A)
        elseif bl == GC.B_TRAP then
            GC.SetCell(cell, o, 0)
            P.pop = math.max(0, P.pop - GC.TrapPenalty)
            Notify(slot, "You hit a trap! -" .. GC.TrapPenalty .. " population")
            Notify(o, "Your trap was triggered by " .. P.name .. "!")
            GC.SendArmy(A)
            GC.SendStats()
        else
            if bl == GC.B_CAPITAL then
                Notify(o, P.name .. " captured your capital. You lost.")
                TransferAll(o, slot)
            else
                GC.SetCell(cell, slot, bl)
            end
            if not A.dead then
                if bl == GC.B_CRATER then GC.SendArmy(A) else MoveArmy(A, cell) end
            end
        end
    end

    local function Rout(D, A, forced)
        local cell = D.cell
        if forced then D.hp = D.hp - 1 end
        local dest = (D.hp > 0) and FindRetreat(D) or nil
        EndAllBattles(D)
        if D.hp <= 0 then
            RemoveArmy(D)
            Notify(D.owner, "Your army was destroyed.")
        elseif not dest then
            RemoveArmy(D)
            Notify(D.owner, "Your army was encircled and destroyed.")
        else
            RawMoveArmy(D, dest)
        end
        ResolveAttack(A, cell)
    end

    local function StartBattle(A, D)
        D.claim = false
        A.state, A.foe, A.target = GC.ST_ATTACK, D, D.cell
        D.attackers[#D.attackers + 1] = A
        D.state, D.target = GC.ST_DEFENSE, 0
        A.nextRound = CurTime() + 1
        GC.SendArmy(A)
        GC.SendArmy(D)
        if #D.attackers == 1 then Notify(D.owner, "Your army is under attack.") end
    end

    local function CoastAlert(A, to)
        local D = GC.army[to]
        local eo = (D and D.owner) or GC.owner[to]
        if not eo or eo == 0 or eo == A.owner then return end
        if not GC.CoastGuardNear(to, eo) then return end
        local P = GC.Slots[eo]
        if not P or not IsValid(P.ply) or P.ply:IsBot() then return end
        net.Start("GCapture_Snd")
        net.WriteUInt(to - 1, GCIB)
        net.WriteUInt(5, 3)
        net.Send(P.ply)
        Notify(eo, "Coast Guard: enemy landing.")
    end

    local function StartAttack(A, to)
        if A.state ~= GC.ST_IDLE then return false, "The army is busy!" end
        if IsTraining(A) then return false, "The army is still training." end
        if A.org < 1 then return false, "No organization. The army can't attack." end
        local eo = (GC.army[to] and GC.army[to].owner) or GC.owner[to]
        if eo and eo ~= 0 and eo ~= A.owner and GC.HasPact(A.owner, eo) then
            return false, "Non-aggression pact in effect."
        end

        local aboard = GC.Biomes[GC.biome[A.cell]].water
        local ok
        if aboard then ok = GC.CanArmyLand(A.owner, A.cell, to) else ok = GC.CanArmyAttack(A.owner, A.cell, to) end
        if not ok then
            return false, "Target must be within 3x3 of the army."
        end
        if aboard then CoastAlert(A, to) end

        local D = GC.army[to]
        if D then
            if D.state == GC.ST_ATTACK and D.foe then return false, "That army is already fighting." end
            if D.state == GC.ST_ATTACK then
                D.state, D.target, D.claim = GC.ST_IDLE, 0, false
            end
            StartBattle(A, D)
        else
            A.state, A.target, A.foe = GC.ST_ATTACK, to, nil
            A.claim = (GC.owner[to] == 0)
            A.captureAt = CurTime() + C.CaptureDelay
            GC.SendArmy(A)
        end
        return true
    end

    local function StartBorder(A)
        if not NearestEnemy(A) then return false, "No visible enemy armies." end
        A.state, A.target = GC.ST_BORDER, 0
        A.nextBorder = 0
        GC.SendArmy(A)
        return true
    end

    local function Snd(A, kind)
        local P = GC.Slots[A.owner]
        if not P or not IsValid(P.ply) or P.ply:IsBot() then return end
        net.Start("GCapture_Snd")
        net.WriteUInt(A.cell - 1, GCIB)
        net.WriteUInt(kind, 3)
        net.Send(P.ply)
    end

    local function BattleRound(A)
        local D = A.foe
        if not D or D.dead then return CancelAttack(A) end

        local ab, db = GC.biome[A.cell], GC.biome[D.cell]
        local ac = C.AttackChance + GC.AttackMods(A.owner, A.cav, ab, D.owner) + (ab == GC.TUNDRA and C.TundraAttack or 0)
        local dc = C.DefenseChance + GC.DefenseMods(D.owner, D.cav, db) + (db == GC.TUNDRA and C.TundraDefense or 0)
        ac = ac + GC.NightAtk()

        local function Odds(owner, isAtt, pct)
            local P = GC.Slots[owner]
            if not P or not IsValid(P.ply) or P.ply:IsBot() then return end
            net.Start("GCapture_Odds")
            net.WriteUInt(A.cell - 1, GCIB)
            net.WriteUInt(D.cell - 1, GCIB)
            net.WriteBool(isAtt)
            net.WriteUInt(math.Clamp(math.Round(pct * 100), 0, 100), 7)
            net.Send(P.ply)
        end
        Odds(A.owner, true, dc)
        Odds(D.owner, false, ac)

        if math.random() < ac then
            D.org = math.max(0, D.org - 1)
            Snd(A, 1)
            Snd(D, 3)
        else
            A.org = math.max(0, A.org - 1)
            Snd(A, 3)
        end
        if math.random() < dc then
            A.org = math.max(0, A.org - 1)
            Snd(D, 2)
            Snd(A, 3)
        end

        if D.org <= 0 then
            GC.AddWin(A.owner)
            Rout(D, A, true)
        elseif A.org <= 0 then
            CancelAttack(A)
            GC.AddWin(D.owner)
            Notify(A.owner, "Your army ran out of organization and stopped.")
        else
            GC.SendArmy(A)
            GC.SendArmy(D)
        end
    end

    local function AutoPath(A, E)
        local from, isN = A.cell, {}
        for _, j in ipairs(GC.Neighbors8(E.cell)) do isN[j] = true end
        if isN[from] then return from, nil end
        local prev, q, h = { [from] = false }, { from }, 1
        while h <= #q do
            local c = q[h]
            h = h + 1
            for _, j in ipairs(GC.Neighbors8(c)) do
                if prev[j] == nil and not GC.Biomes[GC.biome[j]].water and GC.build[j] ~= GC.B_CRATER and GC.owner[j] == A.owner and not GC.army[j] then
                    prev[j] = c
                    if isN[j] then
                        local st = j
                        while prev[st] ~= from do st = prev[st] end
                        return j, st
                    end
                    q[#q + 1] = j
                end
            end
        end
    end

    local function StartAuto(A)
        local slot = A.owner
        local reach, q, h = { [A.cell] = true }, { A.cell }, 1
        while h <= #q do
            local c = q[h]
            h = h + 1
            for _, j in ipairs(GC.Neighbors8(c)) do
                if not reach[j] and not GC.Biomes[GC.biome[j]].water and GC.build[j] ~= GC.B_CRATER and GC.owner[j] == slot and not GC.army[j] then
                    reach[j] = true
                    q[#q + 1] = j
                end
            end
        end
        local caps = {}
        for i = 1, GCN do
            if GC.build[i] == GC.B_CAPITAL and GC.owner[i] ~= 0 then caps[GC.owner[i]] = i end
        end
        local cands, total = {}, 0
        for _, E in pairs(GC.army) do
            if E.owner ~= slot and not E.dead and not GC.Biomes[GC.biome[E.cell]].water and CanSee(slot, E.cell)
                and not GC.HasPact(slot, E.owner) and not (E.state == GC.ST_ATTACK and E.foe) then
                local ok = false
                for _, j in ipairs(GC.Neighbors8(E.cell)) do
                    if reach[j] then ok = true break end
                end
                if ok then
                    local d, cp = 0, caps[E.owner]
                    if cp then
                        local ex, ey = XY(E.cell)
                        local cx, cy = XY(cp)
                        d = math.max(math.abs(ex - cx), math.abs(ey - cy))
                    end
                    local w = 1 / (1 + d) ^ 1.5
                    total = total + w
                    cands[#cands + 1] = { E, w }
                end
            end
        end
        if #cands == 0 then return false, "No reachable enemy army." end
        local r, pick = math.random() * total, cands[1][1]
        for _, c in ipairs(cands) do
            r = r - c[2]
            if r <= 0 then pick = c[1] break end
        end
        A.autoId, A.autoEnd, A.route = pick.id, CurTime() + 90, nil
        GC.SendArmy(A)
        local OP = GC.Slots[pick.owner]
        Notify(slot, "Auto Attack: target chosen (" .. (OP and OP.name or "?") .. ")")
        return true
    end

    local function AutoStep(A)
        local now = CurTime()
        local function Stop(msg)
            A.autoId = nil
            GC.SendArmy(A)
            if msg then Notify(A.owner, msg) end
        end
        local E
        for _, x in pairs(GC.army) do
            if x.id == A.autoId then E = x break end
        end
        if not E or E.dead or E.owner == A.owner or GC.HasPact(A.owner, E.owner) or now > (A.autoEnd or 0) then
            return Stop("Auto Attack: target lost.")
        end
        if A.org < 1 then return Stop("Auto Attack cancelled: no organization.") end
        if IsTraining(A) or now < A.nextMove then return end
        local goal, step = AutoPath(A, E)
        if not goal then return Stop("Auto Attack: target unreachable.") end
        if not step then
            A.autoId = nil
            local ok, msg = StartAttack(A, E.cell)
            if not ok then Notify(A.owner, "Auto Attack: " .. (msg or "failed")) end
            GC.SendArmy(A)
            return
        end
        MoveArmy(A, step)
    end

    GC.ShipStep = 0.8

    function GC.SetShipOrder(slot, cell, dest)
        GC.shipOrd[cell] = { slot = slot, dest = dest, nextT = 0 }
    end

    local function LandSpots(slot, target, selfCell, bad)
        local used = {}
        for c, o in pairs(GC.shipOrd) do
            if c ~= selfCell and o.slot == slot and o.spot then used[o.spot] = true end
        end
        local cand = { target }
        for _, j in ipairs(GC.Neighbors8(target)) do cand[#cand + 1] = j end
        local list = {}
        for _, c in ipairs(cand) do
            if not used[c] and not (bad and bad[c]) and GC.biome[c] ~= GC.WATER and GC.build[c] ~= GC.B_CRATER then
                local D = GC.army[c]
                local eo = D and D.owner or GC.owner[c]
                if not (D and D.owner == slot)
                    and not (eo ~= 0 and eo ~= slot and (GC.HasPact(slot, eo) or GC.AccessTie(slot, eo))) then
                    list[#list + 1] = c
                end
            end
        end
        return list
    end

    local function WaterStep(from, goals)
        if goals[from] then return nil, true end
        local prev, q, h = { [from] = false }, { from }, 1
        while h <= #q do
            local c = q[h]
            h = h + 1
            for _, j in ipairs(GC.Neighbors(c)) do
                if prev[j] == nil and GC.biome[j] == GC.WATER and GC.ship[j] == 0 then
                    prev[j] = c
                    if goals[j] then
                        local st = j
                        while prev[st] ~= from do st = prev[st] end
                        return st, false
                    end
                    q[#q + 1] = j
                end
            end
        end
        return nil, false
    end

    local function ShipThink(now)
        local list = {}
        for c, o in pairs(GC.shipOrd or {}) do list[#list + 1] = { c, o } end
        for _, e in ipairs(list) do
            local cell, o = e[1], e[2]
            if GC.shipOrd[cell] ~= o then continue end
            if GC.ship[cell] ~= o.slot then GC.shipOrd[cell] = nil continue end
            if now < o.nextT then continue end
            local slot, dest = o.slot, o.dest
            local A = GC.army[cell]
            if A and A.state ~= GC.ST_IDLE then o.nextT = now + 0.5 continue end
            local goals, spot = {}, nil
            local land = GC.biome[dest] ~= GC.WATER
            if not land then
                if dest == cell or GC.ship[dest] == 0 then goals[dest] = true
                else
                    for _, j in ipairs(GC.Neighbors8(dest)) do
                        if GC.biome[j] == GC.WATER and GC.ship[j] == 0 then goals[j] = true end
                    end
                end
            else
                if A then
                    local spots = LandSpots(slot, dest, cell, o.bad)
                    if not table.HasValue(spots, o.spot) then
                        o.spot = nil
                        local sx, sy = XY(cell)
                        local bd
                        for _, c in ipairs(spots) do
                            local x, y = XY(c)
                            local d = (x - sx) ^ 2 + (y - sy) ^ 2
                            if not bd or d < bd then o.spot, bd = c, d end
                        end
                    end
                    spot = o.spot
                else
                    spot = dest
                end
                if not spot then
                    Notify(slot, "Ship order cancelled: no free landing cell.")
                    GC.shipOrd[cell] = nil
                    continue
                end
                for _, j in ipairs(GC.Neighbors8(spot)) do
                    if GC.biome[j] == GC.WATER and (GC.ship[j] == 0 or j == cell) then goals[j] = true end
                end
            end
            if next(goals) == nil then GC.shipOrd[cell] = nil continue end
            local nxt, arrived = WaterStep(cell, goals)
            if arrived then
                if A and land then
                    if GC.CanArmyLand(slot, cell, spot) then
                        if not GC.army[spot] and (GC.owner[spot] == slot or GC.HasAccess(slot, GC.owner[spot])) then
                            if now >= A.nextMove then MoveArmy(A, spot) GC.shipOrd[cell] = nil
                            else o.nextT = now + 0.3 end
                        else
                            local ok = StartAttack(A, spot)
                            if ok then GC.shipOrd[cell] = nil
                            else
                                o.fail = (o.fail or 0) + 1
                                if o.fail > 15 then GC.shipOrd[cell] = nil else o.nextT = now + 1 end
                            end
                        end
                    else
                        o.bad = o.bad or {}
                        o.bad[spot] = true
                        o.spot = nil
                        o.fail = (o.fail or 0) + 1
                        if o.fail > 15 then GC.shipOrd[cell] = nil else o.nextT = now + 0.3 end
                    end
                else GC.shipOrd[cell] = nil end
            elseif nxt then
                GC.SetShip(cell, 0)
                GC.SetShip(nxt, slot)
                if A then RawMoveArmy(A, nxt) end
                GC.shipOrd[nxt] = o
                o.nextT = now + GC.ShipStep
            else
                o.fail = (o.fail or 0) + 1
                if o.fail > 10 then GC.shipOrd[cell] = nil else o.nextT = now + 1 end
            end
        end
    end

    local function ArmyThink()
        if GC.State ~= "playing" then return end
        local now = CurTime()
        ShipThink(now)

        for i, t in pairs(GC.expire) do
            if now >= t then
                GC.expire[i] = nil
                local b = GC.build[i]
                if b == GC.B_OIL or b == GC.B_FIRE or (GC.Build[b] and GC.Build[b].lifetime) then GC.SetCell(i, GC.owner[i], 0) end
            end
        end

        local list = {}
        for _, A in pairs(GC.army) do list[#list + 1] = A end

        for _, A in ipairs(list) do
            if A.dead then continue end

            if A.trainEnd and now >= A.trainEnd then
                A.trainEnd = nil
                GC.SendArmy(A)
            end

            if A.state == GC.ST_IDLE then
                if A.autoId then AutoStep(A) end
                if A.route and #A.route > 0 and now >= (A.nextRoute or 0) then
                    if A.org < 1 then
                        A.route = nil
                        Notify(A.owner, "Route cancelled: no organization.")
                    else
                        local step = table.remove(A.route, 1)
                        if step and GC.CanStand(A.owner, step) and not GC.army[step] then
                            MoveArmy(A, step)
                            A.nextRoute = A.nextMove
                        else
                            A.route = nil
                            Notify(A.owner, "Route cancelled: path blocked.")
                        end
                        if A.route and #A.route == 0 then A.route = nil end
                    end
                end
                if now >= A.nextRegen then
                    A.nextRegen = now + 1
                    local changed = false

                    local mo, mh = GC.MaxOrg(A.owner, A.cav), GC.MaxHP(A.owner, A.cav)
                    if mo ~= A.maxOrg or mh ~= A.maxHp then
                        A.maxOrg, A.maxHp = mo, mh
                        A.org, A.hp = math.min(A.org, mo), math.min(A.hp, mh)
                        changed = true
                    end

                    if A.org < A.maxOrg and GC.InSupply(A.owner, A.cell) then
                        A.org, changed = A.org + 1, true
                    end
                    if changed then GC.SendArmy(A) end
                end
            elseif A.state == GC.ST_BORDER then
                if now >= A.nextBorder then
                    A.nextBorder = now + C.BorderStep
                    if not BorderStep(A) then
                        A.state = GC.ST_IDLE
                        GC.SendArmy(A)
                        Notify(A.owner, "The army stopped: border reached or no path.")
                    end
                end
            elseif A.state == GC.ST_ATTACK then
                if A.foe then
                    if now >= A.nextRound then
                        A.nextRound = now + 1
                        BattleRound(A)
                    end
                elseif now >= A.captureAt then
                    local t = A.target
                    local D = GC.army[t]
                    if D and D.owner ~= A.owner then
                        if (D.state == GC.ST_ATTACK and D.foe) or GC.HasPact(A.owner, D.owner) then
                            CancelAttack(A)
                        else
                            if D.state == GC.ST_ATTACK then D.state, D.target, D.claim = GC.ST_IDLE, 0, false end
                            StartBattle(A, D)
                        end
                    elseif GC.owner[t] == A.owner then
                        CancelAttack(A)
                    elseif GC.owner[t] ~= 0 and GC.HasPact(A.owner, GC.owner[t]) then
                        CancelAttack(A)
                    elseif GC.owner[t] == 0 and not A.claim then
                        CancelAttack(A)
                    else
                        ResolveAttack(A, t)
                    end
                end
            end
        end
        GC.CheckWin()
    end
    timer.Create("GCapture_Army", 0.1, 0, ArmyThink)

    local function FogThink()
        if GC.State ~= "playing" or not FogOn() then return end
        for _, v in ipairs(ViewerList(true)) do
            local slot, old = GC.SlotOf[v], GC.VisOf[v]
            if slot and old and old ~= "all" then
                local new = ComputeVis(slot)
                local newCells, hidCells = {}, {}
                for i in pairs(new) do if not old[i] then newCells[#newCells + 1] = i end end
                for i in pairs(old) do if not new[i] then hidCells[#hidCells + 1] = i end end
                if #newCells > 0 or #hidCells > 0 then
                    SendVis(v, slot, newCells, hidCells)
                    local seen = GC.Seen[slot] or {}
                    GC.Seen[slot] = seen
                    for i in pairs(new) do seen[i] = true end
                    GC.VisOf[v] = new
                end
            end
        end
    end
    timer.Create("GCapture_Fog", 0.25, 0, FogThink)

    cvars.AddChangeCallback("sv_gc_fog", function()
        timer.Simple(0, function()
            if GC.State == "lobby" then return end
            for _, p in ipairs(ViewerList(true)) do GC.SendFull(p) end
        end)
    end, "GCapture_Fog")

    GC.RecFlag = GC.RecFlag or {}
    GC.Rec = nil

    net.Receive("GCapture_Rec", function(_, ply)
        GC.RecFlag[ply] = net.ReadBool() or nil
    end)

    local function RecFrame(R)
        local L, f, c, s = R.last, {}, {}, {}
        for i = 1, GCN do
            local o, b, l = GC.owner[i], GC.build[i], GC.blevel[i] or 0
            if o ~= L.o[i] or b ~= L.b[i] or l ~= L.l[i] then
                c[#c + 1], c[#c + 2], c[#c + 3], c[#c + 4] = i, o, b, l
                L.o[i], L.b[i], L.l[i] = o, b, l
            end
            local sh = GC.ship[i]
            if sh ~= L.s[i] then
                s[#s + 1], s[#s + 2] = i, sh
                L.s[i] = sh
            end
        end
        if #c > 0 then f.c = c end
        if #s > 0 then f.s = s end

        local list = {}
        for cell, A in pairs(GC.army) do list[#list + 1] = { cell = cell, A = A } end
        table.sort(list, function(x, y) return x.cell < y.cell end)
        local a = {}
        for _, entry in ipairs(list) do
            local cell, A = entry.cell, entry.A
            a[#a + 1], a[#a + 2], a[#a + 3], a[#a + 4], a[#a + 5] = cell, A.id or 0, A.owner, A.org, A.hp
            a[#a + 1], a[#a + 2], a[#a + 3], a[#a + 4], a[#a + 5] = A.state, A.target or 0, A.maxOrg, A.maxHp, A.cav and 1 or 0
        end
        local key = table.concat(a, ",")
        if key ~= R.akey then f.a, R.akey = a, key end

        local r = {}
        for _, P in ipairs(GC.Slots) do
            r[#r + 1], r[#r + 2], r[#r + 3] = math.Round(P.coins, 1), math.floor(P.pop), math.floor(P.weapons)
        end
        f.r = r
        local sp, parts = {}, {}
        for s, P in ipairs(GC.Slots) do
            local l = {}
            for _, inst in ipairs(P.spirits or {}) do l[#l + 1] = inst.id .. ":" .. (inst.target or 0) end
            sp[s] = l
            parts[s] = table.concat(l, ",")
        end
        local skey = table.concat(parts, "|")
        if skey ~= R.spkey then f.sp, R.spkey = sp, skey end
        if R.ev then f.e, R.ev = R.ev, nil end
        if R.bm then f.bm, R.bm = R.bm, nil end
        if R.evt then f.ev, R.evt = R.evt, nil end
        R.frames[#R.frames + 1] = f
    end

    function GC.StartRec(list)
        GC.Rec = nil
        local targets = {}
        for _, p in ipairs(ViewerList(true)) do
            if GC.RecFlag[p] and not p:IsBot() then targets[#targets + 1] = p end
        end
        if #targets == 0 then return end

        local pl, biome = {}, {}
        for s, P in ipairs(GC.Slots) do
            pl[s] = { P.name, math.Round(P.color.r), math.Round(P.color.g), math.Round(P.color.b), P.bot and P.bot.d.name or "" }
        end
        local L = { o = {}, b = {}, l = {}, s = {} }
        for i = 1, GCN do
            biome[i] = GC.biome[i]
            L.o[i], L.b[i], L.l[i], L.s[i] = 0, 0, 0, 0
        end
        GC.Rec = { targets = targets, players = pl, biome = biome, frames = {}, last = L }
        RecFrame(GC.Rec)
    end

    timer.Create("GCapture_Rec", 1, 0, function()
        if GC.Rec and GC.State == "playing" then RecFrame(GC.Rec) end
    end)

    function GC.FinishRec()
        local R = GC.Rec
        if not R then return end
        GC.Rec = nil
        RecFrame(R)

        local bs = {}
        for i = 1, GCW * GCH do bs[i] = string.char(48 + (R.biome[i] or 5)) end
        local json = util.TableToJSON({ v = 2, w = GCW, h = GCH, bs = table.concat(bs), seed = GC.SeedText or "", players = R.players, frames = R.frames })
        if not json then return end
        local data = util.Compress(json)
        local crc = util.CRC(data)

        local dur = #R.frames - 1
        local WP = GC.Winner and GC.Slots[GC.Winner]
        local wname = WP and WP.name or "-"
        local names = {}
        for _, p in ipairs(R.players) do names[#names + 1] = p[1] end
        local plist = table.concat(names, ", ")

        local CH = 30000
        local n = math.max(1, math.ceil(#data / CH))
        for k = 1, n do
            timer.Simple((k - 1) * 0.1, function()
                local part = string.sub(data, (k - 1) * CH + 1, k * CH)
                for _, p in ipairs(R.targets) do
                    if IsValid(p) then
                        net.Start("GCapture_DemoSend")
                        net.WriteBool(k == 1)
                        if k == 1 then
                            net.WriteUInt(dur, 32)
                            net.WriteUInt(os.time(), 32)
                            net.WriteString(wname)
                            net.WriteString(string.sub(plist, 1, 2000))
                            net.WriteUInt(#data, 32)
                            net.WriteString(crc)
                        end
                        net.WriteUInt(#part, 16)
                        net.WriteData(part, #part)
                        net.WriteBool(k == n)
                        net.Send(p)
                    end
                end
            end)
        end
    end

    local function ResetToLobby()
        timer.Remove("GCapture_EndReset")
        timer.Remove("GCapture_Deploy")
        GC.Deploy = nil
        GC.State = "lobby"
        GC.nextEvent = nil
        GC.EventBusy, GC.FogSuspend, GC.Virus, GC.LastEvent = false, false, nil, nil
        GC.Slots, GC.SlotOf, GC.Winner, GC.army = {}, {}, nil, {}
        GC.VisOf, GC.Seen, GC.airCd = {}, {}, {}
        GC.pacts, GC.offers, GC.oilUsed, GC.Choices = {}, {}, {}, {}
        GC.expPend = {}
        GC.Dead = {}
        GC.access, GC.muted, GC.accReq = {}, {}, {}
        GC.accessExp, GC.disc = {}, {}
        GC.shipOrd = {}
        GC.SendLobby()
    end

    function GC.CheckWin()
        if GC.State ~= "playing" then return end
        local has = {}
        for i = 1, GCN do
            local o = GC.owner[i]
            if o ~= 0 then has[o] = true end
        end
        for s in ipairs(GC.Slots) do
            if not has[s] and not GC.Dead[s] then
                GC.Dead[s] = true

                local P = GC.Slots[s]
                if FogOn() and P and IsValid(P.ply) and not P.ply:IsBot() and GC.Viewers[P.ply] then GC.SendFull(P.ply) end
            end
        end
        if #GC.Slots < 2 then return end
        local cnt, last = 0, nil
        for s in ipairs(GC.Slots) do
            if has[s] then cnt, last = cnt + 1, s end
        end
        if cnt > 1 then return end

        GC.State, GC.Winner = "ended", last
        hook.Run("GCapture_GameEnded", last)
        GC.FinishRec()
        GC.SendWin()
        timer.Create("GCapture_EndReset", 15, 1, function()
            if GC.State == "ended" then ResetToLobby() end
        end)
    end

    function GC.LoadCustom(CM)
        GC.blevel = {}
        for i = 1, GCN do GC.biome[i], GC.owner[i], GC.build[i], GC.ship[i] = CM.biome[i], 0, 0, 0 end
    end

    function GC.SendDeployPicks(target)
        local D = GC.Deploy
        if not D then return end
        local list = {}
        for s, c in pairs(D.picks) do
            local P = GC.Slots[s]
            if P then list[#list + 1] = { c, P.color } end
        end
        local v = target and { target } or ViewerList(true)
        if #v == 0 then return end
        net.Start("GCapture_Deploy")
        net.WriteUInt(1, 2)
        net.WriteUInt(#list, 8)
        for _, e in ipairs(list) do
            net.WriteUInt(e[1], 20)
            net.WriteUInt(math.Round(e[2].r), 8)
            net.WriteUInt(math.Round(e[2].g), 8)
            net.WriteUInt(math.Round(e[2].b), 8)
        end
        net.Send(v)
    end

    function GC.SendDeploy(ply)
        local D = GC.Deploy
        if not D or not IsValid(ply) then return end
        local slot = GC.SlotOf[ply] or 0
        local P = GC.Slots[slot]
        local parts = {}
        for i = 1, GCN do parts[i] = string.char(GC.biome[i]) end
        local comp = util.Compress(table.concat(parts))
        local seq = ((ply.GCDepSeq or 0) + 1) % 256
        ply.GCDepSeq = seq

        net.Start("GCapture_Deploy")
        net.WriteUInt(0, 2)
        net.WriteUInt(GCW, 10)
        net.WriteUInt(GCH, 10)
        net.WriteUInt(math.Clamp(math.ceil(D.endT - CurTime()), 0, 127), 7)
        net.WriteUInt(slot, 8)
        net.WriteUInt(P and math.Round(P.color.r) or 0, 8)
        net.WriteUInt(P and math.Round(P.color.g) or 0, 8)
        net.WriteUInt(P and math.Round(P.color.b) or 0, 8)
        net.WriteUInt(seq, 8)
        net.Send(ply)
        local CH = 30000
        local nCh = math.max(1, math.ceil(#comp / CH))
        for k = 1, nCh do
            timer.Simple((k - 1) * 0.05, function()
                if not IsValid(ply) then return end
                local part = string.sub(comp, (k - 1) * CH + 1, k * CH)
                net.Start("GCapture_DeployData")
                net.WriteUInt(seq, 8)
                net.WriteUInt(#part, 16)
                net.WriteData(part, #part)
                net.WriteBool(k == nCh)
                net.Send(ply)
            end)
        end
        GC.SendDeployCountries(ply)
        GC.SendDeployPicks(ply)
    end

    function GC.SendDeployCountries(ply)
        local D = GC.Deploy
        local CM = GC.CustomMap
        if not D or not D.cellCountry or not CM or not IsValid(ply) then return end
        local parts = {}
        for i = 1, GCN do parts[i] = string.char(D.cellCountry[i] or 0) end
        local comp = util.Compress(table.concat(parts))
        if #comp > 60000 then return end
        local nc = math.min(#CM.pre, 128)
        net.Start("GCapture_Deploy")
        net.WriteUInt(2, 2)
        net.WriteUInt(nc, 8)
        for k = 1, nc do
            local c = CM.pre[k].color or HSVToColor((k * 47) % 360, 0.7, 1)
            net.WriteUInt(math.Round(c.r), 8)
            net.WriteUInt(math.Round(c.g), 8)
            net.WriteUInt(math.Round(c.b), 8)
        end
        net.WriteUInt(#comp, 16)
        net.WriteData(comp, #comp)
        net.Send(ply)
    end

    function GC.BeginDeploy(cont)
        GC.State = "deploy"
        GC.Deploy = { endT = CurTime() + GC.DeployTime, picks = {}, cont = cont, countryOf = {}, taken = {} }
        local CM = (GC.Opts.map or "") ~= "" and GC.CustomMap or nil
        if CM and CM.pre and #CM.pre > 0 and not GC.Opts.nopresets then
            local cc = {}
            for k, C in ipairs(CM.pre) do
                for _, c in ipairs(C.cells) do cc[c] = k end
            end
            GC.Deploy.cellCountry = cc
        end
        for _, p in ipairs(ViewerList(true)) do GC.SendDeploy(p) end
        timer.Create("GCapture_Deploy", GC.DeployTime, 1, function()
            local D = GC.Deploy
            if GC.State ~= "deploy" or not D then return end
            GC.Deploy = nil
            D.cont(D.picks, D.countryOf)
        end)
    end

    net.Receive("GCapture_DeployPick", function(_, ply)
        local D = GC.Deploy
        if GC.State ~= "deploy" or not D then return end
        local slot = GC.SlotOf[ply]
        if not slot then return end
        local cell = net.ReadUInt(20)
        if cell < 1 or cell > GCN or GC.Biomes[GC.biome[cell]].water then return end
        if D.cellCountry then
            local CM = GC.CustomMap
            local k = D.cellCountry[cell]
            local function Release()
                local old = D.countryOf[slot]
                if old and D.taken[old] == slot then D.taken[old] = nil end
                D.countryOf[slot] = nil
            end
            if k then
                if D.taken[k] and D.taken[k] ~= slot then
                    GC.SendDeployPicks(ply)
                    return
                end
                Release()
                D.countryOf[slot], D.taken[k] = k, slot
                D.picks[slot] = CM.pre[k].spawn
                GC.SendDeployPicks()
                return
            end

            local cx0, cy0 = XY(cell)
            for s, c in pairs(D.picks) do
                if s ~= slot then
                    local x, y = XY(c)
                    if math.max(math.abs(x - cx0), math.abs(y - cy0)) <= 2 then
                        GC.SendDeployPicks(ply)
                        return
                    end
                end
            end
            Release()
            D.picks[slot] = cell
            GC.SendDeployPicks()
            return
        end
        local cx, cy = XY(cell)
        for s, c in pairs(D.picks) do
            if s ~= slot then
                local x, y = XY(c)
                if math.max(math.abs(x - cx), math.abs(y - cy)) <= 2 then
                    SendMsg(ply, "Too close to another player's start.")
                    return
                end
            end
        end
        D.picks[slot] = cell
        GC.SendDeployPicks()
    end)

    function GC.StartGame(list)
        timer.Remove("GCapture_EndReset")
        local CM = (GC.Opts.map or "") ~= "" and GC.CustomMap or nil
        GC.SizeIdx = GC.Opts.size or 1
        if CM then GC.SetSize(CM.w, CM.h) else GC.SetSize(GC.SizeList[GC.SizeIdx] or 32) end
        local seed
        local txt = string.Trim(GC.Opts.seed or "")
        if txt ~= "" then
            seed = tonumber(txt)
            if not seed or seed ~= seed or math.abs(seed) > 2147483000 then seed = tonumber(util.CRC(txt)) end
            seed = math.floor(math.abs(seed))
        else
            seed = os.time() % 1000000000 + math.random(0, 99999)
        end
        GC.Seed = seed
        GC.SeedText = CM and "" or tostring(seed)
        math.randomseed(seed)
        if CM then GC.LoadCustom(CM) else GC.Generate(seed) end
        math.randomseed(seed + 1)
        GC.expire, GC.Winner, GC.army, GC.airCd = {}, nil, {}, {}
        GC.expPend = {}
        GC.pacts, GC.offers, GC.oilUsed, GC.Choices = {}, {}, {}, {}
        GC.Dead = {}
        GC.access, GC.muted, GC.accReq = {}, {}, {}
        GC.accessExp, GC.disc = {}, {}
        GC.shipOrd = {}
        GC.GameId = GC.GameId + 1
        GC.VisOf, GC.Seen = {}, {}
        GC.Slots, GC.SlotOf = {}, {}
        local np = #list
        local n = np + (GC.Opts.bots or 0)

        local hues, base = {}, math.random(0, 359)
        for k = 1, n do hues[k] = (base + (k - 1) * 360 / n + math.random(-8, 8)) % 360 end
        table.Shuffle(hues)

        local taken = {}
        local function ColorFor(p, hue)
            local c = GC.Colors[p]
            if c then
                local ok = true
                for _, t in ipairs(taken) do
                    if (c.r - t.r) ^ 2 + (c.g - t.g) ^ 2 + (c.b - t.b) ^ 2 < 3600 then ok = false break end
                end
                if ok then taken[#taken + 1] = c return Color(c.r, c.g, c.b) end
                SendMsg(p, "Color already taken. You got a random one. HIHIHAHA")
            end
            local generated = HSVToColor(hue, 0.85, 1)
            taken[#taken + 1] = generated
            return generated
        end

        for s, p in ipairs(list) do
            GC.Slots[s] = {
                ply = p, name = GC.Names[p] or GC.DefaultName(p), color = ColorFor(p, hues[s]),
                coins = GC.Opts.rush and 1000 or GC.StartResources.coins, pop = GC.StartResources.pop, weapons = GC.StartResources.weapons,
                spirits = {},
            }
            GC.SlotOf[p] = s
        end

        for s = np + 1, n do GC.Slots[s] = GC.NewBotSlot(s, hues[s], s - np) end

        local mode = GC.Opts.mode or 0
        local function Continue(picks, countryOf)

        local landCells = {}
        for i = 1, GCN do
            if not GC.Biomes[GC.biome[i]].water then landCells[#landCells + 1] = i end
        end
        local spawns, minD = {}, math.max(3, math.floor(6 * GCW / 32 + 0.5))
        local fixed = CM and #CM.spawns > 0 and table.Copy(CM.spawns) or nil
        if fixed then table.Shuffle(fixed) end

        local presetCell, reserved = {}, {}
        local deployPre = false
        if CM and CM.pre and #CM.pre > 0 and (mode == 0 or mode == 2) and not GC.Opts.nopresets then
            local function GiveCountry(s, k)
                local C = CM.pre[k]
                for _, c in ipairs(C.cells) do GC.owner[c] = s end
                presetCell[s] = C.spawn
                reserved[#reserved + 1] = C.spawn
                if C.name ~= "" then GC.Slots[s].name = C.name end
                if C.color then GC.Slots[s].color = Color(C.color.r, C.color.g, C.color.b) end
            end
            local order = {}
            for k = 1, #CM.pre do order[k] = k end
            table.Shuffle(order)
            if mode == 0 then
                for s = 1, math.min(n, #order) do GiveCountry(s, order[s]) end
            else
                deployPre = true
                local used = {}
                for s, k in pairs(countryOf or {}) do
                    if s <= np and CM.pre[k] and not used[k] and IsValid(GC.Slots[s].ply) then
                        used[k] = true
                        GiveCountry(s, k)
                    end
                end
                local oi = 1
                for s = 1, n do
                    if not presetCell[s] and not (picks or {})[s] then
                        while order[oi] and used[order[oi]] do oi = oi + 1 end
                        if not order[oi] then break end
                        used[order[oi]] = true
                        GiveCountry(s, order[oi])
                    end
                end
            end
        end

        local chosen = {}
        for s, c in pairs(picks or {}) do
            if not presetCell[s] and GC.Slots[s] and c >= 1 and c <= GCN and not GC.Biomes[GC.biome[c]].water then
                chosen[s] = c
                reserved[#reserved + 1] = c
            end
        end
        local near, fi = {}, 0
        for _, c in ipairs(reserved) do near[#near + 1] = c end
        local function NextFixed()
            while fixed and fi < #fixed do
                fi = fi + 1
                local c = fixed[fi]
                if GC.owner[c] == 0 then return c end
            end
        end

        local capOf, observers = {}, {}
        for s = 1, n do
            local pick = presetCell[s] or chosen[s] or NextFixed()
            for attempt = 1, (pick and 0 or 300) do
                local c = landCells[math.random(#landCells)]
                local cx, cy = XY(c)
                local ok = GC.owner[c] == 0
                for _, o in ipairs(near) do
                    local ox, oy = XY(o)
                    if (cx - ox) ^ 2 + (cy - oy) ^ 2 < minD * minD then ok = false break end
                end
                if ok then pick = c break end
                if attempt % 40 == 0 then minD = math.max(1, minD - 1) end
            end
            if not pick then
                for _ = 1, 50 do
                    local c = landCells[math.random(#landCells)]
                    if GC.owner[c] == 0 then pick = c break end
                end
            end
            if not pick and deployPre and s <= np then

                observers[s] = true
            else
                pick = pick or landCells[math.random(#landCells)]
                near[#near + 1] = pick
                spawns[#spawns + 1] = pick
                capOf[s] = pick
                GC.owner[pick], GC.build[pick] = s, GC.B_CAPITAL
            end
        end
        for s in pairs(observers) do
            local P = GC.Slots[s]
            if P and IsValid(P.ply) then GC.SlotOf[P.ply] = nil end
            if P then P.ply = nil end
        end

        for s = 1, n do
            local cap = capOf[s]
            if not cap then continue end
            local candidates = {}
            for _, j in ipairs(GC.Neighbors8(cap)) do
                if not GC.Biomes[GC.biome[j]].water and (GC.owner[j] == 0 or GC.owner[j] == s) and GC.build[j] == 0 then
                    candidates[#candidates + 1] = j
                end
            end
            if #candidates == 0 then
                for _, j in ipairs(landCells) do
                    if (GC.owner[j] == 0 or GC.owner[j] == s) and GC.build[j] == 0 then
                        local x, y = XY(j); local cx, cy = XY(cap)
                        if math.max(math.abs(x-cx), math.abs(y-cy)) <= 2 then candidates[#candidates + 1] = j end
                    end
                end
            end
            if #candidates > 0 then
                local village = candidates[math.random(#candidates)]
                GC.owner[village], GC.build[village] = s, GC.B_VILLAGE
            end
        end

        if GC.Opts.rush then
            local quota = math.floor(#landCells / n)
            local cnt, fr = {}, {}
            for s = 1, n do cnt[s], fr[s] = 0, {} end
            local function AddFrontier(s, c)
                for _, j in ipairs(GC.Neighbors(c)) do
                    if GC.owner[j] == 0 and not GC.Biomes[GC.biome[j]].water then fr[s][#fr[s] + 1] = j end
                end
            end
            for i = 1, GCN do
                local o = GC.owner[i]
                if o ~= 0 then cnt[o] = cnt[o] + 1 AddFrontier(o, i) end
            end
            local progress = true
            while progress do
                progress = false
                for s = 1, n do
                    if cnt[s] < quota then
                        local c, f = nil, fr[s]
                        while #f > 0 do
                            local k = math.random(#f)
                            local cand = f[k]
                            f[k] = f[#f]
                            f[#f] = nil
                            if GC.owner[cand] == 0 then c = cand break end
                        end
                        if not c then
                            local pool = {}
                            for _, lc in ipairs(landCells) do
                                if GC.owner[lc] == 0 then pool[#pool + 1] = lc end
                            end
                            if #pool > 0 then c = pool[math.random(#pool)] end
                        end
                        if c then
                            GC.owner[c] = s
                            cnt[s] = cnt[s] + 1
                            AddFrontier(s, c)
                            progress = true
                        end
                    end
                end
            end
        end

        local free, tundra = {}, {}
        for _, c in ipairs(landCells) do
            local cx, cy = XY(c)
            local okc = true
            for _, o in ipairs(spawns) do
                local ox, oy = XY(o)
                if math.max(math.abs(cx - ox), math.abs(cy - oy)) <= 2 then okc = false break end
            end
            if okc and GC.owner[c] == 0 then
                free[#free + 1] = c
                if GC.biome[c] == GC.TUNDRA then tundra[#tundra + 1] = c end
            end
        end
        local used = {}
        local function Pick(pool)
            while #pool > 0 do
                local k = math.random(#pool)
                local c = pool[k]
                table.remove(pool, k)
                if not used[c] then used[c] = true return c end
            end
        end
        local chestPool = (#tundra > 0) and tundra or free
        local sc = GCN / 1024
        if GC.Opts.nochests then

        elseif CM and #CM.chest > 0 then
            for _, c in ipairs(CM.chest) do
                if GC.build[c] == 0 then GC.build[c] = GC.B_CHEST end
            end
        else
            for _ = 1, math.random(math.max(1, math.floor(3 * sc)), math.max(1, math.floor(8 * sc))) do
                local c = Pick(chestPool)
                if c then GC.build[c] = GC.B_CHEST end
            end
        end
        if CM and #CM.vill > 0 then

            for _, c in ipairs(CM.vill) do
                if GC.build[c] == 0 then GC.build[c] = GC.B_VILLAGE end
            end
        elseif not GC.Opts.novillages then
            for _ = 1, math.random(math.max(1, math.floor(2 * sc)), math.max(1, math.floor(9 * sc))) do
                local c = Pick(free)
                if c then GC.build[c] = GC.B_VILLAGE end
            end
        end

        math.randomseed(os.time() + math.floor(SysTime() * 1000))

        for s = 1, n do
            local opts = GC.RollChoices(s, 3)
            local p = GC.Slots[s].ply
            if #opts > 0 then
                if IsValid(p) and not p:IsBot() and not GC.Opts.nospirits then
                    GC.Choices[s] = { opts = opts, deadline = CurTime() + GC.ChoiceTime }
                else
                    GC.Slots[s].spirits[1] = GC.PickFor(s, opts)
                end
            end
        end

        for s = 1, n do
            local P = GC.Slots[s]
            if P and not P.bot and not IsValid(P.ply) then
                for i = 1, GCN do
                    if GC.owner[i] == s then GC.owner[i], GC.build[i] = 0, 0 end
                end
            end
        end

        GC.DayT0 = CurTime()
        GC.State = "playing"
        GC.nextTimedChoice = CurTime() + GC.ChoiceInterval
        GC.nextEvent = CurTime() + 300
        GC.EventBusy, GC.FogSuspend, GC.Virus, GC.LastEvent = false, false, nil, nil
        GC.InitBots()
        for _, p in ipairs(ViewerList(true)) do GC.SendFull(p) end
        for _, p in ipairs(ViewerList(true)) do SendMsg(p, "Map seed: " .. seed) end
        print("[GCapture] Map seed: " .. seed)
        GC.StartRec(list)
        hook.Run("GCapture_GameStarted")
        end

        if mode == 2 then GC.BeginDeploy(Continue) else Continue({}) end
    end

    net.Receive("GCapture_View", function(_, ply)
        if net.ReadBool() then
            GC.Viewers[ply] = true
            if GC.State == "lobby" then
                GC.SendLobby()
            elseif GC.State == "deploy" then
                GC.SendDeploy(ply)
            else
                GC.SendFull(ply)
                if GC.State == "ended" then GC.SendWin(ply) end
            end
        else
            GC.Viewers[ply] = nil
            if GC.State == "lobby" then GC.SendLobby() end
        end
    end)

    net.Receive("GCapture_Name", function(_, ply)
        if GC.State ~= "lobby" then return end
        local name = GC.TrimName(net.ReadString())
        GC.Names[ply] = (name ~= "") and name or nil
        GC.SendLobby()
    end)

    net.Receive("GCapture_Color", function(_, ply)
        if GC.State ~= "lobby" then return end
        if net.ReadBool() then
            local c = Color(net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8))
            local h, sat, v = ColorToHSV(c)
            if v < 0.6 then c = HSVToColor(h, sat, 0.6) end
            GC.Colors[ply] = Color(math.Round(c.r), math.Round(c.g), math.Round(c.b))
        else
            GC.Colors[ply] = nil
        end
        GC.SendLobby()
    end)

    net.Receive("GCapture_Opts", function(_, ply)
        if GC.State ~= "lobby" or not IsHost(ply) then return end
        GC.Opts.mode = math.Clamp(net.ReadUInt(2), 0, 2)
        GC.Opts.rush = GC.Opts.mode == 1
        GC.Opts.nofog = net.ReadBool()
        GC.Opts.bots = math.Clamp(net.ReadUInt(6), 0, GC.MaxBots)
        GC.Opts.diff = math.Clamp(net.ReadUInt(3), 0, 4)
        GC.Opts.btype = math.Clamp(net.ReadUInt(2), 0, 3)
        GC.Opts.size = math.Clamp(net.ReadUInt(2), 0, 3)
        GC.Opts.observe = net.ReadBool()
        local sd = string.gsub(net.ReadString(), "%c", "")
        GC.Opts.seed = string.sub(string.Trim(sd), 1, 24)
        GC.Opts.noevents = net.ReadBool()
        GC.Opts.emperor = net.ReadBool()
        for _, k in ipairs(GC.OptFlags) do GC.Opts[k] = net.ReadBool() end

        if GC.Opts.noplains and GC.Opts.noforest and GC.Opts.nodesert and GC.Opts.notundra then GC.Opts.noplains = false end
        GC.Opts.map = GC.Opts.map or ""
        GC.SendLobby()
    end)

    net.Receive("GCapture_MapUp", function(_, ply)
        if GC.State ~= "lobby" or not IsHost(ply) then return end
        if not net.ReadBool() then
            GC.CustomMap, GC.Opts.map = nil, ""
            ply.GCMapBuf = nil
            return GC.SendLobby()
        end
        if net.ReadBool() then
            ply.GCMapBuf = { name = string.sub(string.gsub(net.ReadString(), "%c", ""), 1, 40), parts = {}, size = 0 }
        end
        local buf = ply.GCMapBuf
        local part = net.ReadData(net.ReadUInt(16))
        local last = net.ReadBool()
        if not buf then return end
        buf.parts[#buf.parts + 1] = part
        buf.size = buf.size + #part
        if buf.size > 3000000 then ply.GCMapBuf = nil return end
        if not last then return end
        ply.GCMapBuf = nil

        local function Bad(msg) ply:PrintMessage(HUD_PRINTTALK, "[GCapture] Map rejected: " .. msg) end
        local js = util.Decompress(table.concat(buf.parts), 8000000)
        local d = js and util.JSONToTable(js)
        if not d then return Bad("corrupted data.") end
        local w, h = tonumber(d.w), tonumber(d.h)
        if not w or not h or w < 1 or h < 1 or w > 512 or h > 512 or w ~= math.floor(w) or h ~= math.floor(h) then
            return Bad("bad size.")
        end
        local n = w * h
        if type(d.b) ~= "string" or #d.b ~= n then return Bad("bad biome data.") end

        local biome, land = {}, 0
        for i = 1, n do
            local b = string.byte(d.b, i) - 48
            if b < 1 or b > 5 then b = 5 end
            biome[i] = b
            if b ~= 5 then land = land + 1 end
        end
        if land == 0 then return Bad("the map has no land.") end

        local function Marks(src)
            local out, seen = {}, {}
            for _, c in ipairs(type(src) == "table" and src or {}) do
                c = tonumber(c)
                if c and c >= 1 and c <= n and c == math.floor(c) and biome[c] ~= 5 and not seen[c] then
                    seen[c] = true
                    out[#out + 1] = c
                end
            end
            return out
        end

        local pre, owned = {}, {}
        for _, C in ipairs(type(d.p) == "table" and d.p or {}) do
            if #pre >= 128 then break end
            if type(C) == "table" then
                local sp = tonumber(C.s)
                if sp and sp >= 1 and sp <= n and sp == math.floor(sp) and biome[sp] ~= 5 and not owned[sp] then
                    local cells = { sp }
                    owned[sp] = true
                    for _, c in ipairs(type(C.c) == "table" and C.c or {}) do
                        c = tonumber(c)
                        if c and c >= 1 and c <= n and c == math.floor(c) and biome[c] ~= 5 and not owned[c] then
                            owned[c] = true
                            cells[#cells + 1] = c
                        end
                    end
                    local col
                    if type(C.k) == "table" then
                        local r, g, b = tonumber(C.k[1]), tonumber(C.k[2]), tonumber(C.k[3])
                        if r and g and b then
                            col = Color(math.Clamp(math.floor(r), 0, 255), math.Clamp(math.floor(g), 0, 255), math.Clamp(math.floor(b), 0, 255))
                        end
                    end
                    pre[#pre + 1] = { name = GC.TrimName(tostring(C.n or "")), spawn = sp, cells = cells, color = col }
                end
            end
        end
        GC.CustomMap = { name = buf.name, w = w, h = h, biome = biome, spawns = Marks(d.s), vill = Marks(d.v), chest = Marks(d.c), pre = pre }
        GC.Opts.map = string.format("%s (%dx%d)", buf.name, w, h)
        GC.SendLobby()
    end)

    local cvAuto  = CreateConVar("sv_gc_autostart", "0", FCVAR_ARCHIVE + FCVAR_NOTIFY, "GCapture: auto-start the game from the lobby (1 = on)", 0, 1)
    local cvAutoT = CreateConVar("sv_gc_autostart_timer", "30", FCVAR_ARCHIVE + FCVAR_NOTIFY, "GCapture: seconds before auto-start (10-60)", 10, 60)
    local cvAutoPly = CreateConVar("sv_gc_autostart_ply", "2", FCVAR_ARCHIVE + FCVAR_NOTIFY, "GCapture: minimum number of players in the lobby for the auto-start timer to run (2-256)", 2, 256)

    function GC.TryStart(ply)
        if GC.State ~= "lobby" then return false end
        local list, bots = ViewerList(), GC.Opts.bots or 0
        if GC.Opts.observe then
            for k = #list, 1, -1 do if IsHost(list[k]) then table.remove(list, k) end end
            if #list + bots < 2 then
                if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[GCapture] Observe needs at least 2 participants (players + bots).") end
                return false
            end
        end
        if #list == 0 and bots == 0 then return false end
        GC.StartGame(list)
        return true
    end

    net.Receive("GCapture_Start", function(_, ply)
        if GC.State ~= "lobby" or not IsHost(ply) then return end
        GC.TryStart(ply)
    end)

    local autoLeft, autoSent
    local function SendAuto(left)
        autoSent = left > 0
        local v = ViewerList(true)
        if #v == 0 then return end
        net.Start("GCapture_Auto")
        net.WriteUInt(left, 7)
        net.Send(v)
    end
    timer.Create("GCapture_Auto", 1, 0, function()

        local need = math.Clamp(cvAutoPly:GetInt(), 2, 256)
        if not (cvAuto:GetBool() and GC.State == "lobby" and #ViewerList(true) >= need) then
            if autoSent then SendAuto(0) end
            autoLeft = nil
            return
        end
        autoLeft = autoLeft or math.Clamp(cvAutoT:GetInt(), 10, 60)
        if autoLeft <= 0 then
            autoLeft = nil
            SendAuto(0)
            GC.TryStart(nil)
            return
        end
        SendAuto(autoLeft)
        autoLeft = autoLeft - 1
    end)
    net.Receive("GCapture_Stop", function(_, ply)
        if GC.State == "lobby" or not IsHost(ply) then return end
        GC.FinishRec()
        ResetToLobby()
    end)

    local function FindAirbase(slot, idx)
        local cx, cy = XY(idx)
        local R = GC.AirRange(slot)
        local inRange = false
        for i = 1, GCN do
            if GC.build[i] == GC.B_AIR and GC.owner[i] == slot then
                local x, y = XY(i)
                if math.abs(x - cx) <= R and math.abs(y - cy) <= R then
                    inRange = true
                    if (GC.airCd[i] or 0) <= CurTime() then return i, true end
                end
            end
        end
        return nil, inRange
    end

    net.Receive("GCapture_Act", function(_, ply)
        if GC.State ~= "playing" then return end
        local slot = GC.SlotOf[ply]
        if not slot then return end

        local idx, act, idx2 = net.ReadUInt(GCIB) + 1, net.ReadUInt(GC.ActBits), net.ReadUInt(GCIB + 1)
        local a = GC.Actions[act]
        if not a or idx < 1 or idx > GCN then return end

        local water = GC.Biomes[GC.biome[idx]].water and true or false
        if not a.any and (a.water and true or false) ~= water then return end

        local P = GC.Slots[slot]
        local owner, bl = GC.owner[idx], GC.build[idx]
        local function Fail(msg) SendMsg(ply, msg) end

        if a.coins and P.coins < a.coins then return Fail("Not enough coins!") end
        if a.pop and P.pop < a.pop then return Fail("Not enough population.") end
        if a.weapons and P.weapons < a.weapons then return Fail("Not enough weapons.") end
        if a.mod then
            local ok, msg = GC.Mods.CheckAction(a, ply, slot, idx, idx2)
            if not ok then return Fail(msg) end
        end

        local function Pay()
            P.coins = P.coins - (a.coins or 0)
            P.pop = P.pop - (a.pop or 0)
            P.weapons = P.weapons - (a.weapons or 0)
        end

        if act == 1 then
            if owner ~= 0 then return Fail("Cell already taken.") end
            local ca = GC.army[idx]
            if ca and ca.owner ~= slot then return Fail("An enemy army is on this cell.") end
            if not GC.HasNeighbor(GC.owner, idx, slot, GC.ship) then
                return Fail("You can only expand next to your land or ship.")
            end
            local pend = GC.expPend[slot]
            if pend and #pend >= GC.ExpandMax then return Fail("Already expanding.") end
            for _, list in pairs(GC.expPend) do
                for _, e in ipairs(list) do if e.cell == idx then return Fail("Someone is already expanding there.") end end
            end
            Pay()
            GC.expPend[slot] = GC.expPend[slot] or {}
            table.insert(GC.expPend[slot], { cell = idx, t = CurTime() + GC.ExpandTime })
            net.Start("GCapture_Exp")
            net.WriteUInt(idx - 1, GCIB)
            net.WriteUInt(GC.ExpandTime, 4)
            net.Send(ply)

        elseif a.build then
            if owner ~= slot then return Fail("Not your cell.") end
            if bl ~= 0 then return Fail("This cell already has a structure.") end
            if a.build == GC.B_OIL and GC.oilUsed[idx] then return Fail("The oil here is already drained.") end
            if a.biome and GC.biome[idx] ~= a.biome then return Fail("Desert only.") end
            if a.coast and not GC.IsCoast(idx) then return Fail("Coast only.") end
            if a.build == GC.B_AIR and not GC.AirbaseUnlocked() then return Fail("Airbases unlock on day " .. GC.AirbaseMinDay .. ".") end
            if not GC.CanBuildAt(slot, idx) then return Fail("Cut off from the capital. You need a ship touching both islands.") end
            Pay()
            GC.Place(idx, slot, a.build)
            if not ply:IsBot() then
                net.Start("GCapture_Build")
                net.Send(ply)
            end

        elseif a.run then
            Pay()
            local ok, err = pcall(a.run, ply, slot, idx, idx2, P)
            if not ok then ErrorNoHalt("[GCapture] submod action '" .. tostring(a.name) .. "' failed: " .. tostring(err) .. "\n") end

        elseif act == 9 then
            if GC.ship[idx] ~= 0 then return Fail("There's already a ship here.") end
            if not GC.HasNeighbor(GC.owner, idx, slot) then return Fail("Build ships next to your land.") end
            Pay()
            GC.SetShip(idx, slot)

        elseif act == 10 then
            if GC.ship[idx] ~= slot then return Fail("Not your ship.") end
            if GC.army[idx] then return Fail("Unload the army first.") end
            if not GC.HasLandNeighbor(idx) then return Fail("Disassemble ships next to land.") end
            AddCoins(P, a.refund.coins)
            AddPop(slot, P, a.refund.pop)
            GC.SetShip(idx, 0)

        elseif act == 11 then
            if GC.ship[idx] ~= slot then return Fail("Not your ship.") end
            if idx2 < 1 or idx2 > GCN or not GC.Biomes[GC.biome[idx2]].water then return Fail("Water only.") end
            if not table.HasValue(GC.Neighbors(idx), idx2) then return Fail("Adjacent cells only.") end
            if GC.ship[idx2] ~= 0 then return Fail("Another ship is there.") end
            local A = GC.army[idx]
            if A and A.state ~= GC.ST_IDLE then return Fail("The army on board is fighting.") end
            GC.SetShip(idx, 0)
            GC.SetShip(idx2, slot)
            if A then RawMoveArmy(A, idx2) end

        elseif act == 31 then
            if GC.ship[idx] ~= slot then return Fail("Not your ship.") end
            if idx2 == 0 then GC.shipOrd[idx] = nil return end
            if idx2 < 1 or idx2 > GCN or idx2 == idx then return end
            GC.SetShipOrder(slot, idx, idx2)

        elseif act == 12 then
            local s = GC.ship[idx]
            if s == 0 or s == slot then return Fail("Enemy ships only.") end
            if GC.HasPact(slot, s) then return Fail("Non-aggression pact in effect.") end
            if not GC.CoastGuardNear(idx, slot) then return Fail("Out of Coast Guard range.") end
            Pay()
            local A = GC.army[idx]
            if A then RemoveArmy(A) end
            GC.SetShip(idx, 0)
            Notify(s, P.name .. " sank your ship!")

        elseif act == 13 or act == 28 then
            local cav = (act == 28)
            if not GC.CanSpawnArmy(slot, idx, cav) then
                return Fail(cav and "Needs a free Cavalry Center cell."
                                or "Needs a free Army Center cell.")
            end
            if not GC.CanBuildAt(slot, idx) then return Fail("Cut off from the capital, can't recruit.") end
            Pay()
            CreateArmy(slot, idx, false, cav)

        elseif act == 29 then
            if owner ~= slot or bl ~= GC.B_BARRICADE then return Fail("Not your fortress.") end
            local lvl = GC.blevel[idx] or 1
            if lvl >= GC.BarricadeMaxLevel then return Fail("Fortress is at max level.") end
            if not GC.CanBuildAt(slot, idx) then return Fail("Cut off from the capital, can't upgrade.") end
            local cost = GC.BarricadeUpgrade[lvl]
            if P.coins < cost then return Fail("Not enough coins!") end
            P.coins = P.coins - cost
            GC.SetCell(idx, slot, bl, lvl + 1)

        elseif act == 20 then
            if owner == 0 or owner == slot then return Fail("Enemy cells only.") end
            if GC.HasPact(slot, owner) then return Fail("Non-aggression pact in effect.") end
            if GC.AccessTie(slot, owner) then return Fail("Military access is open. Close it first.") end
            local ca = GC.army[idx]
            if (bl == 0 or bl == GC.B_FIRE or bl == GC.B_CRATER) and not ca then return Fail("Nothing to bombard here.") end
            local base, inRange = FindAirbase(slot, idx)
            if not base then
                return Fail(inRange and "Airbase is reloading." or "No airbase in range.")
            end
            Pay()
            GC.airCd[base] = CurTime() + GC.AirCooldown
            for _, v in ipairs(ViewerList(true)) do
                net.Start("GCapture_AirCD")
                net.WriteUInt(base - 1, GCIB)
                net.WriteFloat(GC.AirCooldown)
                net.Send(v)
            end

            for _, v in ipairs(ViewerList(true)) do
                if Sees(v, idx) or GC.SlotOf[v] == slot then
                    net.Start("GCapture_Boom")
                    net.WriteUInt(idx - 1, GCIB)
                    net.Send(v)
                end
            end
            if GC.Rec then
                GC.Rec.ev = GC.Rec.ev or {}
                table.insert(GC.Rec.ev, idx)
            end
            if bl == GC.B_CAPITAL then

                local OP = GC.Slots[owner]
                OP.coins = math.max(0, OP.coins - GC.CapitalBombPenalty)
            else
                GC.BombCell(idx, owner)
            end
            GC.AddDiscontent(owner)
            if ca and ca.owner ~= slot then GC.BombArmy(ca) end
            if bl == GC.B_CAPITAL then
                Notify(owner, P.name .. " bombed your capital: -" .. GC.CapitalBombPenalty .. " coins")
            else
                Notify(owner, P.name .. " bombed your cell.")
            end

        elseif act == 21 then
            if owner ~= slot or bl ~= GC.B_CHEST then return Fail("The chest must be on your land.") end
            local sp = GC.RollSpirit(slot)
            if not sp then return Fail("You already have every spirit.") end
            Pay()
            GC.SetCell(idx, slot, 0)
            GC.GiveSpirit(slot, sp)

        elseif act == 25 then
            if owner ~= slot then return Fail("Not your cell.") end
            if bl == 0 or bl == GC.B_FIRE then return Fail("Nothing to delete.") end
            if bl == GC.B_CAPITAL then return Fail("The capital can't be deleted.") end
            if bl == GC.B_CRATER then return Fail("Craters can't be removed.") end
            GC.SetCell(idx, slot, 0)

        elseif (act >= 14 and act <= 18) or act == 22 or act == 23 or act == 24 or act == 30 then
            local A = GC.army[idx]
            if not A or A.owner ~= slot then return Fail("No army here.") end

            if act == 14 then
                A.route = nil
                A.autoId = nil
                if water then return Fail("The army is on a ship. Use Disembark.") end
                if A.state ~= GC.ST_IDLE then return Fail("The army is busy!") end
                if IsTraining(A) then return Fail("The army is still training.") end
                if CurTime() < A.nextMove then return Fail("The army can't move yet.") end
                if GC.CanArmyAttack(slot, idx, idx2) then
                    local ok, msg = StartAttack(A, idx2)
                    if not ok then return Fail(msg) end
                elseif GC.CanArmyMoveTo(slot, idx, idx2) then
                    MoveArmy(A, idx2)
                elseif GC.CanStand(slot, idx2) then
                    local queue, prev, seen = { idx }, {}, { [idx] = true }
                    local head = 1
                    while head <= #queue and not seen[idx2] do
                        local c = queue[head]; head = head + 1
                        for _, j in ipairs(GC.Neighbors8(c)) do
                            if not seen[j] and GC.CanStand(slot, j) and (not GC.army[j] or j == idx2) then
                                seen[j], prev[j] = true, c
                                queue[#queue + 1] = j
                            end
                        end
                    end
                    if not seen[idx2] then return Fail("No land route there.") end
                    local route, c = {}, idx2
                    while c ~= idx do table.insert(route, 1, c); c = prev[c] end
                    A.route, A.nextRoute = route, CurTime()
                    Notify(slot, "Route set: " .. #route .. " cells.")
                else
                    return Fail("Pick your own cell or an adjacent enemy cell.")
                end

            elseif act == 15 then
                if water then return Fail("The army is on a ship. Use Disembark.") end
                local ok, msg = StartAttack(A, idx2)
                if not ok then return Fail(msg) end

            elseif act == 16 then
                if A.state ~= GC.ST_ATTACK then return Fail("The army isn't attacking.") end
                CancelAttack(A)

            elseif act == 17 then
                if A.state ~= GC.ST_DEFENSE or #A.attackers == 0 then return Fail("The army isn't defending.") end
                if not FindRetreat(A) then return Fail("Nowhere to retreat.") end
                Rout(A, A.attackers[1], false)

            elseif act == 18 then
                if not water or GC.ship[idx] ~= slot then return Fail("The army isn't on your ship.") end
                if A.state ~= GC.ST_IDLE then return Fail("The army is busy!") end
                if IsTraining(A) then return Fail("The army is still training.") end
                if not GC.CanArmyLand(slot, idx, idx2) then return Fail("Can't land here.") end
                if not GC.army[idx2] and (GC.owner[idx2] == slot or GC.HasAccess(slot, GC.owner[idx2])) then

                    if CurTime() < A.nextMove then return Fail("The army can't move yet.") end
                    MoveArmy(A, idx2)
                else

                    local ok, msg = StartAttack(A, idx2)
                    if not ok then return Fail(msg) end
                end

            elseif act == 22 then
                A.autoId = nil
                if water then return Fail("The army is on a ship. Use Disembark.") end
                if A.state ~= GC.ST_IDLE then return Fail("The army is busy!") end
                if IsTraining(A) then return Fail("The army is still training.") end
                local ok, msg = StartBorder(A)
                if not ok then return Fail(msg) end

            elseif act == 23 then
                if A.autoId then
                    A.autoId = nil
                    GC.SendArmy(A)
                elseif A.state == GC.ST_BORDER then
                    A.state = GC.ST_IDLE
                    GC.SendArmy(A)
                else
                    return Fail("The army isn't moving.")
                end

            elseif act == 24 then
                RemoveArmy(A)

            elseif act == 30 then
                if water then return Fail("The army is on a ship. Use Disembark.") end
                if A.state ~= GC.ST_IDLE then return Fail("The army is busy!") end
                if IsTraining(A) then return Fail("The army is still training.") end
                if A.org < 1 then return Fail("No organization.") end
                local ok, msg = StartAuto(A)
                if not ok then return Fail(msg) end
            end
        end

        GC.SendStats()
        GC.CheckWin()
    end)

    timer.Create("GCapture_Expand", 0.2, 0, function()
        if GC.State ~= "playing" then return end
        local now, changed = CurTime(), false
        for slot, list in pairs(GC.expPend or {}) do
            for k = #list, 1, -1 do
                local e = list[k]
                if now >= e.t then
                    table.remove(list, k)
                    local P, i = GC.Slots[slot], e.cell
                    if P then
                        local ca = GC.army[i]
                        local a = GC.Actions[1]
                        if GC.owner[i] == 0 and not (ca and ca.owner ~= slot) and GC.HasNeighbor(GC.owner, i, slot, GC.ship) then
                            GC.SetCell(i, slot, GC.build[i])
                            if IsValid(P.ply) and not P.ply:IsBot() then
                                net.Start("GCapture_ExpandSound")
                                net.Send(P.ply)
                            end
                        else
                            AddCoins(P, a.coins)
                            AddPop(slot, P, a.pop)
                            Notify(slot, "Expansion failed. Resources refunded.")
                        end
                        if IsValid(P.ply) and not P.ply:IsBot() then
                            net.Start("GCapture_Exp")
                            net.WriteUInt(i - 1, GCIB)
                            net.WriteUInt(0, 4)
                            net.Send(P.ply)
                        end
                        changed = true
                    end
                end
            end
            if #list == 0 then GC.expPend[slot] = nil end
        end
        if changed then GC.SendStats() end
    end)

    net.Receive("GCapture_Pick", function(_, ply)
        if GC.State ~= "playing" then return end
        local slot = GC.SlotOf[ply]
        local ch = slot and GC.Choices[slot]
        if not ch then return end
        local inst = ch.opts[net.ReadUInt(2)]
        if not inst then return end
        GC.Choices[slot] = nil
        GC.GiveSpirit(slot, inst)
        GC.NextChoice(slot)
    end)

    GC.access, GC.muted, GC.accReq = GC.access or {}, GC.muted or {}, GC.accReq or {}
    GC.accessExp, GC.disc = GC.accessExp or {}, GC.disc or {}

    function GC.SendAccess(target)
        local v = target and { target } or ViewerList(true)
        for _, p in ipairs(v) do
            local slot = GC.SlotOf[p]
            local list, mut = {}, {}
            for k in pairs(GC.access) do
                local g, e = math.floor(k / 256), k % 256
                if not slot or g == slot or e == slot then list[#list + 1] = { g, e } end
            end
            if slot then
                for k in pairs(GC.muted) do
                    if math.floor(k / 256) == slot then mut[#mut + 1] = k % 256 end
                end
            end
            net.Start("GCapture_Access")
            net.WriteUInt(#list, 12)
            for _, e in ipairs(list) do
                net.WriteUInt(e[1], 8)
                net.WriteUInt(e[2], 8)
            end
            net.WriteUInt(#mut, 8)
            for _, c in ipairs(mut) do net.WriteUInt(c, 8) end
            net.Send(p)
        end
    end

    function GC.TeleportArmy(A)
        if A.dead then return end
        local ax, ay = XY(A.cell)
        local best, bd
        for i = 1, GCN do
            if GC.owner[i] == A.owner and GC.build[i] ~= GC.B_CRATER and not GC.army[i] and not GC.Biomes[GC.biome[i]].water then
                local x, y = XY(i)
                local d = (x - ax) ^ 2 + (y - ay) ^ 2
                if not bd or d < bd then best, bd = i, d end
            end
        end
        if not best then
            local owner = A.owner
            RemoveArmy(A)
            Notify(owner, "Your army had nowhere to go and was lost.")
            return
        end
        Detach(A)
        if #A.attackers > 0 then EndAllBattles(A) end
        A.state, A.target, A.claim, A.route, A.autoId = GC.ST_IDLE, 0, false, nil, nil
        RawMoveArmy(A, best)
        Notify(A.owner, "Your army was moved to the nearest own cell.")
    end

    function GC.EvictFrom(grantor, grantee)
        local list = {}
        for _, A in pairs(GC.army) do
            if A.owner == grantee and not A.dead and GC.owner[A.cell] == grantor
                and not GC.Biomes[GC.biome[A.cell]].water then
                list[#list + 1] = A
            end
        end
        for _, A in ipairs(list) do GC.TeleportArmy(A) end
        return #list
    end

    function GC.CheckStranded()
        local list = {}
        for _, A in pairs(GC.army) do
            if not A.dead and not GC.Biomes[GC.biome[A.cell]].water then
                local o = GC.owner[A.cell]
                if o ~= A.owner and not GC.HasAccess(A.owner, o) then list[#list + 1] = A end
            end
        end
        for _, A in ipairs(list) do GC.TeleportArmy(A) end
    end

    local function CancelPactAttacks(a, b)
        local list = {}
        for _, A in pairs(GC.army) do
            if A.state == GC.ST_ATTACK and (A.owner == a or A.owner == b) then list[#list + 1] = A end
        end
        for _, A in ipairs(list) do
            local D = A.foe or GC.army[A.target]
            local eo = D and D.owner or GC.owner[A.target]
            if (A.owner == a and eo == b) or (A.owner == b and eo == a) then CancelAttack(A) end
        end
    end

    local resFields = { "coins", "weapons", "pop" }
    local resNames = { "coins", "weapons", "population" }

    local function DipCool(ply, key, sec)
        ply.GCDip = ply.GCDip or {}
        local now = CurTime()
        local t = ply.GCDip[key]
        if t and t > now then return math.ceil(t - now) end
        ply.GCDip[key] = now + sec
    end

    local function DipNotify(to, from, msg)
        if GC.muted[to * 256 + from] then return end
        Notify(to, msg)
    end

    net.Receive("GCapture_Diplo", function(_, ply)
        if GC.State ~= "playing" then return end
        local slot = GC.SlotOf[ply]
        if not slot then return end

        local kind, target = net.ReadUInt(4), net.ReadUInt(8)
        local T, P = GC.Slots[target], GC.Slots[slot]
        local function Fail(msg) SendMsg(ply, msg) end
        if not T or target == slot then return end
        if not T.bot and not IsValid(T.ply) then return Fail("Player unavailable.") end
        local now = CurTime()

        local function Cool(key, sec, global)
            local w = DipCool(ply, "any", 1) or DipCool(ply, global and key or (key .. target), sec)
            if w then Fail("Diplomacy cooldown: wait " .. w .. " sec.") return true end
        end
        local function Blocked()
            if GC.muted[target * 256 + slot] then
                Fail(T.name .. " has severed relations with you.")
                return true
            end
        end

        if kind == 1 then
            if Blocked() then return end
            if GC.HasPact(slot, target) then return Fail("A pact is already in effect.") end
            if T.bot then
                if Cool("pact", 15) then return end
                if GC.BotPactDecision(target, slot) then GC.SignPact(slot, target)
                else Notify(slot, T.name .. " declined the non-aggression pact.") end
                return
            end
            if T.ply:IsBot() then return Fail("A bot can't accept a pact.") end
            if Cool("pact", 15) then return end
            GC.offers[slot * 256 + target] = now
            net.Start("GCapture_Diplo")
            net.WriteUInt(1, 2)
            net.WriteUInt(slot, 8)
            net.WriteString(P.name)
            net.Send(T.ply)
            Notify(slot, "Pact offer sent to: " .. T.name)

        elseif kind == 2 then
            if T.bot or T.ply:IsBot() then return Fail("A bot doesn't read letters.") end
            if Blocked() then return end
            local text = string.Trim(net.ReadString() or "")
            local len = utf8.len(text)
            if not len then return end
            if len > GC.LetterMax then text = string.sub(text, 1, utf8.offset(text, GC.LetterMax + 1) - 1) end
            if text == "" then return end
            if Cool("letter", 3, true) then return end
            net.Start("GCapture_Diplo")
            net.WriteUInt(2, 2)
            net.WriteUInt(slot, 8)
            net.WriteString(P.name)
            net.WriteString(text)
            net.Send(T.ply)
            Notify(slot, "Letter sent to: " .. T.name)

        elseif kind == 3 then
            local res, amount = net.ReadUInt(2), net.ReadUInt(16)
            local f = resFields[res]
            if not f or amount < 1 then return end
            if P[f] < amount then return Fail("Not enough resources.") end
            if Blocked() then return end
            if Cool("donate", 2, true) then return end
            P[f] = P[f] - amount
            if f == "coins" then AddCoins(T, amount)
            elseif f == "pop" then AddPop(target, T, amount)
            else T[f] = T[f] + amount end
            GC.SendStats()
            Notify(slot, "You gave " .. amount .. " " .. resNames[res] .. " to " .. T.name)
            Notify(target, P.name .. " gave you " .. amount .. " " .. resNames[res] .. "!")

        elseif kind == 4 then
            local accept = net.ReadBool()
            local key = target * 256 + slot
            local t0 = GC.offers[key]
            if not t0 or now - t0 > 40 then return Fail("The offer has expired.") end
            GC.offers[key] = nil
            if not accept then return DipNotify(target, slot, P.name .. " declined the non-aggression pact.") end
            if GC.HasPact(slot, target) then return end
            GC.SignPact(slot, target)

        elseif kind == 5 then
            if T.bot or T.ply:IsBot() then return Fail("Bots can't use military access.") end
            local key = slot * 256 + target
            if GC.access[key] then return Fail("They already have access to your land.") end
            if Cool("access", 5) then return end
            GC.access[key] = true
            GC.SendAccess()
            Notify(slot, "Military access granted to " .. T.name .. ". Neither side can attack while it's open.")
            DipNotify(target, slot, P.name .. " allowed your troops to enter their territory.")

        elseif kind == 6 then
            local key = slot * 256 + target
            if not GC.access[key] then return Fail("That country has no access to your land.") end
            if Cool("access", 5) then return end
            GC.access[key] = nil
            local n = GC.EvictFrom(slot, target)
            GC.SendAccess()
            Notify(slot, "Military access closed" .. (n > 0 and (": " .. n .. " foreign armies were sent back.") or "."))
            DipNotify(target, slot, P.name .. " closed their territory to your troops.")

        elseif kind == 7 then
            if not T.bot and T.ply:IsBot() then return Fail("A bot can't grant military access.") end
            if Blocked() then return end
            if GC.access[target * 256 + slot] then return Fail("You already have access to their land.") end
            if Cool("req", 20) then return end
            if T.bot then
                if GC.BotAccessDecision(target, slot) then GC.GrantBotAccess(target, slot)
                else Notify(slot, T.name .. " refused to let your troops in.") end
                return
            end
            GC.accReq[slot * 256 + target] = now
            net.Start("GCapture_Diplo")
            net.WriteUInt(3, 2)
            net.WriteUInt(slot, 8)
            net.WriteString(P.name)
            net.Send(T.ply)
            Notify(slot, "Military access request sent to: " .. T.name)

        elseif kind == 8 then
            local accept = net.ReadBool()
            local key = target * 256 + slot
            local t0 = GC.accReq[key]
            if not t0 or now - t0 > 40 then return Fail("The request has expired.") end
            GC.accReq[key] = nil
            if not accept then return DipNotify(target, slot, P.name .. " refused to let your troops in.") end
            GC.access[slot * 256 + target] = true
            GC.SendAccess()
            Notify(slot, "Military access granted to " .. T.name .. ".")
            DipNotify(target, slot, P.name .. " allowed your troops to enter their territory.")

        elseif kind == 9 then
            if Cool("rel", 10) then return end
            local key = slot * 256 + target
            if GC.muted[key] then
                GC.muted[key] = nil
                Notify(slot, "Relations with " .. T.name .. " restored.")
                DipNotify(target, slot, P.name .. " restored relations with you.")
            else
                GC.muted[key] = true
                Notify(slot, "Relations with " .. T.name .. " severed: you won't get their messages.")
                DipNotify(target, slot, P.name .. " severed relations with you.")
            end
            GC.SendAccess(ply)
        end
    end)

    GC.BotDiff = {
        [0] = { name = "Easy", think = { 3.0, 5.0 }, acts = 1, buyChance = 0.6, shuffle = true, expN = 1, expChance = 0.35,
            capBase = 8, capPerMin = 1.2, grace = 420, peace = 300, warLen = { 40, 80 }, lullLen = { 60, 120 }, focus = true,
            atkChance = 0.25, moveChance = 0.35, armyMult = 0.5, noise = 40, navy = false, navDelay = 1e9,
            air = false, airChance = 0, orgRest = 0.30, orgGo = 0.60, fightMargin = 0.7, pact = 0.5 },
        [1] = { name = "Normal", think = { 1.8, 3.0 }, acts = 2, buyChance = 0.8, shuffle = true, expN = 1, expChance = 0.6,
            capBase = 14, capPerMin = 2.5, grace = 240, peace = 150, warLen = { 60, 120 }, lullLen = { 30, 70 }, focus = true,
            capPush = true, atkChance = 0.5, moveChance = 0.6, armyMult = 0.7, noise = 25, navy = true, navDelay = 90, navInit = 0.4, navCool = 110, navReach = 24, cgBomb = 0.3,
            air = true, airChance = 0.35, orgRest = 0.40, orgGo = 0.70, fightMargin = 0.85, pact = 0.25 },
        [2] = { name = "Hard", think = { 1.0, 1.6 }, acts = 3, buyChance = 0.95, shuffle = true, expN = 2, expChance = 0.85,
            capBase = 22, capPerMin = 4, grace = 100, peace = 50, warLen = { 90, 180 }, lullLen = { 10, 30 }, focus = true,
            capPush = true, coast = true, coastMax = 2, atkChance = 0.8, moveChance = 0.85, armyMult = 0.9, noise = 12, navy = true, navDelay = 40, navInit = 0.7, navCool = 55, navReach = 18, cgBomb = 0.5,
            air = true, airChance = 0.7, orgRest = 0.45, orgGo = 0.80, fightMargin = 1.0, pact = 0.05 },
        [3] = { name = "Emperor", think = { 0.5, 0.7 }, acts = 999, buyChance = 1, shuffle = false, expN = 3, expChance = 1,
            capBase = 1e9, capPerMin = 0, grace = 0, peace = 0, focus = false,
            capPush = true, atkChance = 1, moveChance = 1, armyMult = 1, noise = 0, navy = true, navDelay = 0,
            air = true, airChance = 1, orgRest = 0.5, orgGo = 0.85, fightMargin = 1.1, pact = 0,
            navMul = 0.2, navOrg = 4, coast = true, chestFirst = true, navPush = true,
            navInit = 1, navCool = 0, navReach = 8, cgBomb = 0.8 },
    }

    local NB4, NB8 = {}, {}
    function GC.RebuildNB()
        NB4, NB8 = {}, {}
        for i = 1, GCN do NB4[i], NB8[i] = GC.Neighbors(i), GC.Neighbors8(i) end
    end
    GC.RebuildNB()
    local WATER = GC.WATER
    local landComp = {}

    local STRUCT_VALUE = { [GC.B_VILLAGE] = 25, [GC.B_WEAPONRY] = 22, [GC.B_ARMYC] = 25, [GC.B_CAVC] = 22,
        [GC.B_AIR] = 30, [GC.B_OIL] = 12, [GC.B_CHEST] = 8, [GC.B_COAST] = 10 }
    local BOMB_VALUE = { [GC.B_AIR] = 45, [GC.B_ARMYC] = 38, [GC.B_VILLAGE] = 30, [GC.B_WEAPONRY] = 28, [GC.B_CAVC] = 28,
        [GC.B_OIL] = 15, [GC.B_BARRICADE] = 12, [GC.B_COAST] = 10, [GC.B_TRAP] = 8, [GC.B_CAPITAL] = 6, [GC.B_CHEST] = 4 }

    local function Cheb(a, b)
        local ax, ay = XY(a)
        local bx, by = XY(b)
        return math.max(math.abs(ax - bx), math.abs(ay - by))
    end

    local function Hostile(slot, j)
        if GC.biome[j] == WATER then return false end
        local D = GC.army[j]
        local o = D and D.owner or GC.owner[j]
        return o ~= 0 and o ~= slot and not GC.Friendly(slot, o)
    end

    local function Afford(P, a)
        return P.coins >= (a.coins or 0) and P.pop >= (a.pop or 0) and P.weapons >= (a.weapons or 0)
    end

    local function DistField(slot, goals)
        local d, q = {}, {}
        for c in pairs(goals) do d[c] = 0 q[#q + 1] = c end
        local h = 1
        while h <= #q do
            local c = q[h]
            h = h + 1
            for _, j in ipairs(NB8[c]) do
                if d[j] == nil and GC.owner[j] == slot then d[j] = d[c] + 1 q[#q + 1] = j end
            end
        end
        return d
    end

    local function StepDown(A, field)
        local cur = field[A.cell]
        if not cur then return end
        local best, bd = nil, cur
        for _, j in ipairs(NB8[A.cell]) do
            local dj = field[j]
            if dj and dj < bd and GC.build[j] ~= GC.B_CRATER and not GC.army[j] and GC.owner[j] == A.owner then best, bd = j, dj end
        end
        return best
    end

    local function Strength(slot)
        local n = 0
        for _, A in pairs(GC.army) do
            if A.owner == slot then n = n + (A.cav and 1.2 or 1) * (A.hp / math.max(1, A.maxHp)) end
        end
        return n
    end

    local function Wanted(S, o)
        if o == S.target and S.allowed then return true end
        if S.threatBy[o] then return true end
        if S.d.focus then return false end
        return S.allowed
    end

    local function FightRates(A, D, mid, natkOverride)
        local C = GC.Combat
        local ab, db = GC.biome[A.cell], GC.biome[D.cell]
        local ac = C.AttackChance + GC.AttackMods(A.owner, A.cav, ab, D.owner) + (ab == GC.TUNDRA and C.TundraAttack or 0)
        local dc = C.DefenseChance + GC.DefenseMods(D.owner, D.cav, db) + (db == GC.TUNDRA and C.TundraDefense or 0)
        ac = ac + GC.NightAtk()
        ac, dc = math.Clamp(ac, 0.02, 0.98), math.Clamp(dc, 0, 0.98)
        local natk = natkOverride or math.max(1, #D.attackers + (mid and 0 or 1))
        return ac * natk, (1 - ac) + dc
    end

    local function WinsFight(A, D, margin, mid, natk)
        local dLoss, aLoss = FightRates(A, D, mid, natk)
        local tKill = D.org / math.max(0.05, dLoss)
        local tDie = A.org / math.max(0.05, aLoss)
        local ratio = tDie / math.max(0.1, tKill)
        return ratio >= margin, ratio
    end

    local function ComputeLandComp()
        landComp = {}
        local nc = 0
        for i = 1, GCN do
            if not landComp[i] and GC.biome[i] ~= WATER then
                nc = nc + 1
                landComp[i] = nc
                local q, h = { i }, 1
                while h <= #q do
                    local c = q[h]
                    h = h + 1
                    for _, j in ipairs(NB8[c]) do
                        if not landComp[j] and GC.biome[j] ~= WATER then landComp[j] = nc q[#q + 1] = j end
                    end
                end
            end
        end
    end
    GC.RefreshLand = ComputeLandComp

    local W_BASE = { coins = 3, pop = 1.2, weapons = 3, oilCoin = 0.15, oilLife = 0.3, coastRange = 1, org = 1.2, hp = 1,
        attack = 40, defense = 40, fog = 0.6, airRange = 0.5, train = -0.2, upkeep = -5, cavAttack = 12, cavDefense = 12,
        cavMove = -4, cavHp = 0.5, cavOrg = 0.5, cavTrain = -0.1, cavUpkeep = -2, move = -8 }
    local W_KIND = {
        aggr = { attack = 1.6, org = 1.4, hp = 1.3, weapons = 1.5, train = 1.3, cavAttack = 1.4 },
        def  = { coins = 1.6, pop = 1.5, defense = 1.5, upkeep = 1.3 },
    }

    function GC.PickFor(slot, opts)
        local P = GC.Slots[slot]
        local b = P and P.bot
        if not b then return opts[math.random(#opts)] end
        local best, bs
        for _, inst in ipairs(opts) do
            local d = GC.SpiritDefs[inst.id]
            local sc = math.random() * 0.5
            local km = W_KIND[b.kind] or {}
            if d.mods then
                for k, v in pairs(d.mods) do sc = sc + v * (W_BASE[k] or 0) * (km[k] or 1) end
            end
            if d.vs then
                for k, v in pairs(d.vs) do sc = sc + v * (W_BASE[k] or 0) * 0.5 end
            end
            if d.biome then
                for _, bm in pairs(d.biome) do
                    for k, v in pairs(bm) do sc = sc + v * (W_BASE[k] or 0) * 0.2 end
                end
            end
            if not bs or sc > bs then best, bs = inst, sc end
        end
        return best
    end

    function GC.PickBotKind(di)
        local bt = GC.Opts.btype or 0
        if di == 3 or bt == 1 then return "aggr" end
        if bt == 2 then return "def" end
        return math.random() < 0.5 and "aggr" or "def"
    end

    function GC.NewBotSlot(s, hue, num, force, name)
        local now = CurTime()
        local di = GC.Opts.diff or 1
        if di == 4 then di = math.random(0, GC.Opts.emperor and 3 or 2) end
        if force then di = force end
        local d = GC.BotDiff[di]
        local P = {
            ply = nil, name = name or string.format("Bot%02d", num or s), color = HSVToColor(hue, 0.5, 0.78),
            coins = GC.Opts.rush and 1000 or GC.StartResources.coins, pop = GC.StartResources.pop,
            weapons = GC.StartResources.weapons, spirits = {},
            bot = { kind = GC.PickBotKind(di), d = d, nextThink = now + math.Rand(0.5, 2.5) + d.think[1], visT = 0 },
        }
        GC.BotReset(P.bot)
        return P
    end

    function GC.BotReset(b)
        local now, d = CurTime(), b.d
        b.start, b.offAt, b.peaceUntil, b.war = now, now + d.grace, 0, true
        b.phaseEnd = now + d.grace + (d.warLen and math.Rand(d.warLen[1], d.warLen[2]) or 1e9)
        b.nextNav = now + d.navDelay
        b.cool, b.rest, b.idleShip, b.shipT = {}, {}, {}, {}
        b.target, b.nav = nil, nil
        b.nextFlip = now + 30
    end

    function GC.InitBots()
        ComputeLandComp()
        local bots = {}
        for s, P in ipairs(GC.Slots) do
            if P.bot then
                GC.BotReset(P.bot)
                bots[#bots + 1] = P
            end
        end
        local bt = GC.Opts.btype or 0
        if #bots >= 2 and (bt == 0 or bt == 3) then
            local a = 0
            for _, P in ipairs(bots) do if P.bot.kind == "aggr" then a = a + 1 end end
            if a == 0 or a == #bots then
                local P = bots[math.random(#bots)]
                P.bot.kind = (P.bot.kind == "aggr") and "def" or "aggr"
            end
        end
        for _, P in ipairs(bots) do
            print(string.format("[GCapture] %s: %s, %s", P.name, P.bot.d.name, P.bot.kind == "aggr" and "aggressive" or "defensive"))
        end
    end

    function GC.SignPact(a, b)
        GC.pacts[GC.PactKey(a, b)] = CurTime() + GC.PactTime
        CancelPactAttacks(a, b)
        GC.SendPacts()
        Notify(a, "Non-aggression pact with " .. GC.Slots[b].name .. " signed for " .. GC.PactTime .. " sec.")
        Notify(b, "Non-aggression pact with " .. GC.Slots[a].name .. " signed for " .. GC.PactTime .. " sec.")
    end

    function GC.BotPactDecision(botSlot, fromSlot)
        local P = GC.Slots[botSlot]
        local b = P and P.bot
        if not b then return false end
        if b.kind ~= "def" then return math.random() < (b.d.pact or 0) end
        local mine, theirs = Strength(botSlot), Strength(fromSlot)
        if b.target == fromSlot and b.offense and mine > theirs * 1.5 then return false end
        if CurTime() - (b.hurtAt or -1000) < 60 then return true end
        if theirs >= mine * 0.8 then return true end
        return math.random() < 0.35
    end

    function GC.BotAccessDecision(botSlot, fromSlot)
        local P = GC.Slots[botSlot]
        local b = P and P.bot
        if not b then return false end
        if b.target == fromSlot then return false end
        local mine, theirs = Strength(botSlot), Strength(fromSlot)
        local chance
        if b.kind == "def" then
            chance = 0.55
            if CurTime() - (b.hurtAt or -1000) < 60 then chance = 0.9 end
            if theirs >= mine * 1.5 then chance = math.max(chance, 0.8) end
        else
            chance = math.min(0.6, (b.d.pact or 0) + 0.2)
        end
        if b.target and b.target ~= fromSlot then chance = chance + 0.25 end
        return math.random() < math.min(0.95, chance)
    end

    function GC.GrantBotAccess(botSlot, toSlot)
        local key = botSlot * 256 + toSlot
        GC.access[key] = true
        GC.accessExp[key] = CurTime() + GC.BotAccessTime
        CancelPactAttacks(botSlot, toSlot)
        GC.SendAccess()
        Notify(toSlot, GC.Slots[botSlot].name .. " allowed your troops to enter their territory for " .. GC.BotAccessTime
            .. " sec. Neither side can attack while it's open.")
    end

    local function BotBombard(slot, base, idx)
        local P = GC.Slots[slot]
        local owner, bl, ca = GC.owner[idx], GC.build[idx], GC.army[idx]
        P.weapons = P.weapons - (GC.Actions[20].weapons or 0)
        GC.airCd[base] = CurTime() + GC.AirCooldown
        for _, v in ipairs(ViewerList(true)) do
            net.Start("GCapture_AirCD")
            net.WriteUInt(base - 1, GCIB)
            net.WriteFloat(GC.AirCooldown)
            net.Send(v)
            if Sees(v, idx) then
                net.Start("GCapture_Boom")
                net.WriteUInt(idx - 1, GCIB)
                net.Send(v)
            end
        end
        if GC.Rec then
            GC.Rec.ev = GC.Rec.ev or {}
            table.insert(GC.Rec.ev, idx)
        end
        if bl == GC.B_CAPITAL then
            local OP = GC.Slots[owner]
            if OP then OP.coins = math.max(0, OP.coins - GC.CapitalBombPenalty) end
            Notify(owner, P.name .. " bombed your capital: -" .. GC.CapitalBombPenalty .. " coins")
        else
            GC.BombCell(idx, owner)
            Notify(owner, P.name .. " bombed your cell.")
        end
        GC.AddDiscontent(owner)
        if ca and ca.owner ~= slot then GC.BombArmy(ca) end
    end

    local NavFieldRef

    local function FleetThreats(S)
        local slot, b, now = S.slot, S.b, S.now
        if b.cgT and now < b.cgT then return b.cgSet end
        b.cgT = now + 3
        local pts = {}
        for i = 1, GCN do
            if GC.ship[i] == slot and #pts < 40 then pts[#pts + 1] = i end
        end
        local dd = NavFieldRef and NavFieldRef(S)
        if dd then
            local k = 0
            for w, v in pairs(dd) do
                if v == 0 then
                    k = k + 1
                    if k % 3 == 0 and #pts < 120 then pts[#pts + 1] = w end
                end
            end
        end
        local set = {}
        if #pts > 0 then
            for j = 1, GCN do
                if GC.build[j] == GC.B_COAST and Hostile(slot, j) and (not S.vis or S.vis[j]) then
                    local o = GC.owner[j]
                    local R = GC.CoastRange(o)
                    local cx, cy = XY(j)
                    for _, w in ipairs(pts) do
                        local wx, wy = XY(w)
                        if (wx - cx) ^ 2 + (wy - cy) ^ 2 <= R * R then set[j] = true break end
                    end
                end
            end
        end
        b.cgSet = set
        return set
    end

    local function BotAir(S)
        if not S.d.air or math.random() > S.d.airChance then return end
        local slot, now = S.slot, S.now
        if (S.cnt[GC.B_AIR] or 0) == 0 then return end
        if S.P.weapons < (GC.Actions[20].weapons or 0) then return end
        local R = GC.AirRange(slot)

        local cgSet
        if S.d.navy and (S.needNavy or S.b.nav) and math.random() < (S.d.cgBomb or 0) then cgSet = FleetThreats(S) end
        for _, base in ipairs(S.mine) do
            if GC.build[base] == GC.B_AIR and (GC.airCd[base] or 0) <= now and S.acts > 0 and S.P.weapons >= (GC.Actions[20].weapons or 0) then
                local bx, by = XY(base)
                local best, bs
                for y = math.max(0, by - R), math.min(GCH - 1, by + R) do
                    for x = math.max(0, bx - R), math.min(GCW - 1, bx + R) do
                        local j = y * GCW + x + 1
                        local cg = cgSet and cgSet[j]
                        if (not S.vis or S.vis[j]) and Hostile(slot, j)
                            and (cg or Wanted(S, (GC.army[j] and GC.army[j].owner) or GC.owner[j])) then
                            local bl, ca = GC.build[j], GC.army[j]
                            local sc = 0
                            if bl ~= 0 and bl ~= GC.B_FIRE then sc = BOMB_VALUE[bl] or 5 end
                            if cg and bl == GC.B_COAST then sc = 70 end
                            if ca and ca.owner ~= slot then
                                sc = sc + 18 - ca.hp + (ca.hp <= GC.BombHP[2] and 30 or 0)
                                if ca.state ~= GC.ST_IDLE then sc = sc + 8 end
                            end
                            if sc >= 10 and (not bs or sc > bs) then best, bs = j, sc end
                        end
                    end
                end
                if best then BotBombard(slot, base, best) S.acts = S.acts - 1 end
            end
        end
    end

    local function Snapshot(slot, P, b, now)
        local owner, build = GC.owner, GC.build
        local S = { slot = slot, P = P, b = b, now = now, mine = {}, n = 0, cnt = {}, caps = {}, cellsOf = {}, armiesOf = {},
            nv = {}, armies = {}, enemyArmies = {}, nA = 0, nC = 0, ownComps = {}, upkeep = 0, threatBy = {}, sup = {} }

        if FogOn() then
            if now >= (b.visT or 0) then b.vis, b.visT = ComputeVis(slot), now + 1 end
        else
            b.vis = nil
        end
        local vis = b.vis
        S.vis = vis

        local R, sup = GC.SupplyRadius, S.sup
        for i = 1, GCN do
            local o, bl = owner[i], build[i]
            if o ~= 0 then
                S.cellsOf[o] = (S.cellsOf[o] or 0) + 1
                if bl == GC.B_CAPITAL then S.caps[o] = i end
                if o == slot then
                    S.n = S.n + 1
                    S.mine[S.n] = i
                    if bl ~= 0 then S.cnt[bl] = (S.cnt[bl] or 0) + 1 end
                    if bl == GC.B_VILLAGE then
                        local cx, cy = XY(i)
                        for y = math.max(0, cy - R), math.min(GCH - 1, cy + R) do
                            for x = math.max(0, cx - R), math.min(GCW - 1, cx + R) do sup[y * GCW + x + 1] = true end
                        end
                    end
                end
            elseif bl == GC.B_VILLAGE then
                S.nv[#S.nv + 1] = i
            end
        end
        S.cap = S.caps[slot]
        S.hasSup = next(sup) ~= nil
        if S.n == 0 then return S end

        S.conn = GC.CapitalConnected(slot)
        for c in pairs(S.conn) do
            local k = landComp[c]
            if k then S.ownComps[k] = true end
        end

        for _, A in pairs(GC.army) do
            S.armiesOf[A.owner] = (S.armiesOf[A.owner] or 0) + 1
            if A.owner == slot then
                S.armies[#S.armies + 1] = A
                if A.cav then S.nC = S.nC + 1 else S.nA = S.nA + 1 end
                S.upkeep = S.upkeep + GC.UpkeepPerArmy(slot, A.cav)
            elseif not vis or vis[A.cell] then
                S.enemyArmies[#S.enemyArmies + 1] = A
            end
        end
        S.gross = math.max(0, (S.cnt[GC.B_VILLAGE] or 0) * (GC.Build[GC.B_VILLAGE].coin or 0) + GC.Mod(slot, "coins") - GC.DiscontentOf(slot))

        local dE, qe, dM, qm = {}, {}, {}, {}
        for i = 1, GCN do
            local o = owner[i]
            if o == slot then dM[i] = 0 qm[#qm + 1] = i
            elseif o ~= 0 and (not vis or vis[i]) then dE[i] = 0 qe[#qe + 1] = i end
        end
        local function Spread(d, q, cap)
            local h = 1
            while h <= #q do
                local c = q[h]
                h = h + 1
                local dc = d[c]
                if dc < cap then
                    for _, j in ipairs(NB8[c]) do
                        if d[j] == nil and GC.biome[j] ~= WATER then d[j] = dc + 1 q[#q + 1] = j end
                    end
                end
            end
        end
        Spread(dE, qe, 10)
        Spread(dM, qm, 4)
        S.dE, S.dM = dE, dM

        for _, E in ipairs(S.enemyArmies) do
            if not GC.Friendly(slot, E.owner) then
                local dm = dM[E.cell] or 9
                if dm <= 3 then
                    S.threat = true
                    S.threatBy[E.owner] = (S.threatBy[E.owner] or 0) + 1
                    if dm <= 2 then b.hurtAt = now end
                end
                if S.cap and Cheb(E.cell, S.cap) <= 5 then S.capThreat = true end
            end
        end
        if S.cap and (dE[S.cap] or 9) <= 3 then S.capThreat = true end
        return S
    end

    local function PickTarget(S)
        local slot, b = S.slot, S.b
        local best, bs
        for s in ipairs(GC.Slots) do
            local ecap = S.caps[s]
            if s ~= slot and ecap then
                local d = S.cap and Cheb(S.cap, ecap) or 20
                local reach = S.ownComps[landComp[ecap] or 0] and 0 or (S.d.navReach or 30)
                local sc
                if b.kind == "aggr" then
                    sc = -d - reach - (S.armiesOf[s] or 0) * 1.2 - (S.cellsOf[s] or 0) * 0.05
                else
                    sc = -d * 0.6 - reach - (S.armiesOf[s] or 0) * 3 - (S.cellsOf[s] or 0) * 0.2
                end
                sc = sc + (S.threatBy[s] or 0) * 8
                sc = sc + (math.random() - 0.5) * S.d.noise
                if GC.Friendly(slot, s) then sc = sc - 100 end
                if s == b.target then sc = sc + 6 end
                if not bs or sc > bs then best, bs = s, sc end
            end
        end
        return best
    end

    local function PlanTarget(S)
        local b, now, d = S.b, S.now, S.d

        if b.target and not S.caps[b.target] then
            b.target = nil
            b.peaceUntil = now + d.peace * math.Rand(0.7, 1.3)
        end
        if not b.target or now >= (b.retarget or 0) then
            b.target, b.retarget = PickTarget(S), now + math.Rand(8, 8 + d.noise)
        end
        S.target = b.target
        S.targetCap = b.target and S.caps[b.target] or nil
        S.targetComp = S.targetCap and landComp[S.targetCap] or nil

        if d.warLen and now >= b.phaseEnd then
            b.war = not b.war
            local r = b.war and d.warLen or d.lullLen
            b.phaseEnd = now + math.Rand(r[1], r[2])
        end
        S.allowed = now >= b.offAt and now >= (b.peaceUntil or 0) and b.war
        S.siege = nil
        if now >= b.offAt and S.cap then
            for o, cp in pairs(S.caps) do
                if o ~= S.slot and not GC.Friendly(S.slot, o) and (S.dM[cp] or 9) <= 2 then S.siege = o break end
            end
        end
        if S.siege then
            local cp = S.caps[S.siege]
            b.target, b.retarget = S.siege, now + 8
            S.target, S.targetCap, S.targetComp = S.siege, cp, landComp[cp]
            S.allowed = true
        end

        local n, V = S.nA + S.nC, S.cnt[GC.B_VILLAGE] or 0
        local off
        if b.kind == "aggr" then
            off = true
        else
            if n < 2 then b.offense = false
            elseif n >= 8 or (n >= 5 and V >= 3 and now - b.start > 180) then b.offense = true end
            off = b.offense or false
        end
        S.offense = off and S.allowed
        if S.siege then S.offense = true end
    end

    local function ExpandList(S)
        local slot, b = S.slot, S.b
        local seen, connSet, list = {}, {}, {}
        for _, i in ipairs(S.mine) do
            for _, j in ipairs(NB4[i]) do
                if GC.owner[j] == 0 and GC.biome[j] ~= WATER and not GC.army[j] then
                    if S.conn[i] then connSet[j] = true end
                    if not seen[j] then
                        seen[j] = true
                        local bl = GC.build[j]
                        local sc, val = GC.Biomes[GC.biome[j]].pop * 3 + 1, false
                        if bl == GC.B_VILLAGE then sc, val = sc + 40, true
                        elseif bl == GC.B_CHEST then sc, val = sc + (S.d.chestFirst and 36 or 14), true end
                        local own = 0
                        for _, k in ipairs(NB4[j]) do if GC.owner[k] == slot then own = own + 1 end end
                        sc = sc + own * 0.8
                        for _, v in ipairs(S.nv) do
                            local dd = Cheb(j, v)
                            if dd <= 6 then sc = sc + (7 - dd) * 0.5 end
                        end
                        if S.targetCap then sc = sc - Cheb(j, S.targetCap) * (b.kind == "aggr" and 0.25 or 0.08) end
                        local de = S.dE[j]
                        if de and b.kind == "aggr" then sc = sc + math.max(0, 5 - de) * 0.3 end
                        list[#list + 1] = { j, sc, val }
                    end
                end
            end
        end
        table.sort(list, function(x, y) return x[2] > y[2] end)
        S.expList, S.nExpConn = list, table.Count(connSet)
    end

    local function NavInit(S)
        local b, d, now = S.b, S.d, S.now
        if not d.navy or (d.navInit or 0) <= 0 then return false end
        if S.threat or S.capThreat or S.nA + S.nC < 3 or now < (b.navCool or 0) then return false end
        if now >= (b.navRoll or 0) then
            b.navRoll = now + math.Rand(20, 40)
            b.navOn = math.random() < d.navInit
            b.navKind = (S.offense and math.random() < 0.5) and "flank" or "island"
        end
        return b.navOn == true
    end

    local function PlanArmy(S)
        local slot, b, now, vis = S.slot, S.b, S.now, S.vis
        local front, frontT, isFront, nConn, nEdge = {}, {}, {}, 0, 0
        for _, i in ipairs(S.mine) do
            local hostile, tgt, armyAdj = false, false, false
            for _, j in ipairs(NB8[i]) do
                if (not vis or vis[j]) and Hostile(slot, j) then
                    hostile = true
                    local D = GC.army[j]
                    if D then armyAdj = true end
                    if (D and D.owner or GC.owner[j]) == S.target then tgt = true end
                end
            end
            if hostile then
                nEdge = nEdge + 1
                if S.conn[i] then nConn = nConn + 1 end
                if S.offense or armyAdj or (S.cap and Cheb(i, S.cap) <= 6) then
                    isFront[i] = true
                    if not GC.army[i] then
                        front[i] = true
                        if tgt then frontT[i] = true end
                    end
                end
            end
        end
        S.frontConn, S.isFront, S.nEdge = nConn, isFront, nEdge

        local kind
        if S.d.navy and S.n >= 5 then
            local overseas = S.targetComp and not S.ownComps[S.targetComp]
            if nConn == 0 and S.nExpConn == 0 then kind = "stuck"
            elseif overseas and (S.d.navPush or S.allowed) then kind = "target"
            elseif NavInit(S) then
                kind = b.navKind
                if kind == "flank" and not (S.offense and S.target and S.targetComp and S.ownComps[S.targetComp]) then kind = "island" end
            end
        end
        S.navKind, S.needNavy = kind, kind ~= nil

        local goals = next(frontT) and frontT or front
        S.fAny = (next(frontT) and next(front)) and DistField(slot, front) or nil
        S.stage = nil
        if not next(goals) then
            goals = {}
            local ref = (S.offense and S.targetCap) or S.cap
            local cand = {}
            for _, i in ipairs(S.mine) do
                cand[#cand + 1] = { i, -(ref and Cheb(i, ref) or 0) + (S.sup[i] and 2 or 0) }
            end
            table.sort(cand, function(x, y) return x[2] > y[2] end)
            for k = 1, math.min(#cand, #S.armies + 2) do goals[cand[k][1]] = true end
            S.stage = goals
        end
        S.fFront = DistField(slot, goals)

        local sg = {}
        for _, i in ipairs(S.mine) do
            if S.sup[i] and not GC.army[i] then sg[i] = true end
        end
        S.fSup = DistField(slot, sg)

        S.guardId = nil
        local n = S.nA + S.nC
        if S.cap and n >= 1 and (b.kind == "def" or S.capThreat) and not (b.kind == "aggr" and n < 2) then
            local onCap = GC.army[S.cap]
            if onCap and onCap.owner == slot then
                S.guardId = onCap.id
            else
                local fc = DistField(slot, { [S.cap] = true })
                local best, bd
                for _, A in ipairs(S.armies) do
                    local d = fc[A.cell]
                    if d and A.state == GC.ST_IDLE and GC.biome[A.cell] ~= WATER and A.org >= 3
                        and not (A.trainEnd and now < A.trainEnd) and not (b.nav and b.nav.aid == A.id)
                        and (not bd or d < bd) then best, bd = A, d end
                end
                S.guardId, S.fCap = best and best.id, fc
            end
        end
    end

    local function BuyBuild(S, act, cell)
        if S.acts <= 0 then return false end
        local a, P, slot = GC.Actions[act], S.P, S.slot
        if not cell or not Afford(P, a) then return false end
        if GC.owner[cell] ~= slot or GC.build[cell] ~= 0 then return false end
        if a.build == GC.B_OIL and GC.oilUsed[cell] then return false end
        if a.build == GC.B_AIR and not GC.AirbaseUnlocked() then return false end
        if not GC.CanBuildAt(slot, cell) then return false end
        P.coins, P.pop, P.weapons = P.coins - (a.coins or 0), P.pop - (a.pop or 0), P.weapons - (a.weapons or 0)
        GC.Place(cell, slot, a.build)
        S.acts = S.acts - 1
        return true
    end

    local function PickCell(S, kind)
        local slot, aggr = S.slot, S.b.kind == "aggr"
        local best, bs
        for _, i in ipairs(S.mine) do
            if GC.build[i] == 0 and S.conn[i] then
                local de, sup, sc = S.dE[i] or 9, S.sup[i], nil
                if kind == "village" then
                    local cx, cy, R, un = 0, 0, GC.SupplyRadius, 0
                    cx, cy = XY(i)
                    for y = math.max(0, cy - R), math.min(GCH - 1, cy + R) do
                        for x = math.max(0, cx - R), math.min(GCW - 1, cx + R) do
                            local j = y * GCW + x + 1
                            if GC.owner[j] == slot and not S.sup[j] then un = un + 1 end
                        end
                    end
                    sc = un + (aggr and math.max(0, 6 - de) * 0.8 or math.min(de, 6) * 0.5) - (de <= 1 and 5 or 0)
                    if S.b.needSupCell and (S.now - (S.b.needSup or -1e9)) < 30 then
                        sc = sc - Cheb(i, S.b.needSupCell) * 0.8
                    end
                elseif kind == "weap" then
                    sc = -math.abs(de - 5) * 0.6 + (sup and 1 or 0) - (de <= 2 and 6 or 0)
                elseif kind == "center" or kind == "cavcenter" then
                    if not GC.army[i] then sc = (sup and 4 or 0) - math.abs(de - 3) - (de <= 1 and 8 or 0) end
                elseif kind == "airbase" then
                    if de >= 2 then sc = -math.abs(de - 4) + (sup and 1 or 0) end
                elseif kind == "barricade" then
                    if de == 1 then
                        sc = 0
                        for _, j in ipairs(NB8[i]) do
                            if Hostile(slot, j) then sc = sc + 2 + (GC.army[j] and 4 or 0) end
                        end
                    end
                elseif kind == "coast" then
                    if GC.IsCoast(i) then
                        local wn = 0
                        for _, j in ipairs(NB8[i]) do if GC.biome[j] == WATER then wn = wn + 1 end end
                        sc = wn * 0.5 + (S.dE[i] and 2 or 0) - (GC.CoastGuardNear(i, slot) and 6 or 0)
                    end
                elseif kind == "oil" then
                    if GC.biome[i] == GC.DESERT and not GC.oilUsed[i] then sc = 0 end
                end
                if sc then
                    sc = sc + math.random() * 0.4
                    if not bs or sc > bs then best, bs = i, sc end
                end
            end
        end
        return best
    end

    local function DoChest(S)
        if S.acts <= 0 then return false end
        local P, slot = S.P, S.slot
        for _, i in ipairs(S.mine) do
            if GC.build[i] == GC.B_CHEST then
                local sp = GC.RollSpirit(slot)
                if not sp then return false end
                P.coins = P.coins - GC.Actions[21].coins
                GC.SetCell(i, slot, 0)
                GC.GiveSpirit(slot, sp)
                S.acts = S.acts - 1
                return true
            end
        end
        return false
    end

    local function BotUpgrade(S)
        if S.acts <= 0 then return end
        local P, slot = S.P, S.slot
        for _, i in ipairs(S.mine) do
            if GC.build[i] == GC.B_BARRICADE and S.conn[i] and (S.dE[i] or 9) <= 1 then
                local lvl = GC.blevel[i] or 1
                local cost = GC.BarricadeUpgrade[lvl]
                if lvl < GC.BarricadeMaxLevel and cost and P.coins >= cost + 100 then
                    P.coins = P.coins - cost
                    GC.SetCell(i, slot, GC.B_BARRICADE, lvl + 1)
                    S.acts = S.acts - 1
                    return true
                end
            end
        end
    end

    local function OilWorth(S)
        local o = GC.Build[GC.B_OIL]
        return math.max(0, o.coin + GC.Mod(S.slot, "oilCoin")) * math.max(1, o.lifetime + GC.Mod(S.slot, "oilLife")) >= 560
    end

    local function RearCount(S)
        if S.rearN then return S.rearN end
        local n, b = 0, S.b
        for _, A in ipairs(S.armies) do
            if A.state == GC.ST_IDLE and GC.biome[A.cell] ~= WATER and A.id ~= S.guardId and not b.rest[A.id]
                and not (b.nav and b.nav.aid == A.id) and not (S.isFront and S.isFront[A.cell])
                and not (S.stage and S.stage[A.cell]) then n = n + 1 end
        end
        S.rearN = n
        return n
    end

    local function BotRecruit(S)
        if S.acts <= 0 then return false end
        local P, slot, b = S.P, S.slot, S.b
        local aggr = b.kind == "aggr"
        local V = S.cnt[GC.B_VILLAGE] or 0
        if not (aggr or V >= 4 or S.threat or S.needNavy or S.now - b.start > 300) then return false end
        local maxA = aggr and (3 + math.floor(S.n / 5)) or (2 + math.floor(S.n / 9))
        maxA = math.max(1, math.floor(maxA * S.d.armyMult + 0.5))
        if S.needNavy and (S.d.navPush or (S.d.navInit or 0) > 0) then maxA = maxA + 2 end
        if S.threat then maxA = maxA + 2 end

        local need = math.ceil((S.nEdge or 0) * 0.7) + 3 + (S.threat and 2 or 0) + (S.needNavy and 2 or 0)
        maxA = math.min(maxA, need)
        if S.nA + S.nC >= maxA then return false end
        if RearCount(S) >= (S.d.name == "Emperor" and 3 or 2) then return false end

        local armC, cavC = S.cnt[GC.B_ARMYC] or 0, S.cnt[GC.B_CAVC] or 0
        local wantCav = cavC > 0 and (S.nC * (aggr and 2 or 3) <= S.nA)
        for _, cav in ipairs(wantCav and { true, false } or { false, true }) do
            if (cav and cavC or armC) > 0 then
                local a = GC.Actions[cav and 28 or 13]
                local ratio = (aggr and 0.9 or 0.6) + (S.threat and 0.3 or 0)
                if S.upkeep + GC.UpkeepPerArmy(slot, cav) <= S.gross * ratio + 0.5 and Afford(P, a) then
                    for _, i in ipairs(S.mine) do
                        if GC.build[i] == (cav and GC.B_CAVC or GC.B_ARMYC) and S.conn[i] and GC.CanSpawnArmy(slot, i, cav)
                            and GC.CanBuildAt(slot, i) then
                            P.coins, P.pop, P.weapons = P.coins - (a.coins or 0), P.pop - (a.pop or 0), P.weapons - (a.weapons or 0)
                            CreateArmy(slot, i, false, cav)
                            S.acts = S.acts - 1
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    local function BotEconomy(S)
        local P, b = S.P, S.b
        local aggr = b.kind == "aggr"
        local cnt = S.cnt
        local V, Wp, AC, CC, AB = cnt[GC.B_VILLAGE] or 0, cnt[GC.B_WEAPONRY] or 0, cnt[GC.B_ARMYC] or 0, cnt[GC.B_CAVC] or 0, cnt[GC.B_AIR] or 0
        local chest = (cnt[GC.B_CHEST] or 0) > 0
        local cells, t, nA = S.n, S.now - b.start, S.nA + S.nC
        local CG = cnt[GC.B_COAST] or 0

        BotRecruit(S)
        if S.threat and P.coins >= 200 then BotUpgrade(S) end

        local plan = {}
        local function Want(c, act, kind, tag) if c then plan[#plan + 1] = { act, kind, tag } end end
        Want(S.d.chestFirst and chest, 21, "chest")
        Want((S.now - (b.needSup or -1e9)) < 30 and S.now >= (b.supCd or 0), 2, "village", true)
        Want(S.d.coast and cells >= 10 and CG < math.min(S.d.coastMax or 3, 1 + math.floor(cells / 25)), 7, "coast")
        if aggr then
            Want(V < 2, 2, "village")
            Want(AC == 0 and (cells >= 4 or P.coins >= 350), 26, "center")
            Want(Wp == 0 and AC >= 1, 3, "weap")
            Want(chest, 21, "chest")
            Want(V < math.min(6, 1 + math.floor(cells / 8)), 2, "village")
            Want(Wp < math.min(4, 1 + math.floor(cells / 10)), 3, "weap")
            Want(AC < math.min(3, 1 + math.floor(nA / 4)) and nA >= 3, 26, "center")
            Want(CC == 0 and cells >= 20 and nA >= 3, 27, "cavcenter")
        else
            Want(V < 2, 2, "village")
            Want(chest and V >= 3, 21, "chest")
            Want(V < math.min(10, 3 + math.floor(cells / 6)), 2, "village")
            Want(Wp == 0 and V >= 3, 3, "weap")
            Want(AC == 0 and (V >= 4 or t > 240 or S.threat or S.needNavy), 26, "center")
            Want(Wp < math.min(3, 1 + math.floor(cells / 12)) and V >= 3, 3, "weap")
            Want(S.threat and P.coins >= 250 and (cnt[GC.B_BARRICADE] or 0) < math.min(4, 1 + math.floor(cells / 15)), 5, "barricade")
            Want(AC == 1 and cells >= 25 and nA >= 3, 26, "center")
            Want(CC == 0 and cells >= 35 and nA >= 4, 27, "cavcenter")
        end
        Want(S.d.air and AB == 0 and cells >= 25 and (S.threat or P.weapons >= 120 or (S.needNavy and (S.d.cgBomb or 0) > 0 and P.weapons >= 80)), 19, "airbase")
        Want(OilWorth(S) and P.coins >= 600, 6, "oil")

        for _, w in ipairs(plan) do
            local a = GC.Actions[w[1]]
            if Afford(P, a) then
                if S.acts <= 0 then return nil end
                local ok
                if w[2] == "chest" then ok = DoChest(S) else ok = BuyBuild(S, w[1], PickCell(S, w[2])) end
                if ok then
                    if w[3] then b.supCd = S.now + 40 end
                    return nil
                end
            elseif (a.weapons or 0) <= P.weapons and (a.pop or 0) <= P.pop then
                return a.coins
            end
        end
    end

    local function BotExpand(S, saving)
        local P, b, now, slot, d = S.P, S.b, S.now, S.slot, S.d
        local a = GC.Actions[1]
        if now < (b.expReady or 0) then return end
        local cap = d.capBase + d.capPerMin * (now - b.start) / 60
        local done = 0
        for _, e in ipairs(S.expList) do
            if done >= d.expN or S.acts <= 0 then break end
            local cell, val = e[1], e[3]
            if not val then
                if S.n + done >= cap then break end
                if math.random() > d.expChance then break end
            end
            if saving and not val and (done >= 1 or now < (b.nextExp or 0)) then break end
            if P.coins < a.coins or P.pop < a.pop then break end
            if GC.owner[cell] == 0 and not GC.army[cell] then
                P.coins, P.pop = P.coins - a.coins, P.pop - a.pop
                GC.SetCell(cell, slot, GC.build[cell])
                done = done + 1
                S.acts = S.acts - 1
                if saving and not val then b.nextExp = now + 10 / math.max(0.5, S.gross * 0.25) end
            end
        end
        if done > 0 then b.expReady = now + GC.ExpandTime * done end
    end

    local function IsLandTarget(S, j)
        local k = landComp[j]
        if not k then return false end
        local o, kind = GC.owner[j], S.navKind
        if kind == "flank" then
            return o ~= 0 and o == S.target and not GC.Friendly(S.slot, o) and S.dM[j] == nil
        end
        if S.ownComps[k] then return false end
        if o == S.slot then return GC.army[j] == nil end
        if kind == "island" then return o == 0 end
        return o == 0 or not GC.Friendly(S.slot, o)
    end

    local function WaterField(S, comp)
        local d, q = {}, {}
        for j = 1, GCN do
            local k = landComp[j]
            if k and (not comp or k == comp) and IsLandTarget(S, j) then
                for _, w in ipairs(NB8[j]) do
                    if GC.biome[w] == WATER and d[w] == nil then d[w] = 0 q[#q + 1] = w end
                end
            end
        end
        local h = 1
        while h <= #q do
            local c = q[h]
            h = h + 1
            for _, j in ipairs(NB4[c]) do
                if d[j] == nil and GC.biome[j] == WATER then d[j] = d[c] + 1 q[#q + 1] = j end
            end
        end
        return d, #q > 0
    end

    local function NavField(S)
        if S.targetComp and not S.ownComps[S.targetComp] then
            local d, has = WaterField(S, S.targetComp)
            if has then return d, true end
        end
        return WaterField(S, nil)
    end
    NavFieldRef = NavField

    local function BotNaval(S)
        local b, slot, P, now, d = S.b, S.slot, S.P, S.now, S.d
        local navMul, navOrg = d.navMul or 1, d.navOrg or 6
        local nav, refund = b.nav, GC.Actions[10].refund
        if nav and nav.kind then S.navKind = nav.kind end

        for i = 1, GCN do
            if GC.ship[i] ~= slot or GC.army[i] or (nav and nav.W == i) or GC.HasNeighbor(GC.owner, i, slot) then
                b.idleShip[i] = nil
            elseif not b.idleShip[i] then
                b.idleShip[i] = now
            elseif now - b.idleShip[i] > 8 then
                AddCoins(P, refund.coins)
                AddPop(slot, P, refund.pop)
                GC.SetShip(i, 0)
                b.idleShip[i] = nil
            end
        end
        if not d.navy or S.acts <= 0 then return end

        if nav then
            local A
            for _, x in ipairs(S.armies) do if x.id == nav.aid then A = x break end end
            if not A or A.dead or now - nav.t0 > 180 then b.nav, b.nextNav = nil, now + 25 * navMul return end

            if nav.phase == 1 then
                local W_ = nav.W
                local occ = GC.ship[W_]
                if (occ ~= 0 and occ ~= slot) or (GC.army[W_] and GC.army[W_].id ~= nav.aid) then
                    b.nav, b.nextNav = nil, now + 20 * navMul
                    return
                end
                if table.HasValue(NB8[W_], A.cell) then
                    if GC.ship[W_] == 0 then
                        local a = GC.Actions[9]
                        if P.coins >= a.coins and P.pop >= a.pop and GC.HasNeighbor(GC.owner, W_, slot) then
                            P.coins, P.pop = P.coins - a.coins, P.pop - a.pop
                            GC.SetShip(W_, slot)
                            S.acts = S.acts - 1
                        end
                    elseif A.state == GC.ST_IDLE and not GC.army[W_] and now >= A.nextMove and not (A.trainEnd and now < A.trainEnd) then
                        MoveArmy(A, W_)
                        nav.phase = 2
                        S.acts = S.acts - 1
                    end
                elseif A.state == GC.ST_IDLE and now >= A.nextMove then
                    local st = StepDown(A, nav.field)
                    if st then MoveArmy(A, st) S.acts = S.acts - 1 else b.nav, b.nextNav = nil, now + 20 * navMul end
                end
                return
            end

            if GC.biome[A.cell] ~= WATER then b.nav, b.nextNav = nil, now + 15 * navMul return end
            if A.state ~= GC.ST_IDLE or (A.trainEnd and now < A.trainEnd) then return end

            local bestTo, bs
            for _, j in ipairs(NB8[A.cell]) do
                if GC.biome[j] ~= WATER and IsLandTarget(S, j) and GC.CanArmyLand(slot, A.cell, j) then
                    local bl, o = GC.build[j], GC.owner[j]
                    local sc = (bl == GC.B_CAPITAL and 100 or 0) + (STRUCT_VALUE[bl] or 0) + (o == 0 and 8 or (o == slot and 4 or 20))
                    if GC.army[j] then sc = sc - 25 end
                    if S.targetCap then sc = sc - Cheb(j, S.targetCap) * 0.5 end
                    if not bs or sc > bs then bestTo, bs = j, sc end
                end
            end
            if bestTo then
                if GC.owner[bestTo] == slot then
                    if now >= A.nextMove then MoveArmy(A, bestTo) S.acts = S.acts - 1 end
                elseif StartAttack(A, bestTo) then
                    S.acts = S.acts - 1
                end
                return
            end

            local dd = nav.d
            if not dd or now > (nav.dt or 0) then dd = NavField(S) nav.d, nav.dt = dd, now + 2 end
            local cur, opts = dd[A.cell] or 1e9, {}
            for _, j in ipairs(NB4[A.cell]) do
                if GC.biome[j] == WATER and dd[j] then
                    if GC.ship[j] == slot and not GC.army[j] and not GC.HasNeighbor(GC.owner, j, slot) then
                        AddCoins(P, refund.coins)
                        AddPop(slot, P, refund.pop)
                        GC.SetShip(j, 0)
                    end
                    if GC.ship[j] == 0 then opts[#opts + 1] = j end
                end
            end
            table.sort(opts, function(x, y) return dd[x] < dd[y] end)
            local nxt = opts[1]
            if nxt and dd[nxt] >= cur then nxt = nil end
            if not nxt then
                nav.stuck = (nav.stuck or 0) + 1
                if nav.stuck >= 4 then
                    local alt = {}
                    for _, j in ipairs(opts) do if j ~= nav.prev then alt[#alt + 1] = j end end
                    nxt = #alt > 0 and alt[math.random(#alt)] or nil
                end
                if nav.stuck > 30 then b.nav, b.nextNav = nil, now + 20 * navMul return end
            end
            if nxt then
                nav.prev, nav.stuck = A.cell, 0
                GC.SetShip(A.cell, 0)
                GC.SetShip(nxt, slot)
                RawMoveArmy(A, nxt)
                S.acts = S.acts - 1
            end
            return
        end

        if not S.needNavy or now < (b.nextNav or 0) then return end
        local kind = S.navKind or "stuck"
        local A, spare = nil, 0
        for _, x in ipairs(S.armies) do
            if x.id ~= S.guardId and x.state == GC.ST_IDLE and x.org >= navOrg and GC.biome[x.cell] ~= WATER
                and not (x.trainEnd and now < x.trainEnd) and not b.rest[x.id] then
                spare = spare + 1
                if not A then A = x end
            end
        end
        if not A then return end
        if kind ~= "stuck" then
            if spare < 2 or not Afford(P, GC.Actions[9]) then b.nextNav = now + 15 return end
        end
        local dd, has = NavField(S)
        if not has then b.nextNav = now + 30 * navMul return end
        local bw, bsc
        for _, i in ipairs(S.mine) do
            if S.conn[i] then
                for _, w in ipairs(NB4[i]) do
                    if GC.biome[w] == WATER and GC.ship[w] == 0 and not GC.army[w] and dd[w] then
                        local sc = dd[w] + Cheb(w, A.cell) * 0.3
                        if not bsc or sc < bsc then bw, bsc = w, sc end
                    end
                end
            end
        end
        if not bw then b.nextNav = now + 30 * navMul return end
        local goals = {}
        for _, j in ipairs(NB8[bw]) do
            if GC.owner[j] == slot and not GC.army[j] then goals[j] = true end
        end
        b.nav = { W = bw, aid = A.id, phase = 1, t0 = now, field = DistField(slot, goals), kind = kind }
        if kind ~= "stuck" then b.navCool = now + (d.navCool or 0) end
    end

    local function BestAttack(S, A)
        local slot, b, d = S.slot, S.b, S.d
        local aggr = b.kind == "aggr"
        local minOrg = aggr and 2 or 3
        local best, bs
        for _, to in ipairs(NB8[A.cell]) do
            if (not S.vis or S.vis[to]) and Hostile(slot, to) then
                local D = GC.army[to]
                local eo = D and D.owner or GC.owner[to]
                if Wanted(S, eo) and not (D and D.state == GC.ST_ATTACK and D.foe) then
                    local bl = GC.build[to]
                    local isCap = (bl == GC.B_CAPITAL)
                    local sc, okay = STRUCT_VALUE[bl] or 0, true
                    if isCap then sc = sc + 1000 end
                    if D then

                        local allies = 1
                        for _, B in ipairs(S.armies) do
                            if B ~= A and B.state == GC.ST_IDLE and B.org >= minOrg
                                and not (B.trainEnd and S.now < B.trainEnd) and Cheb(B.cell, to) <= 1 then
                                allies = allies + 1
                            end
                        end
                        local win, ratio = WinsFight(A, D, d.fightMargin * (isCap and 0.6 or 1), false, #D.attackers + allies)
                        if not win and not (isCap and d.capPush) then okay = false end
                        sc = sc + 30 + math.min(ratio, 5) * 6 + (D.hp <= 3 and 8 or 0) + #D.attackers * 12
                    elseif bl == GC.B_BARRICADE then
                        sc = sc - 10 * (GC.blevel[to] or 1)
                    end
                    if eo == S.target then sc = sc + 10 end
                    if S.targetCap then sc = sc - (Cheb(to, S.targetCap) - Cheb(A.cell, S.targetCap)) * 2 end
                    if not S.offense and not D and not isCap and not (S.cap and Cheb(to, S.cap) <= 5) and not S.threatBy[eo] then okay = false end
                    if A.hp <= 2 and not isCap and not (D and D.org <= 2) then okay = false end
                    if A.org < minOrg and not isCap then okay = false end
                    if okay and (not bs or sc > bs) then best, bs = to, sc end
                end
            end
        end
        if best and bs >= (aggr and -70 or -20) then return best end
    end

    local function ShipToCoast(S, A)
        local slot, from = S.slot, A.cell
        local prev, q, h, goal = { [from] = false }, { from }, 1, nil
        while h <= #q and not goal do
            local c = q[h]
            h = h + 1
            for _, j in ipairs(NB4[c]) do
                if prev[j] == nil and GC.biome[j] == WATER and GC.ship[j] == 0 then
                    prev[j] = c
                    q[#q + 1] = j
                    for _, l in ipairs(NB8[j]) do
                        if GC.biome[l] ~= WATER and GC.owner[l] == slot and not GC.army[l] then goal = j break end
                    end
                    if goal then break end
                end
            end
        end
        if not goal then return false end
        local st = goal
        while prev[st] ~= from do st = prev[st] end
        GC.SetShip(from, 0)
        GC.SetShip(st, slot)
        RawMoveArmy(A, st)
        return true
    end

    local function Unload(S, A)
        local slot, now, b = S.slot, S.now, S.b
        for _, j in ipairs(NB8[A.cell]) do
            if GC.biome[j] ~= WATER and GC.owner[j] == slot and not GC.army[j] and now >= A.nextMove then
                MoveArmy(A, j)
                b.shipT[A.id] = nil
                return true
            end
        end
        for _, j in ipairs(NB8[A.cell]) do
            if GC.biome[j] ~= WATER and GC.owner[j] ~= slot and GC.CanArmyLand(slot, A.cell, j) then
                local D = GC.army[j]
                local eo = D and D.owner or GC.owner[j]
                if (eo == 0 or Wanted(S, eo)) and StartAttack(A, j) then return true end
            end
        end
        b.shipT[A.id] = b.shipT[A.id] or now
        if now - b.shipT[A.id] > 12 and ShipToCoast(S, A) then return true end
        return false
    end

    local function ArmyAI(S, A)
        local slot, b, now, d = S.slot, S.b, S.now, S.d
        if A.dead or (A.trainEnd and now < A.trainEnd) then return false end

        if GC.biome[A.cell] == WATER then
            if A.state == GC.ST_IDLE and not (b.nav and b.nav.aid == A.id) then return Unload(S, A) end
            return false
        end
        if b.nav and b.nav.aid == A.id then return false end

        if A.state == GC.ST_DEFENSE then
            local atk = A.attackers[1]
            if atk and A.cell ~= S.cap and FindRetreat(A) then
                local win = WinsFight(atk, A, 1, true)
                if A.org <= 1 or (A.org <= 2 and win) then
                    Rout(A, atk, false)
                    return true
                end
            end
            return false
        end

        if A.state == GC.ST_ATTACK then
            local D = A.foe
            if D then
                local _, ratio = WinsFight(A, D, 1, true)
                local isCap = GC.build[D.cell] == GC.B_CAPITAL
                local quit = d.fightMargin * 0.6 * (isCap and 0.5 or 1)
                if isCap and d.capPush then

                elseif (A.org <= 1 and D.org > A.org) or (ratio < quit and D.org > 2) then
                    CancelAttack(A)
                    b.rest[A.id] = true
                    b.cool[A.id] = now + math.Rand(20, 40)
                    return true
                end
            end
            return false
        end
        if A.state ~= GC.ST_IDLE then return false end
        A.route = nil

        if S.guardId == A.id then
            if A.cell ~= S.cap and S.fCap and now >= A.nextMove then
                local st = StepDown(A, S.fCap)
                if st then MoveArmy(A, st) return true end
            end
            return false
        end

        if A.org >= 1 then
            for _, to in ipairs(NB8[A.cell]) do
                local G = GC.army[to]
                if GC.build[to] == GC.B_CAPITAL and (not G or (d.capPush and A.org >= 2 and not (G.state == GC.ST_ATTACK and G.foe)))
                    and (not S.vis or S.vis[to]) and Hostile(slot, to) then
                    local eo = GC.owner[to]
                    if (Wanted(S, eo) or S.siege == eo) and StartAttack(A, to) then
                        b.rest[A.id] = nil
                        return true
                    end
                end
            end
        end

        local low = math.max(2, math.floor(A.maxOrg * d.orgRest))
        if A.org < low then b.rest[A.id] = true end
        if b.rest[A.id] and A.org >= math.max(low + 1, math.floor(A.maxOrg * d.orgGo)) then b.rest[A.id] = nil end
        if b.rest[A.id] and not S.hasSup then
            b.rest[A.id] = nil
            b.needSup, b.needSupCell = now, A.cell
        end
        if b.rest[A.id] and S.hasSup then
            if S.sup[A.cell] then return false end
            local st = StepDown(A, S.fSup)
            if st then
                if now >= A.nextMove then MoveArmy(A, st) return true end
                return false
            end
            b.rest[A.id] = nil
            b.needSup, b.needSupCell = now, A.cell
        end

        if A.org >= 1 and (b.cool[A.id] or 0) <= now and math.random() < d.atkChance then
            local to = BestAttack(S, A)
            if to and StartAttack(A, to) then return true end
        end

        if d.capPush and S.siege and S.targetCap and A.org >= 2 and now >= A.nextMove then
            local cur = Cheb(A.cell, S.targetCap)
            if cur > 1 and cur <= 6 then
                local bestTo, bd
                for _, to in ipairs(NB8[A.cell]) do
                    if GC.biome[to] ~= WATER and GC.owner[to] == slot and not GC.army[to] then
                        local dd = Cheb(to, S.targetCap)
                        if dd < cur and (not bd or dd < bd) then bestTo, bd = to, dd end
                    end
                end
                if bestTo then MoveArmy(A, bestTo) return true end
            end
        end

        b.rearT = b.rearT or {}
        if S.isFront[A.cell] or (S.stage and S.stage[A.cell]) then b.rearT[A.id] = nil return false end
        if now >= A.nextMove and A.org >= 2 and math.random() < d.moveChance then
            local st = StepDown(A, S.fFront)
            if not st and S.fAny then st = StepDown(A, S.fAny) end
            if st then b.rearT[A.id] = nil MoveArmy(A, st) return true end
        end

        b.rearT[A.id] = b.rearT[A.id] or now
        if now - b.rearT[A.id] > 90 and RearCount(S) >= 3 then
            RemoveArmy(A)
            b.rearT[A.id] = nil
            S.rearN = RearCount(S) - 1
            return true
        end
        return false
    end

    local function BotArmies(S)
        local list = {}
        for _, A in ipairs(S.armies) do list[#list + 1] = A end
        if S.d.shuffle then table.Shuffle(list) end
        for _, A in ipairs(list) do
            if S.acts <= 0 then break end
            if not A.dead and GC.army[A.cell] == A and ArmyAI(S, A) then S.acts = S.acts - 1 end
        end
    end

    local function BotDiplomacy(S)
        local b, slot, now = S.b, S.slot, S.now
        if b.kind ~= "def" or not S.threat or now < (b.nextOffer or 0) then return end
        local h, hv = nil, 0
        for o, c in pairs(S.threatBy) do
            if not GC.Friendly(slot, o) and c > hv then h, hv = o, c end
        end
        if not h or Strength(h) <= Strength(slot) * 1.1 then return end
        b.nextOffer = now + 60
        local T = GC.Slots[h]
        if not T then return end
        if T.bot then
            if GC.BotPactDecision(h, slot) then GC.SignPact(slot, h) end
        elseif IsValid(T.ply) and not T.ply:IsBot() and not GC.muted[h * 256 + slot] then
            GC.offers[slot * 256 + h] = now
            net.Start("GCapture_Diplo")
            net.WriteUInt(1, 2)
            net.WriteUInt(slot, 8)
            net.WriteString(S.P.name)
            net.Send(T.ply)
        end
    end

    local function BotSink(S)
        local slot, P, d = S.slot, S.P, S.d
        if not d.coast or S.acts <= 0 or (S.cnt[GC.B_COAST] or 0) == 0 then return end
        local a = GC.Actions[12]
        for i = 1, GCN do
            local sh = GC.ship[i]
            if sh ~= 0 and sh ~= slot and P.weapons >= a.weapons and (not S.vis or S.vis[i])
                and not GC.Friendly(slot, sh) and Wanted(S, sh) and GC.CoastGuardNear(i, slot) then
                P.weapons = P.weapons - a.weapons
                local A = GC.army[i]
                if A then RemoveArmy(A) end
                GC.SetShip(i, 0)
                Notify(sh, P.name .. " sank your ship!")
                S.acts = S.acts - 1
                return
            end
        end
    end

    local function BotThink(slot, P, b)
        local S = Snapshot(slot, P, b, CurTime())
        if S.n == 0 then return end
        local d = b.d
        S.d, S.acts = d, d.acts
        PlanTarget(S)
        ExpandList(S)
        PlanArmy(S)

        local order = { "eco", "army", "navy", "air", "sink" }
        if d.shuffle then table.Shuffle(order) end
        for _, k in ipairs(order) do
            if k == "eco" then
                if math.random() < d.buyChance then
                    local saving = BotEconomy(S)
                    BotExpand(S, saving)
                end
            elseif k == "army" then BotArmies(S)
            elseif k == "navy" then S.acts = math.max(S.acts, 1) BotNaval(S)
            elseif k == "sink" then BotSink(S)
            else S.acts = math.max(S.acts, 1) BotAir(S) end
        end
        BotDiplomacy(S)
    end

    timer.Create("GCapture_Bots", 0.2, 0, function()
        if GC.State ~= "playing" then return end
        local now, budget = CurTime(), 5
        for s, P in ipairs(GC.Slots) do
            local b = P.bot

            if b and (GC.Opts.btype or 0) == 3 and b.d ~= GC.BotDiff[3] and now >= (b.nextFlip or 0) then
                b.nextFlip = now + 30
                if math.random() < 0.5 then b.kind = (b.kind == "aggr") and "def" or "aggr" end
            end
            if b and now >= b.nextThink and budget > 0 then
                budget = budget - 1
                b.nextThink = now + math.Rand(b.d.think[1], b.d.think[2])
                local ok, err = pcall(BotThink, s, P, b)
                if not ok then ErrorNoHalt("[GCapture] bot " .. P.name .. ": " .. tostring(err) .. "\n") end
            end
        end
    end)

    GC.EventBusy, GC.FogSuspend, GC.Virus = false, false, nil

    local function EvMsg(kind, title, arg)
        if GC.Rec then
            GC.Rec.evt = GC.Rec.evt or {}
            table.insert(GC.Rec.evt, { kind, title or "", arg or 0 })
        end
        local v = ViewerList(true)
        if #v == 0 then return end
        net.Start("GCapture_Event")
        net.WriteUInt(kind, 4)
        net.WriteString(title or "")
        net.WriteUInt(arg or 0, 8)
        net.Send(v)
    end
    local function Alive(id) return GC.State == "playing" and GC.GameId == id end

    function GC.SendBiomes(cells)
        local v = ViewerList(true)
        local a, CH = 1, 2500
        while a <= #cells and #v > 0 do
            local m = math.min(#cells, a + CH - 1)
            net.Start("GCapture_Biome")
            net.WriteUInt(m - a + 1, 15)
            for k = a, m do
                net.WriteUInt(cells[k] - 1, GCIB)
                net.WriteUInt(GC.biome[cells[k]], 3)
            end
            net.Send(v)
            a = m + 1
        end
        if GC.Rec then
            GC.Rec.bm = GC.Rec.bm or {}
            for _, c in ipairs(cells) do
                GC.Rec.bm[#GC.Rec.bm + 1], GC.Rec.bm[#GC.Rec.bm + 2] = c, GC.biome[c]
            end
        end
    end

    local function AfterTerrain()
        if GC.RefreshLand then GC.RefreshLand() end
        GC.SendStats()
        GC.CheckWin()
    end

    local function MeteorHit(idx)
        local owner, bl = GC.owner[idx], GC.build[idx]
        for _, v in ipairs(ViewerList(true)) do
            if Sees(v, idx) or (owner ~= 0 and GC.SlotOf[v] == owner) then
                net.Start("GCapture_Boom")
                net.WriteUInt(idx - 1, GCIB)
                net.Send(v)
            end
        end
        if GC.Rec then
            GC.Rec.ev = GC.Rec.ev or {}
            table.insert(GC.Rec.ev, idx)
        end

        if GC.biome[idx] == GC.WATER then
            local s = GC.ship[idx]
            if s ~= 0 then
                local A = GC.army[idx]
                if A then RemoveArmy(A) end
                GC.SetShip(idx, 0)
                Notify(s, "A meteor sank your ship.")
            end
            return
        end
        if bl == GC.B_CAPITAL then
            local P = GC.Slots[owner]
            if P then
                P.coins = math.max(0, P.coins - 1000)
                Notify(owner, "A meteor hit your capital: -1000 coins.")
                GC.SendStats()
            end
            return
        end
        local A = GC.army[idx]
        GC.SetCell(idx, owner, GC.B_CRATER)
        if A then
            A.hp = A.hp - GC.BombDamage
            if A.hp <= 0 then
                RemoveArmy(A)
                Notify(A.owner, "A meteor destroyed your army.")
            elseif GC.TeleportArmy then
                GC.TeleportArmy(A)
            else
                RemoveArmy(A)
            end
        end
        if owner ~= 0 then Notify(owner, "A meteor hit your land.") end
    end

    local function EventMeteors(id)
        local land = {}
        for i = 1, GCN do if GC.biome[i] ~= GC.WATER then land[#land + 1] = i end end
        if #land == 0 then return false end
        GC.EventBusy = true
        EvMsg(1, "METEOR SHOWER")
        local count = 0
        local function Next()
            timer.Simple(math.Rand(0.5, 3), function()
                if not Alive(id) then GC.EventBusy = false return end
                MeteorHit((math.random() < 0.75) and land[math.random(#land)] or math.random(GCN))
                count = count + 1
                if count >= 10 then GC.EventBusy = false GC.CheckWin() else Next() end
            end)
        end
        Next()
        return true
    end

    local function EventFlood()
        if GC.Opts.noocean then return false end
        local set, cells = {}, {}
        for i = 1, GCN do
            if GC.biome[i] == GC.WATER then
                for _, j in ipairs(GC.Neighbors(i)) do
                    if GC.biome[j] ~= GC.WATER and GC.build[j] ~= GC.B_CAPITAL and not set[j] then
                        set[j] = true
                        cells[#cells + 1] = j
                    end
                end
            end
        end
        if #cells == 0 then return false end
        EvMsg(2, "FLOOD")
        for _, j in ipairs(cells) do
            local A = GC.army[j]
            if A then
                Notify(A.owner, "Your army drowned in the flood.")
                RemoveArmy(A)
            end
            if GC.owner[j] ~= 0 or GC.build[j] ~= 0 then GC.SetCell(j, 0, 0) end
            GC.biome[j] = GC.WATER
        end
        GC.SendBiomes(cells)
        AfterTerrain()
        return true
    end

    local function EventDrain()
        local list, newB = {}, {}
        for i = 1, GCN do
            if GC.biome[i] == GC.WATER then
                local cnt, best, bc = {}, nil, 0
                for _, j in ipairs(GC.Neighbors(i)) do
                    local b = GC.biome[j]
                    if b ~= GC.WATER and b ~= 0 then
                        cnt[b] = (cnt[b] or 0) + 1
                        if cnt[b] > bc then best, bc = b, cnt[b] end
                    end
                end
                if best then list[#list + 1], newB[i] = i, best end
            end
        end
        if #list == 0 then return false end
        EvMsg(5, "DROUGHT")
        for _, i in ipairs(list) do
            local A = GC.army[i]
            if A then RemoveArmy(A) end
            if GC.ship[i] ~= 0 then
                Notify(GC.ship[i], "Your ship ran aground.")
                GC.SetShip(i, 0)
            end
            GC.biome[i] = newB[i]
        end
        GC.SendBiomes(list)
        AfterTerrain()
        return true
    end

    local function EventReveal(id)
        if not FogOn() then return false end
        GC.FogSuspend, GC.EventBusy = true, true
        EvMsg(3, "REVELATION")
        for _, p in ipairs(ViewerList(true)) do GC.SendFull(p) end
        timer.Simple(20, function()
            if GC.GameId ~= id then return end
            GC.FogSuspend, GC.EventBusy = false, false
            if GC.State ~= "playing" then return end
            EvMsg(4, "")
            for _, p in ipairs(ViewerList(true)) do GC.SendFull(p) end
        end)
        return true
    end

    local function EventVirus(id)
        GC.Virus, GC.EventBusy = CurTime() + 60, true
        EvMsg(6, "VIRUS", 60)
        timer.Simple(60, function()
            if GC.GameId ~= id then return end
            GC.Virus, GC.EventBusy = nil, false
            if GC.State == "playing" then
                for _, v in ipairs(ViewerList(true)) do SendMsg(v, "The virus is gone.") end
            end
        end)
        return true
    end

    local function EventInvasion()
        local cells = {}
        for i = 1, GCN do
            if GC.biome[i] ~= GC.WATER and GC.biome[i] ~= 0 and GC.owner[i] == 0 and GC.build[i] == 0 and not GC.army[i] then
                cells[#cells + 1] = i
            end
        end
        if #cells == 0 then return false end
        local caps = {}
        for i = 1, GCN do if GC.build[i] == GC.B_CAPITAL then caps[#caps + 1] = i end end
        local minD = math.max(3, math.floor(6 * GCW / 32 + 0.5))
        local cell
        for _ = 1, 300 do
            local c = cells[math.random(#cells)]
            local cx, cy = XY(c)
            local ok = true
            for _, o in ipairs(caps) do
                local ox, oy = XY(o)
                if math.max(math.abs(cx - ox), math.abs(cy - oy)) < minD then ok = false break end
            end
            if ok then cell = c break end
        end
        cell = cell or cells[math.random(#cells)]

        local used = {}
        for _, P in ipairs(GC.Slots) do used[#used + 1] = (ColorToHSV(P.color)) end
        local hue, bestD = math.random(0, 359), -1
        for h = 0, 350, 10 do
            local md = 360
            for _, u in ipairs(used) do
                local d = math.abs(h - u)
                md = math.min(md, math.min(d, 360 - d))
            end
            if md > bestD then hue, bestD = h, md end
        end

        local s = #GC.Slots + 1
        local P = GC.NewBotSlot(s, hue, 0, 3, "Invader")
        P.coins = 500
        GC.Slots[s] = P
        GC.SetCell(cell, s, GC.B_CAPITAL)
        for _, j in ipairs(GC.Neighbors8(cell)) do
            if GC.biome[j] ~= GC.WATER and GC.owner[j] == 0 and GC.build[j] == 0 then
                GC.SetCell(j, s, GC.B_VILLAGE)
                break
            end
        end
        local opts = GC.RollChoices(s, 3)
        if #opts > 0 then P.spirits[1] = GC.PickFor(s, opts) end
        if GC.Rec then GC.Rec.players[s] = { P.name, math.Round(P.color.r), math.Round(P.color.g), math.Round(P.color.b), "Emperor" } end

        EvMsg(7, "INVASION")
        for _, p in ipairs(ViewerList(true)) do GC.SendFull(p) end
        return true
    end

    local function EventTreasure()
        if GC.Opts.nochests then return false end
        local cells = {}
        for i = 1, GCN do
            if GC.biome[i] ~= GC.WATER and GC.biome[i] ~= 0 and GC.owner[i] == 0 and GC.build[i] == 0 and not GC.army[i] then
                cells[#cells + 1] = i
            end
        end
        if #cells == 0 then return false end
        table.Shuffle(cells)
        local n = math.min(#cells, math.random(3, 6) + math.floor(GCN / 1024) * 2)
        EvMsg(8, "TREASURE RAIN")
        for k = 1, n do GC.SetCell(cells[k], 0, GC.B_CHEST) end
        return true
    end

    local function CoolStep(apply)
        local set, cells = {}, {}
        for i = 1, GCN do
            if GC.biome[i] == GC.TUNDRA then
                for _, j in ipairs(GC.Neighbors(i)) do
                    local b = GC.biome[j]
                    if b ~= GC.WATER and b ~= GC.TUNDRA and b ~= 0 and not set[j] then
                        set[j] = true
                        cells[#cells + 1] = j
                    end
                end
            end
        end
        if apply then
            for _, j in ipairs(cells) do GC.biome[j] = GC.TUNDRA end
            if #cells > 0 then GC.SendBiomes(cells) end
        end
        return cells
    end

    local function EventCooling(id)
        if GC.Opts.notundra or #CoolStep(false) == 0 then return false end
        GC.EventBusy = true
        EvMsg(9, "GLOBAL COOLING")
        local step = 0
        local function Next()
            timer.Simple(1, function()
                if not Alive(id) then GC.EventBusy = false return end
                local cells = CoolStep(true)
                step = step + 1
                if step >= 10 or #cells == 0 then GC.EventBusy = false else Next() end
            end)
        end
        Next()
        return true
    end

    GC.Events = { EventMeteors, EventFlood, EventReveal, EventDrain, EventVirus, EventInvasion, EventTreasure, EventCooling }

    function GC.RunEvent(force)
        if GC.State ~= "playing" then return false end
        local id = GC.GameId
        if force then return GC.Events[force] and GC.Events[force](id) or false end
        if GC.EventBusy then return false end
        local order = {}
        for k = 1, #GC.Events do order[k] = k end
        table.Shuffle(order)
        for _, k in ipairs(order) do
            if k ~= GC.LastEvent and GC.Events[k](id) then
                GC.LastEvent = k
                return true
            end
        end
        return false
    end

    GC.EventEvery, GC.EventChance = 300, 0.5
    timer.Create("GCapture_Events", 1, 0, function()
        if GC.State ~= "playing" or GC.Opts.noevents or not GC.nextEvent then return end
        if CurTime() < GC.nextEvent then return end
        GC.nextEvent = CurTime() + GC.EventEvery
        if not GC.EventBusy and math.random() < GC.EventChance then GC.RunEvent() end
    end)

    timer.Create("GCapture_Tick", 1, 0, function()
        if GC.State ~= "playing" then return end

        local pactsChanged = false
        for k, t in pairs(GC.pacts) do
            if CurTime() >= t then
                GC.pacts[k] = nil
                pactsChanged = true
                local a, b = math.floor(k / 256), k % 256
                Notify(a, "The non-aggression pact has ended.")
                Notify(b, "The non-aggression pact has ended.")
            end
        end
        if pactsChanged then GC.SendPacts() end

        local accChanged = false
        for k, t in pairs(GC.accessExp) do
            if CurTime() >= t then
                GC.accessExp[k] = nil
                if GC.access[k] then
                    local g, e = math.floor(k / 256), k % 256
                    GC.access[k] = nil
                    GC.EvictFrom(g, e)
                    accChanged = true
                    Notify(e, (GC.Slots[g] and GC.Slots[g].name or "?") .. " closed their territory to your troops.")
                end
            end
        end
        if accChanged then GC.SendAccess() end
        GC.CheckStranded()

        for sl, ch in pairs(GC.Choices) do
            if CurTime() >= ch.deadline then
                GC.Choices[sl] = nil
                GC.GiveSpirit(sl, ch.opts[math.random(#ch.opts)])
                GC.NextChoice(sl)
            end
        end

        if GC.nextTimedChoice and CurTime() >= GC.nextTimedChoice then
            GC.nextTimedChoice = CurTime() + GC.ChoiceInterval
            for sl in pairs(GC.Slots) do GC.OfferChoice(sl) end
        end

        local inc = {}
        for s in pairs(GC.Slots) do inc[s] = { 0, 0, 0 } end

        for i = 1, GCN do
            local o = GC.owner[i]
            if o ~= 0 and inc[o] then
                local I, b = inc[o], GC.Biomes[GC.biome[i]]
                I[2] = I[2] + b.pop
                local bd = GC.Build[GC.build[i]]
                if bd then
                    I[1] = I[1] + (bd.coin or 0)
                    I[3] = I[3] + (bd.weapon or 0)
                    I[2] = I[2] + (bd.popinc or 0)
                    if GC.build[i] == GC.B_OIL then I[1] = I[1] + math.max(-(bd.coin or 0), GC.Mod(o, "oilCoin")) end
                end
            end
        end

        local armyCost = {}
        for _, A in pairs(GC.army) do armyCost[A.owner] = (armyCost[A.owner] or 0) + GC.UpkeepPerArmy(A.owner, A.cav) end

        for s, P in pairs(GC.Slots) do
            local I = inc[s]
            if GC.Virus and CurTime() < GC.Virus then I[1] = I[1] - 10 I[2] = I[2] - 500 end

            local dsc = GC.disc[s]
            if dsc and CurTime() >= dsc.t then
                GC.disc[s] = nil dsc = nil
                Notify(s, "Discontent has faded.")
            end
            if dsc then
                I[1] = I[1] - dsc.n * GC.DiscontentPer
                if dsc.msg then
                    dsc.msg = nil
                    Notify(s, string.format("Discontent: -%.1f coins/s (fades after %d s without losses)", dsc.n * GC.DiscontentPer, GC.DiscontentTime))
                end
            end

            I[1] = I[1] + GC.Mod(s, "coins")
            I[2] = I[2] + GC.Mod(s, "pop")
            I[3] = I[3] + GC.Mod(s, "weapons")
            hook.Run("GCapture_Income", s, I, P)
            I[1] = I[1] - (armyCost[s] or 0)
            AddCoins(P, I[1])
            AddPop(s, P, I[2])

            local lim = GC.PopLimit(s)
            if P.pop > lim then P.pop = lim end
            P.weapons = math.max(0, P.weapons + I[3])
        end
        GC.SendStats()
    end)

    hook.Add("PlayerDisconnected", "GCapture_Disconnect", function(ply)
        GC.RecFlag[ply] = nil
        GC.Viewers[ply] = nil
        GC.VisOf[ply] = nil
        GC.Names[ply] = nil
        GC.Colors[ply] = nil
        local slot = GC.SlotOf[ply]
        if slot then
            GC.expPend[slot] = nil
            GC.SlotOf[ply] = nil
            GC.Slots[slot].ply = nil
            GC.Choices[slot] = nil
            for k in pairs(GC.access) do
                if math.floor(k / 256) == slot or k % 256 == slot then GC.access[k] = nil end
            end
            for k in pairs(GC.muted) do
                if math.floor(k / 256) == slot or k % 256 == slot then GC.muted[k] = nil end
            end
            GC.SendAccess()
            GC.noDiscontent = true
            for i = 1, GCN do
                if GC.owner[i] == slot then GC.SetCell(i, 0, 0) end
                if GC.ship[i] == slot then GC.SetShip(i, 0) end
            end
            GC.noDiscontent = nil
            local doomed = {}
            for _, A in pairs(GC.army) do
                if A.owner == slot then doomed[#doomed + 1] = A end
            end
            for _, A in ipairs(doomed) do RemoveArmy(A) end
            GC.CheckWin()
        end
        if GC.State == "lobby" then GC.SendLobby() end
    end)

    local function Reply(ply, msg)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, "[GCapture] " .. msg)
        else print("[GCapture] " .. msg) end
    end

    local function CanDebug(ply)
        return not IsValid(ply) or ply:IsSuperAdmin() or ply:IsListenServerHost()
    end

    local function FindPlayer(name)
        name = string.lower(string.Trim(name or ""))
        if name == "" then return end
        local partial
        for _, p in ipairs(player.GetAll()) do
            local nick = string.lower(p:Nick())
            if nick == name then return p end
            if not partial and string.find(nick, name, 1, true) then partial = p end
        end
        return partial
    end

    concommand.Add("gc_dbg_event", function(ply, _, args)
        if not CanDebug(ply) then return end
        if GC.State ~= "playing" then return Reply(ply, "The game is not running.") end
        local k = tonumber(args[1] or "")
        if not k or not GC.Events or not GC.Events[k] then return Reply(ply, "Usage: gc_dbg_event <1-8>") end
        Reply(ply, GC.RunEvent(k) and "Event started." or "The event could not start (conditions not met).")
    end)

    concommand.Add("gc_dbg_bots", function(ply)
        if not CanDebug(ply) then return end
        if GC.State ~= "playing" then return Reply(ply, "The game is not running.") end
        for s, P in ipairs(GC.Slots) do
            if P.bot then
                local cells = 0
                for i = 1, GCN do if GC.owner[i] == s then cells = cells + 1 end end
                local tg = P.bot.target and GC.Slots[P.bot.target]
                Reply(ply, string.format("%s [%s/%s] cells=%d coins=%d weapons=%d armies=%.1f target=%s", P.name,
                    P.bot.d.name, P.bot.kind, cells, P.coins, P.weapons, Strength(s), tg and tg.name or "-"))
            end
        end
    end)

    concommand.Add("gc_dbg_lobby_all", function(ply)
        if not CanDebug(ply) then return end
        if GC.State ~= "lobby" then return Reply(ply, "The game is already running, stop it first (Stop).") end
        local added = 0
        for _, p in ipairs(player.GetAll()) do
            if not GC.Viewers[p] then
                GC.Viewers[p] = true
                added = added + 1
            end
        end
        GC.SendLobby()
        Reply(ply, "Added to lobby: " .. added .. " (total in lobby: " .. #ViewerList() .. ")")
    end)

    local structIds = {}
    for id, b in pairs(GC.Build) do structIds[(string.lower(b.name):gsub(" ", ""))] = id end

    concommand.Add("gc_dbg_add_structure", function(ply, _, args)
        if not CanDebug(ply) then return end
        if #args < 2 then return Reply(ply, "Usage: gc_dbg_add_structure <nick> <capital|village|weaponry|fortress|oilrig|coastguard|trap|airbase|chest|fire|armycenter|cavalrycenter>") end
        if GC.State ~= "playing" then return Reply(ply, "The game is not running.") end

        local id = structIds[string.lower(args[#args])]
        if not id then return Reply(ply, "Unknown structure: " .. args[#args]) end

        local target = FindPlayer(table.concat(args, " ", 1, #args - 1))
        if not target then return Reply(ply, "Player not found.") end
        local slot = GC.SlotOf[target]
        if not slot then return Reply(ply, target:Nick() .. " is not in the game.") end

        local free = {}
        for i = 1, GCN do
            if GC.owner[i] == slot and GC.build[i] == 0
                and (id ~= GC.B_OIL or GC.biome[i] == GC.DESERT)
                and (id ~= GC.B_COAST or GC.IsCoast(i)) then
                free[#free + 1] = i
            end
        end
        if #free == 0 then return Reply(ply, "" .. target:Nick() .. " has no suitable cells for this structure.") end

        local i = free[math.random(#free)]
        GC.Place(i, slot, id)
        Reply(ply, string.format("%s: %s at cell (%d, %d)", target:Nick(), GC.Build[id].name, (i - 1) % GCW, math.floor((i - 1) / GCW)))
    end)

    concommand.Add("gc_dbg_expand", function(ply, _, args)
        if not CanDebug(ply) then return end
        if #args < 1 then return Reply(ply, "Usage: gc_dbg_expand <nick>") end
        if GC.State ~= "playing" then return Reply(ply, "The game is not running.") end

        local target = FindPlayer(table.concat(args, " "))
        if not target then return Reply(ply, "Player not found.") end
        local slot = GC.SlotOf[target]
        if not slot then return Reply(ply, target:Nick() .. " is not in the game.") end

        local cands = {}
        for i = 1, GCN do
            if GC.owner[i] == 0 and not GC.Biomes[GC.biome[i]].water and GC.HasNeighbor(GC.owner, i, slot, GC.ship) then
                cands[#cands + 1] = i
            end
        end
        if #cands == 0 then return Reply(ply, "No free adjacent cells for " .. target:Nick() .. ".") end

        local i = cands[math.random(#cands)]
        GC.SetCell(i, slot, GC.build[i])
        Reply(ply, string.format("%s expanded to cell (%d, %d)", target:Nick(), (i - 1) % GCW, math.floor((i - 1) / GCW)))
    end)

    concommand.Add("gc_dbg_add_army", function(ply, _, args)
        if not CanDebug(ply) then return end
        if #args < 1 then return Reply(ply, "Usage: gc_dbg_add_army <nick>") end
        if GC.State ~= "playing" then return Reply(ply, "The game is not running.") end

        local target = FindPlayer(table.concat(args, " "))
        if not target then return Reply(ply, "Player not found.") end
        local slot = GC.SlotOf[target]
        if not slot then return Reply(ply, target:Nick() .. " is not in the game.") end

        local free = {}
        for i = 1, GCN do
            if GC.owner[i] == slot and not GC.army[i] then free[#free + 1] = i end
        end
        if #free == 0 then return Reply(ply, "" .. target:Nick() .. " has no free cells for an army.") end

        local i = free[math.random(#free)]
        CreateArmy(slot, i, true)
        Reply(ply, string.format("%s: army at cell (%d, %d)", target:Nick(), (i - 1) % GCW, math.floor((i - 1) / GCW)))
    end)

    concommand.Add("gc_dbg_add_cavalry", function(ply, _, args)
        if not CanDebug(ply) then return end
        if #args < 1 then return Reply(ply, "Usage: gc_dbg_add_cavalry <nick>") end
        if GC.State ~= "playing" then return Reply(ply, "The game is not running.") end

        local target = FindPlayer(table.concat(args, " "))
        if not target then return Reply(ply, "Player not found.") end
        local slot = GC.SlotOf[target]
        if not slot then return Reply(ply, target:Nick() .. " is not in the game.") end

        local free = {}
        for i = 1, GCN do
            if GC.owner[i] == slot and not GC.army[i] and not GC.Biomes[GC.biome[i]].water then free[#free + 1] = i end
        end
        if #free == 0 then return Reply(ply, "" .. target:Nick() .. " has no free cells for an army.") end

        local i = free[math.random(#free)]
        CreateArmy(slot, i, true, true)
        Reply(ply, string.format("%s: cavalry at cell (%d, %d)", target:Nick(), (i - 1) % GCW, math.floor((i - 1) / GCW)))
    end)

    concommand.Add("gc_dbg_add_spirit", function(ply, _, args)
        if not CanDebug(ply) then return end
        if #args < 1 then return Reply(ply, "Usage: gc_dbg_add_spirit <nick>") end
        if GC.State ~= "playing" then return Reply(ply, "The game is not running.") end

        local target = FindPlayer(table.concat(args, " "))
        if not target then return Reply(ply, "Player not found.") end
        local slot = GC.SlotOf[target]
        if not slot then return Reply(ply, target:Nick() .. " is not in the game.") end

        local sp = GC.RollSpirit(slot)
        if not sp then return Reply(ply, "The player already has all spirits.") end
        GC.GiveSpirit(slot, sp)
        Reply(ply, target:Nick() .. ": " .. GC.SpiritName(sp, GC.Slots))
    end)

    concommand.Add("gc_dbg_mm", function(ply)
        if not CanDebug(ply) then return end
        if not IsValid(ply) then return Reply(ply, "Run this command in-game.") end
        if GC.State ~= "playing" then return Reply(ply, "The game is not running.") end
        local slot = GC.SlotOf[ply]
        local P = slot and GC.Slots[slot]
        if not P then return Reply(ply, "You are not in the game.") end
        P.coins = P.coins + 1000
        GC.SendStats()
        SendMsg(ply, "+1000 coins (debug)")
    end)

    concommand.Add("gc_dbg_force_attack", function(ply, _, args)
        if not CanDebug(ply) then return end
        if #args < 1 then return Reply(ply, "Usage: gc_dbg_force_attack <nick>") end
        if GC.State ~= "playing" then return Reply(ply, "The game is not running.") end

        local target = FindPlayer(table.concat(args, " "))
        if not target then return Reply(ply, "Player not found.") end
        local slot = GC.SlotOf[target]
        if not slot then return Reply(ply, target:Nick() .. " is not in the game.") end

        local opts = {}
        for _, A in pairs(GC.army) do
            if A.owner == slot and A.state == GC.ST_IDLE and A.org >= 1 and not IsTraining(A) then
                local aboard = GC.Biomes[GC.biome[A.cell]].water
                for _, j in ipairs(GC.Neighbors8(A.cell)) do
                    local ok
                    if aboard then
                        ok = GC.CanArmyLand(slot, A.cell, j) and (GC.army[j] ~= nil or GC.owner[j] ~= slot)
                    else
                        ok = GC.CanArmyAttack(slot, A.cell, j)
                    end
                    if ok then
                        local D = GC.army[j]
                        if not (D and D.state == GC.ST_ATTACK and D.foe) then opts[#opts + 1] = { A, j } end
                    end
                end
            end
        end
        if #opts == 0 then
            return Reply(ply, "Impossible: " .. target:Nick() .. "'s armies have no free enemy targets within 3x3.")
        end

        local o = opts[math.random(#opts)]
        local from, to = o[1].cell, o[2]
        local ok, msg = StartAttack(o[1], to)
        if not ok then return Reply(ply, msg or "Failed to start the offensive.") end
        Reply(ply, string.format("%s: army (%d, %d) attacks (%d, %d)", target:Nick(),
            (from - 1) % GCW, math.floor((from - 1) / GCW), (to - 1) % GCW, math.floor((to - 1) / GCW)))
    end)

    local function SetCycle(ply, t, name)
        if not CanDebug(ply) then return end
        local day = math.floor(GC.CycleNow() / GC.CycleLen)
        GC.DayT0 = CurTime() - (day * GC.CycleLen + t)
        GC.SendTime()
        Reply(ply, "Time of day: " .. name)
    end
    concommand.Add("gc_dbd_day", function(ply) SetCycle(ply, 0, "day") end)
    concommand.Add("gc_dbd_night", function(ply) SetCycle(ply, GC.DayLen + GC.DayTrans, "night") end)
    concommand.Add("gc_dbg_spirit_choose", function(ply, _, args)
        if not CanDebug(ply) then return end
        if GC.State ~= "playing" then return Reply(ply, "The game is not running.") end
        local target
        if #args > 0 then target = FindPlayer(table.concat(args, " ")) else target = ply end
        if not IsValid(target) then return Reply(ply, "Specify a nick when running from the server console.") end
        if #args > 0 and not target then return Reply(ply, "Player not found.") end
        local slot = GC.SlotOf[target]
        if not slot then return Reply(ply, target:Nick() .. " is not in the game.") end
        GC.OfferChoice(slot)
        Reply(ply, "Spirit choice offered to " .. target:Nick())
    end)
