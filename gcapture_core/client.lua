local GC = GCapture

surface.CreateFont("GCapture.Stat", { font = "Roboto", size = 18, weight = 700 })
surface.CreateFont("GCapture.Mid", { font = "Roboto", size = 16, weight = 700 })
surface.CreateFont("GCapture.Small", { font = "Roboto", size = 14, weight = 500 })
GC.cvMusVol = CreateClientConVar("cl_gc_music_vol", "0.7", true, false, "GCapture: music volume", 0, 1)
GC.cvSfxVol = CreateClientConVar("cl_gc_sfx_vol", "1", true, false, "GCapture: sound effects volume", 0, 1)
GC.cvClouds = CreateClientConVar("cl_gc_clouds", "1", true, false, "GCapture: show clouds (1/0)", 0, 1)
GC.cvWater = CreateClientConVar("cl_gc_water_fx", "1", true, false, "GCapture: animated water effects (1/0), turn off for more FPS", 0, 1)
GC.cvBuildAlpha = CreateClientConVar("cl_gc_build_alpha", "0.5", true, false, "GCapture: structure opacity", 0, 1)
GC.cvUnitAlpha = CreateClientConVar("cl_gc_unit_alpha", "1", true, false, "GCapture: unit (ships, armies) opacity", 0, 1)
GC.cvBubbleAlpha = CreateClientConVar("cl_gc_bubble_alpha", "1", true, false, "GCapture: combat bubble opacity", 0, 1)
GC.cvBarAlpha = CreateClientConVar("cl_gc_bar_alpha", "1", true, false, "GCapture: HP/organization bar opacity", 0, 1)
function GC.PlaySfx(path)
    local v = GC.cvSfxVol:GetFloat()
    if v <= 0.001 then return end
    local lp = LocalPlayer()
    if IsValid(lp) then lp:EmitSound(path, 0, 100, v, CHAN_STATIC) else surface.PlaySound(path) end
end
surface.CreateFont("GCapture.Big", { font = "Roboto", size = 26, weight = 700 })
surface.CreateFont("GCapture.Huge", { font = "Roboto", size = 44, weight = 800 })

local TH = {
    bg = Color(12, 18, 14), hd = Color(7, 12, 9), row = Color(22, 36, 27), rowHover = Color(32, 56, 40),
    accent = Color(60, 210, 110), accentDim = Color(28, 110, 60),
    text = Color(215, 240, 222), muted = Color(120, 150, 130),
}
GC.TH = TH
CreateClientConVar("cl_gc_theme", "-1", true, false, "GCapture: UI theme hue (0-360, -1 = default green)", -1, 360)
local THEME_DEF = {}
for k, v in pairs(TH) do THEME_DEF[k] = Color(v.r, v.g, v.b) end

function GC.ApplyTheme(h)
    h = tonumber(h) or -1
    if h < 0 then
        for k, v in pairs(THEME_DEF) do TH[k] = Color(v.r, v.g, v.b) end
        return
    end
    TH.bg        = HSVToColor(h, 0.33, 0.07)
    TH.hd        = HSVToColor(h, 0.40, 0.05)
    TH.row       = HSVToColor(h, 0.40, 0.14)
    TH.rowHover  = HSVToColor(h, 0.43, 0.22)
    TH.accent    = HSVToColor(h, 0.70, 0.82)
    TH.accentDim = HSVToColor(h, 0.75, 0.43)
    TH.text      = HSVToColor(h, 0.10, 0.95)
    TH.muted     = HSVToColor(h, 0.20, 0.60)
end
cvars.AddChangeCallback("cl_gc_theme", function(_, _, new) GC.ApplyTheme(new) end, "GCapture_Theme")
GC.ApplyTheme(GetConVar("cl_gc_theme"):GetString())

local function LerpColor(t, a, b)
    return Color(Lerp(t, a.r, b.r), Lerp(t, a.g, b.g), Lerp(t, a.b, b.b))
end

local function StyleButton(b)
    b:SetTextColor(TH.text)
    b.hv, b.pr = 0, 0
    b.Paint = function(s, w, h)
        local en = s:IsEnabled()
        s.hv = Lerp(math.min(1, FrameTime() * 14), s.hv, (en and s:IsHovered()) and 1 or 0)
        s.pr = Lerp(math.min(1, FrameTime() * 30), s.pr, (en and s:IsDown()) and 1 or 0)
        local k = s.hv
        draw.RoundedBox(4, 0, 0, w, h, en and LerpColor(k, TH.accentDim, TH.accent) or TH.accentDim)
        local inset = 1 + math.floor(s.pr + 0.5)
        draw.RoundedBox(4, inset, inset, w - inset * 2, h - inset * 2, en and LerpColor(k, TH.row, TH.rowHover) or TH.hd)
        s:SetTextColor(en and LerpColor(k, TH.text, Color(255, 255, 255)) or TH.muted)
    end
end
local function StyleEntry(te)
    te:SetTextColor(TH.text); te:SetCursorColor(TH.accent)
    te.Paint=function(s,w,h)
        draw.RoundedBox(4,0,0,w,h,TH.accentDim); draw.RoundedBox(4,1,1,w-2,h-2,TH.hd)
        s:DrawTextEntryText(TH.text,TH.accent,TH.text)
    end
end
local function StyleScroll(sp)
    local vb=sp:GetVBar(); vb:SetWide(8)
    vb.Paint=function(s,w,h) draw.RoundedBox(4,0,0,w,h,TH.hd) end
    vb.btnUp.Paint=function() end; vb.btnDown.Paint=function() end
    vb.btnGrip.Paint=function(s,w,h) draw.RoundedBox(4,0,0,w,h,TH.accentDim) end
end
local function Glow(cx, cy, R, col, a)
    for k = 1, 6 do
        local r = R * k / 6
        draw.RoundedBox(r, cx - r, cy - r, r * 2, r * 2, Color(col.r, col.g, col.b, a))
    end
end

function GC.PanelBloom(w, h, k)
    k = k or 1
    local t, a = CurTime(), TH.accent
    local pulse = 0.82 + 0.18 * (math.sin(t * 0.45) * 0.6 + math.sin(t * 0.27 + 1.3) * 0.4)

    for i = 0, 14 do
        surface.SetDrawColor(a.r, a.g, a.b, 20 * k * pulse * (1 - i / 15) ^ 2)
        surface.DrawRect(1, 1 + i * 3, w - 2, 3)
    end

    local m = math.min(w, h)
    local x1 = 0.5 + 0.36 * math.sin(t * 0.07) + 0.08 * math.sin(t * 0.13 + 1)
    local y1 = 0.14 + 0.05 * math.sin(t * 0.09 + 1) + 0.02 * math.sin(t * 0.17)
    Glow(w * x1, h * y1, m * 0.55, a, 4 * k * pulse)
    local x2 = 0.5 + 0.40 * math.cos(t * 0.05 + 2) + 0.06 * math.sin(t * 0.11)
    local y2 = 0.90 + 0.04 * math.sin(t * 0.08)
    Glow(w * x2, h * y2, m * 0.45, TH.accentDim, 6 * k * (1.1 - 0.3 * pulse))

    local sx = ((t * 0.025) % 1.6 - 0.3) * w
    for i = -10, 10 do
        local x = math.floor(sx + i * 3)
        if x > 1 and x < w - 4 then
            surface.SetDrawColor(a.r, a.g, a.b, 9 * k * (1 - math.abs(i) / 11) ^ 2)
            surface.DrawRect(x, 2, 3, h - 4)
        end
    end
end

local function StyleFrame(f)
    f.Paint=function(s,w,h)
        draw.RoundedBox(6,0,0,w,h,TH.accent); draw.RoundedBox(6,1,1,w-2,h-2,TH.bg)
        draw.RoundedBoxEx(6,1,1,w-2,24,TH.hd,true,true,false,false)
        GC.PanelBloom(w, h, 1)
        surface.SetDrawColor(TH.accent.r, TH.accent.g, TH.accent.b, 90)
        surface.DrawRect(1, 25, w - 2, 1)
        surface.SetDrawColor(TH.accent.r, TH.accent.g, TH.accent.b, 25)
        surface.DrawRect(1, 26, w - 2, 2)
    end
    if f.lblTitle then f.lblTitle:SetTextColor(TH.accent) end
    if f.btnMinim then f.btnMinim:SetVisible(false) end
    if f.btnMaxim then f.btnMaxim:SetVisible(false) end
    if f.btnClose then f.btnClose:SetText(""); f.btnClose.Paint=function(s,w,h)
        if s:IsHovered() then draw.RoundedBox(4,0,0,w,h,Color(170,50,50)) end
        draw.SimpleText("x","GCapture.Stat",w/2,h/2-1,TH.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
    end end
end
local function StyleOption(o)
    o:SetTextColor(TH.text)
    o.hv = 0
    o.Paint = function(s, w, h)
        local en = s:IsEnabled()
        s.hv = Lerp(math.min(1, FrameTime() * 16), s.hv, (en and s:IsHovered()) and 1 or 0)
        if s.hv > 0.01 then
            draw.RoundedBox(3, 2, 1, w - 4, h - 2, Color(TH.accentDim.r, TH.accentDim.g, TH.accentDim.b, 255 * s.hv))
            surface.SetDrawColor(TH.accent.r, TH.accent.g, TH.accent.b, 255 * s.hv)
            surface.DrawRect(2, 4, 2, h - 8)
        end
        s:SetTextColor(en and TH.text or TH.muted)
        if s.SubMenu then draw.SimpleText(">", "GCapture.Small", w - 12, h / 2, TH.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
    end
end
local function StyleMenu(m)
    m.Paint=function(s,w,h) draw.RoundedBox(4,0,0,w,h,TH.accent); draw.RoundedBox(4,1,1,w-2,h-2,TH.bg) end
    local ao,as=m.AddOption,m.AddSubMenu
    m.AddOption=function(self,...) local o=ao(self,...) StyleOption(o) return o end
    m.AddSubMenu=function(self,...) local sub,o=as(self,...) StyleMenu(sub); StyleOption(o); return sub,o end
end
local function EaseBack(t) t=math.Clamp(t,0,1)-1; return 1+2.70158*t*t*t+1.70158*t*t end
local function DrawScaled(x,y,w,h,sc)
    local nw,nh=w*sc,h*sc
    surface.DrawTexturedRect(math.floor(x+(w-nw)/2),math.floor(y+(h-nh)/2),math.floor(nw),math.floor(nh))
end

local function DrawTintIcon(mat, x, y, w, h, sc, col, a)
    a = a or 255
    surface.SetMaterial(mat)
    surface.SetDrawColor(255, 255, 255, a)
    DrawScaled(x, y, w, h, sc)
    if col then
        surface.SetDrawColor(col.r, col.g, col.b, 160 * a / 255)
        DrawScaled(x, y, w, h, sc)
    end
end

local function DrawBar(x, y, w, h, frac, r, g, b, a)
    a = a or 255
    frac = math.Clamp(frac, 0, 1)
    surface.SetDrawColor(10, 12, 16, 190 * a / 255)
    surface.DrawRect(x, y, w, h)
    local ix, iy, iw, ih = x, y, w, h
    if h >= 4 and w >= 8 then ix, iy, iw, ih = x + 1, y + 1, w - 2, h - 2 end
    local fw = math.floor(iw * frac + 0.5)
    if frac > 0 and fw < 1 then fw = 1 end
    if fw > 0 then
        surface.SetDrawColor(r, g, b, a)
        surface.DrawRect(ix, iy, fw, ih)
    end
end
local CLOUD_ALPHA, CLOUD_SPEED = 28, 0.25
local floor0 = math.floor

function GC.GetVignetteMat()
    if GC.vigMat ~= nil then return GC.vigMat or nil end
    GC.vigMat = false
    local ok = pcall(function()
        local N = 128
        local rt = GetRenderTarget("GCapture_Vignette_" .. N, N, N)
        render.PushRenderTarget(rt)
        render.OverrideAlphaWriteEnable(true, true)
        render.Clear(0, 0, 0, 0, true, true)
        cam.Start2D()
        draw.NoTexture()
        for y = 0, N - 1 do
            local ey = math.min(y + 0.5, N - y - 0.5) / N
            local ay = 1 - math.Clamp(ey / 0.3, 0, 1)
            ay = ay * ay * (3 - 2 * ay)
            for x = 0, N - 1 do
                local ex = math.min(x + 0.5, N - x - 0.5) / N
                local ax = 1 - math.Clamp(ex / 0.3, 0, 1)
                ax = ax * ax * (3 - 2 * ax)
                local a = 1 - (1 - ax) * (1 - ay)
                if a > 0.004 then
                    surface.SetDrawColor(0, 0, 0, 185 * a)
                    surface.DrawRect(x, y, 1, 1)
                end
            end
        end
        cam.End2D()
        render.OverrideAlphaWriteEnable(false)
        render.PopRenderTarget()
        GC.vigMat = CreateMaterial("GCapture_VignetteMat_" .. N, "UnlitGeneric", {
            ["$basetexture"] = rt:GetName(), ["$translucent"] = 1, ["$vertexalpha"] = 1, ["$vertexcolor"] = 1,
        })
    end)
    if not ok then GC.vigMat = false end
    return GC.vigMat or nil
end
local function MakeClouds()
    local a=math.Rand(0,math.pi*2); GC.cloudDir={math.cos(a),math.sin(a)}; GC.clouds={}
    local sc = GCW / 32
    for k=1,math.max(6, math.floor(14 * sc)) do
        local ph,verts=math.Rand(0,6.28),{}
        for v=0,13 do local ang=v/14*math.pi*2; local r=1+0.12*math.sin(ang*3+ph)+0.06*math.sin(ang*5+ph*2)
            verts[#verts+1]={x=math.cos(ang)*r,y=math.sin(ang)*r*0.55}
        end
        GC.clouds[k]={x=math.Rand(0,GCW),y=math.Rand(0,GCH),s=math.Rand(2.5,6) * math.max(1, sc),sp=math.Rand(0.6,1.2),v=verts}
    end
end
local LIGHT_K = {}
do
    local R = 2
    for dy = -R, R do for dx = -R, R do
        local d = math.sqrt(dx * dx + dy * dy)
        local v = 1 - d / (R + 1)
        if v > 0 then LIGHT_K[#LIGHT_K + 1] = { dx, dy, v * v * (3 - 2 * v) } end
    end end
end
local function UpdateLight()
    local L = {}
    local owner, ship = GC.owner, GC.ship
    for i = 1, GCN do
        if owner[i] ~= 0 or ship[i] ~= 0 then
            local cx, cy = (i - 1) % GCW, math.floor((i - 1) / GCW)
            for _, k in ipairs(LIGHT_K) do
                local x, y = cx + k[1], cy + k[2]
                if x >= 0 and x < GCW and y >= 0 and y < GCH then
                    local j = y * GCW + x + 1
                    if k[3] > (L[j] or 0) then L[j] = k[3] end
                end
            end
        end
    end
    GC.light = L
end

local OWNER_ALPHA = 220

local mats = {}
for id, b in pairs(GC.Build) do mats[id] = Material(b.icon) end
GC.BuildMats = mats
local matShip = Material(GC.ShipIcon)
local matArmy = Material(GC.ArmyIcon)
local matCav = Material(GC.CavIcon)
GC.flashes, GC.shakeEnd, GC.lastBoom = {}, 0, -10
GC.cellFx, GC.armySpawn, GC.armyGhost, GC.goneId = {}, {}, {}, {}
GC.bSpawn, GC.bGhost = {}, {}
GC.sndT = {}
GC.lobbyColors = {}
GC.dayOffset, GC.nightA, GC.light, GC.lightT = 0, 0, {}, 0
function GC.CycleNow() return CurTime() + GC.dayOffset end
local matCoins, matPop, matGun = Material("gcapture/gc_ui_coins.png"), Material("gcapture/gc_ui_pop.png"), Material("gcapture/gc_ui_weapons.png")

GC.playing, GC.isHost, GC.lobbyList = false, false, {}
GC.players, GC.mySlot, GC.winner, GC.pick = {}, nil, nil, nil
GC.biome, GC.owner, GC.build, GC.ship, GC.army = {}, {}, {}, {}, {}
GC.sel, GC.fogA = {}, {}
GC.selShip = {}
GC.lobbyOpts, GC.lobbyNames = {}, {}

local function BuildRuns()
    GC.runs = {}
    local biome = GC.biome
    for y = 0, GCH - 1 do
        local row, x = {}, 0
        while x < GCW do
            local b, s = biome[y * GCW + x + 1], x
            while x < GCW and biome[y * GCW + x + 1] == b do x = x + 1 end
            row[#row + 1] = { s, x - s, b }
        end
        GC.runs[y] = row
    end
end

net.Receive("GCapture_Lobby", function()
    GC.isHost = net.ReadBool()
    GC.access, GC.muted = {}, {}
    GC.lobbyOpts = { mode = net.ReadUInt(2), nofog = net.ReadBool(), bots = net.ReadUInt(6), diff = net.ReadUInt(3), btype = net.ReadUInt(2),
        size = net.ReadUInt(2), observe = net.ReadBool(), seed = net.ReadString(), map = net.ReadString(), noevents = net.ReadBool(), presets = net.ReadUInt(8), emperor = net.ReadBool() }
    for _, k in ipairs(GC.OptFlags) do GC.lobbyOpts[k] = net.ReadBool() end
    GC.noNight = GC.lobbyOpts.nonight == true
    local n, list, names, cols = net.ReadUInt(8), {}, {}, {}
    for i = 1, n do
        list[i] = net.ReadEntity()
        names[i] = net.ReadString()
        if net.ReadBool() then cols[i] = Color(net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)) end
    end
    GC.lobbyNames, GC.lobbyColors = names, cols
    GC.sel, GC.fogA = {}, {}
    GC.lobbyList, GC.playing, GC.winner, GC.pick = list, false, nil, nil
    GC.deploy = nil
    if IsValid(GC.choiceFrame) then GC.choiceFrame:Remove() end
    GC.RefreshUI()
end)

net.Receive("GCapture_Event", function()
    local kind, title, arg = net.ReadUInt(4), net.ReadString(), net.ReadUInt(8)
    if title ~= "" then GC.eventBanner = { text = title, t = CurTime() } end
    if kind == 3 then GC.screenFlash = { t = CurTime(), c = 255 }
    elseif kind == 4 then GC.screenFlash = { t = CurTime(), c = 0 }
    elseif kind == 6 then GC.virusEnd = CurTime() + arg end
    if kind ~= 4 then GC.PlaySfx("gcapture/gc_take.wav") end
end)

net.Receive("GCapture_Biome", function()
    local n = net.ReadUInt(15)
    for _ = 1, n do
        local i, b = net.ReadUInt(GCIB) + 1, net.ReadUInt(3)
        if GC.playing and GC.known and GC.known[i] then
            GC.biome[i] = b
            if b == GC.WATER then
                GC.owner[i], GC.build[i], GC.ship[i], GC.army[i] = 0, 0, 0, nil
            end
        end
    end
    if GC.playing then BuildRuns() end
end)

net.Receive("GCapture_Deploy", function()
    local kind = net.ReadUInt(2)
    if kind == 0 then
        local w, h = net.ReadUInt(10), net.ReadUInt(10)
        local secs = net.ReadUInt(7)
        local slot = net.ReadUInt(8)
        local col = Color(net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8))
        local seq = net.ReadUInt(8)
        GC.deploy = { w = w, h = h, endT = CurTime() + secs, total = math.max(1, GC.DeployTime), slot = slot,
            color = col, seq = seq, parts = {}, picks = {} }
        GC.playing = false
        GC.RefreshUI()
    elseif kind == 1 then
        local D = GC.deploy
        local n, list = net.ReadUInt(8), {}
        for i = 1, n do
            list[i] = { cell = net.ReadUInt(20), color = Color(net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)) }
        end
        if D then
            D.picks = list
            if D.color then
                local found
                for _, e in ipairs(list) do
                    if e.color.r == D.color.r and e.color.g == D.color.g and e.color.b == D.color.b then found = e.cell break end
                end
                D.mine = found
            end
        end
    elseif kind == 2 then
        local D = GC.deploy
        local nc, cols = net.ReadUInt(8), {}
        for k = 1, nc do cols[k] = Color(net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)) end
        local len = net.ReadUInt(16)
        local data = util.Decompress(net.ReadData(len), 20000000) or ""
        if not D or #data < D.w * D.h then return end
        local cmap, cruns = {}, {}
        for i = 1, D.w * D.h do cmap[i] = data:byte(i) end
        for y = 0, D.h - 1 do
            local row, x = {}, 0
            while x < D.w do
                local k, st = cmap[y * D.w + x + 1], x
                while x < D.w and cmap[y * D.w + x + 1] == k do x = x + 1 end
                if k > 0 and cols[k] then row[#row + 1] = { st, x - st, k } end
            end
            cruns[y] = row
        end
        D.ccols, D.cruns = cols, cruns
    end
end)

net.Receive("GCapture_DeployData", function()
    local seq = net.ReadUInt(8)
    local D = GC.deploy
    if not D or D.seq ~= seq or not D.parts then return end
    D.parts[#D.parts + 1] = net.ReadData(net.ReadUInt(16))
    if not net.ReadBool() then return end
    local data = util.Decompress(table.concat(D.parts), 20000000) or ""
    D.parts = nil
    local w, h = D.w, D.h
    if #data < w * h then return end
    local biome, runs = {}, {}
    for i = 1, w * h do biome[i] = data:byte(i) end
    for y = 0, h - 1 do
        local row, x = {}, 0
        while x < w do
            local b, st = biome[y * w + x + 1], x
            while x < w and biome[y * w + x + 1] == b do x = x + 1 end
            row[#row + 1] = { st, x - st, b }
        end
        runs[y] = row
    end
    D.biome, D.runs = biome, runs
end)

net.Receive("GCapture_Auto", function()
    local t = net.ReadUInt(7)
    GC.autoEnd = t > 0 and (CurTime() + t) or nil
end)

local function ReadArmyFields()
    local A = {}
    A.id = net.ReadUInt(16)
    A.owner = net.ReadUInt(8)
    A.org = net.ReadUInt(8)
    A.hp = net.ReadUInt(8)
    A.state = net.ReadUInt(2)
    A.target = net.ReadUInt(GCIB + 1)
    A.maxOrg = net.ReadUInt(8)
    A.maxHp = net.ReadUInt(8)
    local tr = net.ReadUInt(7)
    if tr > 0 then A.trainEnd = CurTime() + tr end
    A.cav = net.ReadBool()
    A.auto = net.ReadBool()
    return A
end

local function ReadArmy()
    local cell = net.ReadUInt(GCIB) + 1
    return cell, ReadArmyFields()
end

local function ReadSpirits()
    local n, t = net.ReadUInt(8), {}
    for i = 1, n do
        local id = net.ReadString()
        local target = net.ReadUInt(8)
        t[i] = { id = id, target = target ~= 0 and target or nil }
    end
    return t
end

net.Receive("GCapture_Full", function()
    GC.deploy = nil
    GC.SetSize(net.ReadUInt(10), net.ReadUInt(10))
    GC.isHost = net.ReadBool()
    local n = net.ReadUInt(8)
    GC.players, GC.mySlot, GC.winner, GC.pick = {}, nil, nil, nil
    GC.pacts = {}
    if IsValid(GC.choiceFrame) then GC.choiceFrame:Remove() end
    for s = 1, n do
        local p = {}
        p.ent = net.ReadEntity()
        p.name = net.ReadString()
        p.color = Color(net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8))
        p.coins, p.pop, p.weapons = net.ReadFloat(), net.ReadFloat(), net.ReadFloat()
        p.diff = net.ReadString()
        p.dead = net.ReadBool()
        p.spirits = {}
        GC.players[s] = p
        if p.ent == LocalPlayer() then GC.mySlot = s end
    end
    local mySpirits = ReadSpirits()
    if GC.mySlot then GC.players[GC.mySlot].spirits = mySpirits end

    local gid = net.ReadUInt(16)
    GC.fog = net.ReadBool()
    local seq = net.ReadUInt(8)
    GC.seed = net.ReadString()
    GC.noNight = net.ReadBool()

    if gid ~= GC.gameId then
        GC.gameId = gid
        GC.focusPending, GC.focusAt = true, CurTime() + 0.4
        GC.biome, GC.owner, GC.build, GC.ship, GC.known, GC.blevel = {}, {}, {}, {}, {}, {}
        GC.fogA, GC.sel = {}, {}
        GC.clouds, GC.cellFx, GC.armySpawn, GC.armyGhost, GC.goneId, GC.bSpawn, GC.bGhost = nil, {}, {}, {}, {}, {}, {}
        GC.expPend = nil
        for i = 1, GCN do GC.biome[i], GC.owner[i], GC.build[i], GC.ship[i] = 0, 0, 0, 0 end
    end

    GC.vis = {}
    GC.army = {}
    local cnt = net.ReadUInt(12)
    for _ = 1, cnt do
        local cell, A = ReadArmy()
        GC.army[cell] = A
    end
    GC.oilUsed = {}
    local nOil = net.ReadUInt(15)
    for _ = 1, nOil do GC.oilUsed[net.ReadUInt(GCIB) + 1] = true end

    GC.mapBuf = { parts = {}, touched = {}, seq = seq }
end)

net.Receive("GCapture_FullData", function()
    local seq = net.ReadUInt(8)
    local mb = GC.mapBuf
    if not mb or mb.seq ~= seq then return end
    mb.parts[#mb.parts + 1] = net.ReadData(net.ReadUInt(16))
    if not net.ReadBool() then return end
    GC.mapBuf = nil

    local data = util.Decompress(table.concat(mb.parts), 20000000) or ""
    if #data < GCN * 6 then return end
    local tch = mb.touched
    for i = 1, GCN do
        local st = data:byte(i)
        if st >= 1 then
            GC.biome[i] = data:byte(GCN + i)
            GC.known[i] = true
        end
        if st == 2 then
            GC.vis[i] = true
            if not tch[i] then
                GC.owner[i] = data:byte(2 * GCN + i)
                GC.build[i] = data:byte(3 * GCN + i)
                GC.ship[i] = data:byte(4 * GCN + i)
                GC.blevel[i] = data:byte(5 * GCN + i)
            end
        elseif not tch[i] then
            GC.ship[i] = 0
        end
    end
    BuildRuns()
    GC.playing = true
    GC.RefreshUI()
end)

net.Receive("GCapture_Spirits", function()
    local list = ReadSpirits()
    local me = GC.players[GC.mySlot or 0]
    if me then me.spirits = list end
    GC.FillSpirits()
end)

net.Receive("GCapture_SpecSp", function()
    local n = net.ReadUInt(8)
    for s = 1, n do
        local l = ReadSpirits()
        if GC.players[s] and s ~= GC.mySlot then GC.players[s].spirits = l end
    end
end)

local SHAKE_TIME = 0.6
net.Receive("GCapture_Boom", function()
    local cell = net.ReadUInt(GCIB) + 1
    GC.flashes[cell] = CurTime()
    GC.lastBoom = CurTime()
    GC.shakeEnd = CurTime() + SHAKE_TIME
    GC.PlaySfx("gcapture/gc_explode.ogg")
    local lp = LocalPlayer()
    if IsValid(lp) then util.ScreenShake(lp:GetPos(), 4, 4, 0.8, 100) end
end)

hook.Add("Think", "GCapture_Shake", function()
    local ui = GC.UI
    local w = ui and ui.window
    if not IsValid(w) then GC.shakeBase = nil return end
    local left = GC.shakeEnd - CurTime()
    if left > 0 then
        if not GC.shakeBase then GC.shakeBase = { w:GetPos() } end
        local amp = 12 * (left / SHAKE_TIME)
        w:SetPos(GC.shakeBase[1] + math.Rand(-amp, amp), GC.shakeBase[2] + math.Rand(-amp, amp))
    elseif GC.shakeBase then
        w:SetPos(GC.shakeBase[1], GC.shakeBase[2])
        GC.shakeBase = nil
    end
end)

net.Receive("GCapture_Oil", function()
    GC.oilUsed[net.ReadUInt(GCIB) + 1] = true
end)

net.Receive("GCapture_Pacts", function()
    GC.pacts = {}
    local n = net.ReadUInt(8)
    for _ = 1, n do
        local a, b, r = net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(7)
        GC.pacts[GC.PactKey(a, b)] = CurTime() + r
    end
end)

net.Receive("GCapture_Exp", function()
    local cell, dur = net.ReadUInt(GCIB) + 1, net.ReadUInt(4)
    GC.expPend = GC.expPend or {}
    if dur == 0 then GC.expPend[cell] = nil
    else GC.expPend[cell] = { t0 = CurTime(), t1 = CurTime() + dur } end
end)

net.Receive("GCapture_Cell", function()
    local i, o, b = net.ReadUInt(GCIB) + 1, net.ReadUInt(8), net.ReadUInt(GC.BuildBits)
    if GC.expPend then GC.expPend[i] = nil end
    if GC.mapBuf then GC.mapBuf.touched[i] = true end
    local lvl = net.ReadUInt(2)
    local ob, oo, now = GC.build[i], GC.owner[i], CurTime()

    if b ~= ob then

        if ob ~= 0 and ob ~= GC.B_FIRE and mats[ob] then GC.bGhost[i] = { b = ob, t = now } end
        if b ~= 0 then GC.bSpawn[i] = now end
        if b ~= 0 and b ~= GC.B_FIRE then GC.cellFx[i] = { kind = "build", t = now } end
    elseif b == GC.B_BARRICADE and lvl ~= (GC.blevel[i] or 0) then
        GC.bSpawn[i] = now
        GC.cellFx[i] = { kind = "build", t = now }
    end

    local fx = GC.cellFx[i]
    if o ~= oo and o ~= 0 and not (fx and fx.kind == "build") then
        local P = GC.players[o]
        local c = P and P.color or color_white
        GC.cellFx[i] = { kind = "claim", t = now, r = Lerp(0.45, c.r, 255), g = Lerp(0.45, c.g, 255), b = Lerp(0.45, c.b, 255) }
    end
    GC.owner[i], GC.build[i], GC.blevel[i] = o, b, lvl
end)
net.Receive("GCapture_Time", function() GC.dayOffset=net.ReadFloat()-CurTime() end)

net.Receive("GCapture_Ship", function()
    local i, s = net.ReadUInt(GCIB) + 1, net.ReadUInt(8)
    if GC.mapBuf then GC.mapBuf.touched[i] = true end
    GC.ship[i] = s
end)

local ARMY_SND = {
    [1] = "gcapture/gc_attack.ogg",
    [2] = "gcapture/gc_defend.wav",
    [3] = "gcapture/gc_damage.ogg",
    [4] = "gcapture/gc_move.wav",
}

function GC.ArmySound(cell, kind)
    local ui = GC.UI
    local map = ui and ui.game and ui.game.map
    if not IsValid(map) or not map:IsVisible() or map.zoom <= 1.05 then return end
    local cs = map:CellSize()
    local cx, cy = (cell - 1) % GCW, math.floor((cell - 1) / GCW)
    local px, py = map.ox + (cx + 0.5) * cs, map.oy + (cy + 0.5) * cs
    if px < 0 or py < 0 or px > map:GetWide() or py > map:GetTall() then return end
    local t = SysTime()
    if (GC.sndT[kind] or 0) > t then return end
    GC.sndT[kind] = t + 0.12
    GC.PlaySfx(ARMY_SND[kind])
end

net.Receive("GCapture_Snd", function()
    local cell, kind = net.ReadUInt(GCIB) + 1, net.ReadUInt(3)
    if kind == 5 then
        local t = SysTime()
        if (GC.sndT[5] or 0) > t then return end
        GC.sndT[5] = t + 1
        GC.PlaySfx("gcapture/gc_alarm.ogg")
        return
    end
    GC.ArmySound(cell, kind)
end)

GC.odds = GC.odds or {}
net.Receive("GCapture_Odds", function()
    local acell, dcell = net.ReadUInt(GCIB) + 1, net.ReadUInt(GCIB) + 1
    local att, pct = net.ReadBool(), net.ReadUInt(7)
    GC.odds[acell] = { dcell = dcell, att = att, pct = pct, t = CurTime() }
end)

GC.orgFlashes = GC.orgFlashes or {}
net.Receive("GCapture_Army", function()
    local now = CurTime()
    if net.ReadBool() then
        local cell, A = ReadArmy()
        local old = GC.army[cell]
        if old and A.org < old.org then GC.orgFlashes[cell] = now end
        local g = A.id and GC.goneId[A.id]
        if g and now - g.t < 0.5 then
            GC.armyGhost[g.cell] = nil
            if A.owner == GC.mySlot and g.cell ~= cell then GC.ArmySound(cell, 4) end
        elseif not (old and old.id == A.id) then
            GC.armySpawn[A.id] = now
        end
        GC.goneId[A.id] = nil
        GC.army[cell] = A
    else
        local cell = net.ReadUInt(GCIB) + 1
        local old = GC.army[cell]
        if old then
            GC.armyGhost[cell] = { A = old, t = now }
            if old.id then GC.goneId[old.id] = { cell = cell, t = now } end
        end
        GC.army[cell] = nil
    end
end)

net.Receive("GCapture_Vis", function()
    local nNew = net.ReadUInt(15)
    for _ = 1, nNew do
        local cell = net.ReadUInt(GCIB) + 1
        local b = net.ReadUInt(3)
        local o = net.ReadUInt(8)
        local bl = net.ReadUInt(GC.BuildBits)
        local lvl = net.ReadUInt(2)
        local sh = net.ReadUInt(8)
        GC.biome[cell], GC.owner[cell], GC.build[cell], GC.ship[cell], GC.blevel[cell] = b, o, bl, sh, lvl
        GC.known[cell], GC.vis[cell] = true, true
        if net.ReadBool() then GC.army[cell] = ReadArmyFields() else GC.army[cell] = nil end
    end
    local nHid = net.ReadUInt(15)
    for _ = 1, nHid do
        local cell = net.ReadUInt(GCIB) + 1
        GC.vis[cell] = nil
        GC.ship[cell] = 0
        GC.army[cell] = nil
    end
    BuildRuns()
end)

net.Receive("GCapture_Win", function()
    if net.ReadBool() then
        GC.winner = { name = net.ReadString(), color = Color(net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)) }
    else
        GC.winner = { none = true }
    end
    GC.pick = nil
end)

GC.Msgs = GC.Msgs or {}
net.Receive("GCapture_Msg", function()
    local t = net.ReadString()
    table.insert(GC.Msgs, { text = t, t = CurTime() })
    while #GC.Msgs > 40 do table.remove(GC.Msgs, 1) end
end)

net.Receive("GCapture_Build", function()
    GC.PlaySfx(GC.BuildSound)
end)

GC.airCdClient = GC.airCdClient or {}
net.Receive("GCapture_ExpandSound", function()
    GC.PlaySfx("gcapture/gc_take.wav")
end)
net.Receive("GCapture_AirCD", function()
    local cell, duration = net.ReadUInt(GCIB) + 1, net.ReadFloat()
    GC.airCdClient[cell] = CurTime() + duration
end)

net.Receive("GCapture_Stats", function()
    local n = net.ReadUInt(8)
    for s = 1, n do
        local c, p, w, dead = net.ReadFloat(), net.ReadFloat(), net.ReadFloat(), net.ReadBool()
        local dv, rem = net.ReadFloat(), net.ReadFloat()
        local P = GC.players[s]
        if P then
            P.coins, P.pop, P.weapons, P.dead = c, p, w, dead
            P.disc, P.discEnd = dv, CurTime() + rem
        end
    end
end)

local function SendAct(i, act, i2)
    net.Start("GCapture_Act")
    net.WriteUInt(i - 1, GCIB)
    net.WriteUInt(act, GC.ActBits)
    net.WriteUInt(i2 or 0, GCIB + 1)
    net.SendToServer()
end

function GC.SelectedArmies()
    local out = {}
    for cell, A in pairs(GC.army) do
        if A.owner == GC.mySlot and A.id and GC.sel[A.id] then out[#out + 1] = { cell = cell, A = A } end
    end
    return out
end

local function Ready(A)
    return A.state == GC.ST_IDLE and not (A.trainEnd and CurTime() < A.trainEnd)
end

local function LocalMsg(t)
    table.insert(GC.Msgs, { text = t, t = CurTime() })
end

function GC.GroupMove(to)
    local slot = GC.mySlot
    if not slot then return end

    if GC.Biomes[GC.biome[to]].water then
        if GC.ship[to] ~= slot or GC.army[to] then return end
        local sent = 0
        for _, e in ipairs(GC.SelectedArmies()) do
            if Ready(e.A) and not GC.Biomes[GC.biome[e.cell]].water
                and GC.CanArmyMoveTo(slot, e.cell, to) then
                SendAct(e.cell, 14, to)
                sent = sent + 1
            end
        end
        if sent == 0 then LocalMsg("Select an idle army next to your empty ship.") end
        return
    end

    local list = {}
    for _, e in ipairs(GC.SelectedArmies()) do
        if Ready(e.A) then list[#list + 1] = e end
    end
    if #list == 0 then return LocalMsg("Selected armies can't act now.") end

    local tx, ty = (to - 1) % GCW, math.floor((to - 1) / GCW)
    local function D2(c)
        local x, y = (c - 1) % GCW, math.floor((c - 1) / GCW)
        return (x - tx) ^ 2 + (y - ty) ^ 2
    end

    local sent = 0
    if GC.CanStand(slot, to) then
        local spots = {}
        for c = 1, GCN do
            if GC.CanStand(slot, c) and not GC.army[c] then spots[#spots + 1] = c end
        end
        table.sort(spots, function(a, b) return D2(a) < D2(b) end)
        table.sort(list, function(a, b) return D2(a.cell) < D2(b.cell) end)
        local k = 1
        for _, e in ipairs(list) do
            local dest = spots[k]
            if not dest then break end
            if D2(e.cell) > D2(dest) then
                if GC.Biomes[GC.biome[e.cell]].water then
                    if GC.CanArmyLand(slot, e.cell, dest) then SendAct(e.cell, 18, dest) sent = sent + 1 k = k + 1 end
                else
                    SendAct(e.cell, 14, dest)
                    sent, k = sent + 1, k + 1
                end
            end
        end
    else
        for _, e in ipairs(list) do
            if GC.Biomes[GC.biome[e.cell]].water then
                if GC.CanArmyLand(slot, e.cell, to) then SendAct(e.cell, 18, to) sent = sent + 1 end
            elseif GC.CanArmyAttack(slot, e.cell, to) then
                SendAct(e.cell, 14, to)
                sent = sent + 1
            end
        end
        if sent == 0 then LocalMsg("No selected army is next to that cell.") end
    end
end

function GC.GroupBorder()
    for _, e in ipairs(GC.SelectedArmies()) do
        if Ready(e.A) and not GC.Biomes[GC.biome[e.cell]].water then SendAct(e.cell, 22) end
    end
end

function GC.GroupAuto()
    for _, e in ipairs(GC.SelectedArmies()) do
        if Ready(e.A) and not GC.Biomes[GC.biome[e.cell]].water then SendAct(e.cell, 30) end
    end
end

function GC.GroupStop()
    for _, e in ipairs(GC.SelectedArmies()) do
        if e.A.state == GC.ST_ATTACK then SendAct(e.cell, 16)
        elseif e.A.state == GC.ST_BORDER then SendAct(e.cell, 23)
        elseif e.A.state == GC.ST_IDLE and e.A.auto then SendAct(e.cell, 23) end
    end
end

function GC.GroupDelete()
    for _, e in ipairs(GC.SelectedArmies()) do SendAct(e.cell, 24) end
    GC.sel = {}
end

function GC.SelectedShips()
    local out = {}
    GC.selShip = GC.selShip or {}
    for c in pairs(GC.selShip) do
        if GC.ship[c] == GC.mySlot then out[#out + 1] = c else GC.selShip[c] = nil end
    end
    return out
end

function GC.ShipGroupMove(to)
    for _, c in ipairs(GC.SelectedShips()) do if c ~= to then SendAct(c, 31, to) end end
    GC.selShip = {}
end

function GC.ShipGroupStop()
    for _, c in ipairs(GC.SelectedShips()) do SendAct(c, 31, 0) end
end

local function PickCandidates(pk)
    local out, slot = {}, GC.mySlot
    if not slot then return out end
    if pk.act == 11 then
        for _, j in ipairs(GC.Neighbors(pk.from)) do
            if GC.Biomes[GC.biome[j]].water and GC.ship[j] == 0 then out[#out + 1] = j end
        end
    elseif pk.act == 14 then
        for j = 1, GCN do
            if (GC.CanStand(slot, j) and (not GC.army[j] or j == pk.from))
                or GC.CanArmyMoveTo(slot, pk.from, j)
                or GC.CanArmyAttack(slot, pk.from, j) then
                if j ~= pk.from then out[#out + 1] = j end
            end
        end
    elseif pk.act == 18 then
        for _, j in ipairs(GC.Neighbors8(pk.from)) do
            if GC.CanArmyLand(slot, pk.from, j) then out[#out + 1] = j end
        end
    end
    return out
end

local PICK_HINTS = {
    [11] = "Pick an adjacent water cell",
    [14] = "Friendly = route, your ship = embark, enemy = attack",
    [18] = "Coast cell: own = unload, neutral = claim, enemy = landing",
}

function GC.FillSpirits()
    local f = GC.UI and GC.UI.spirits
    if not IsValid(f) then return end
    f.scroll:Clear()

    local me = GC.players[GC.mySlot or 0]
    local list = me and me.spirits or {}

    if #list == 0 then
        local lbl = f.scroll:Add("DLabel")
        lbl:Dock(TOP)
        lbl:SetTall(30)
        lbl:SetFont("GCapture.Stat")
        lbl:SetTextColor(Color(200, 200, 200))
        lbl:SetText("No national spirits yet.")
        return
    end

    local flag = Material("gcapture/gc_ui_nationalspirit.png")
    for _, inst in ipairs(list) do
        local d = GC.SpiritDefs[inst.id]
        if d then
            local name, lines = GC.SpiritLines(inst, GC.players)

            local row = f.scroll:Add("DPanel")
            row:Dock(TOP)
            row:SetTall(44)
            row:DockMargin(0, 0, 0, 4)
            row:SetTooltip(table.concat(lines, "\n"))
            row.Paint = function(s, w, h)
                draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and TH.rowHover or TH.row)
                surface.SetDrawColor(255, 255, 255)
                surface.SetMaterial(flag)
                surface.DrawTexturedRect(12, h / 2 - 8, 16, 16)
                local T = d.target and GC.players[inst.target or 0]
                draw.SimpleText(name, "GCapture.Stat", 38, h / 2, d.rare and GC.UncommonColor or (T and T.color) or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
    end
end

function GC.OpenSpirits()
    if not GC.UI then return end
    if IsValid(GC.UI.spirits) then
        GC.UI.spirits:MoveToFront()
        return
    end

    local f = vgui.Create("DFrame")
    f:SetTitle("National Spirits")
    f:SetSize(340, 400)
    f:Center()
    f:MakePopup()
    StyleFrame(f)
    f.scroll = vgui.Create("DScrollPanel", f)
    StyleScroll(f.scroll)
    f.scroll:Dock(FILL)
    f.scroll:DockMargin(2, 2, 2, 2)
    GC.UI.spirits = f
    GC.FillSpirits()
end

local function SendDiplo(kind, target, fn)
    net.Start("GCapture_Diplo")
    net.WriteUInt(kind, 4)
    net.WriteUInt(target, 8)
    if fn then fn() end
    net.SendToServer()
end

local function WrapLabel(parent, text)
    local l = vgui.Create("DLabel", parent)
    l:Dock(FILL)
    l:DockMargin(8, 6, 8, 6)
    l:SetFont("GCapture.Stat")
    l:SetTextColor(color_white)
    l:SetWrap(true)
    l:SetContentAlignment(7)
    l:SetText(text)
    return l
end

function GC.OpenLetter(target)
    local T = GC.players[target]
    if not T then return end
    local f = vgui.Create("DFrame")
    f:SetTitle("Letter to " .. T.name)
    f:SetSize(380, 240)
    f:Center()
    f:MakePopup()
    StyleFrame(f)

    local te = vgui.Create("DTextEntry", f)
    StyleEntry(te)
    StyleEntry(te)
    te:Dock(TOP)
    te:SetTall(130)
    te:DockMargin(6, 6, 6, 4)
    te:SetMultiline(true)

    local counter = vgui.Create("DLabel", f)
    counter:Dock(TOP)
    counter:SetTall(18)
    counter:DockMargin(8, 0, 8, 4)
    counter:SetFont("GCapture.Small")
    counter:SetTextColor(Color(200, 200, 200))
    counter:SetText("0 / " .. GC.LetterMax)

    te.OnChange = function(s)
        local t = s:GetValue()
        local len = utf8.len(t) or #t
        if len > GC.LetterMax then
            t = string.sub(t, 1, (utf8.offset(t, GC.LetterMax + 1) or (#t + 1)) - 1)
            s:SetValue(t)
            s:SetCaretPos(#t)
            len = GC.LetterMax
        end
        counter:SetText(len .. " / " .. GC.LetterMax)
    end

    local send = vgui.Create("DButton", f)
    StyleButton(send)
    send:Dock(BOTTOM)
    send:SetTall(30)
    send:DockMargin(6, 4, 6, 6)
    send:SetText("Send")
    send.DoClick = function()
        local text = string.Trim(te:GetValue())
        if text == "" then return end
        SendDiplo(2, target, function() net.WriteString(text) end)
        f:Remove()
    end
end

function GC.OpenDonate(target)
    local T = GC.players[target]
    if not T then return end
    local f = vgui.Create("DFrame")
    f:SetTitle("Donate to " .. T.name)
    f:SetSize(320, 180)
    f:Center()
    f:MakePopup()
    StyleFrame(f)

    local combo = vgui.Create("DComboBox", f)
    StyleButton(combo)
    StyleButton(combo)
    combo:Dock(TOP)
    combo:SetTall(26)
    combo:DockMargin(8, 8, 8, 4)
    combo:AddChoice("Coins", 1, true)
    combo:AddChoice("Weapons", 2)
    combo:AddChoice("Population", 3)

    local te = vgui.Create("DTextEntry", f)
    StyleEntry(te)
    te:Dock(TOP)
    te:SetTall(26)
    te:DockMargin(8, 4, 8, 4)
    te:SetNumeric(true)
    te:SetValue("10")

    local send = vgui.Create("DButton", f)
    StyleButton(send)
    send:Dock(BOTTOM)
    send:SetTall(30)
    send:DockMargin(8, 4, 8, 8)
    send:SetText("Send")
    send.DoClick = function()
        local _, res = combo:GetSelected()
        local amount = math.Clamp(math.floor(tonumber(te:GetValue()) or 0), 0, 65535)
        if not res or amount < 1 then return end
        SendDiplo(3, target, function()
            net.WriteUInt(res, 2)
            net.WriteUInt(amount, 16)
        end)
        f:Remove()
    end
end

local function ShowOffer(fromSlot, name)
    local f = vgui.Create("DFrame")
    f:SetTitle("Non-Aggression Pact")
    f:SetSize(380, 140)
    f:Center()
    f:MakePopup()
    StyleFrame(f)
    WrapLabel(f, name .. " offers a " .. GC.PactTime .. "-second non-aggression pact.")

    local bar = vgui.Create("DPanel", f)
    bar:Dock(BOTTOM)
    bar:SetTall(34)
    bar:DockMargin(8, 4, 8, 8)
    bar.Paint = nil
    local function Respond(accept)
        SendDiplo(4, fromSlot, function() net.WriteBool(accept) end)
        if IsValid(f) then f:Remove() end
    end
    local yes = vgui.Create("DButton", bar)
    StyleButton(yes)
    yes:Dock(LEFT)
    yes:SetWide(170)
    yes:SetText("Accept")
    yes.DoClick = function() Respond(true) end
    local no = vgui.Create("DButton", bar)
    StyleButton(no)
    no:Dock(RIGHT)
    no:SetWide(170)
    no:SetText("Decline")
    no.DoClick = function() Respond(false) end

    timer.Simple(30, function() if IsValid(f) then f:Remove() end end)
end

local function ShowAccessOffer(fromSlot, name)
    local f = vgui.Create("DFrame")
    f:SetTitle("Military Access Request")
    f:SetSize(400, 160)
    f:Center()
    f:MakePopup()
    StyleFrame(f)
    WrapLabel(f, name .. " asks for military access.")

    local bar = vgui.Create("DPanel", f)
    bar:Dock(BOTTOM)
    bar:SetTall(34)
    bar:DockMargin(8, 4, 8, 8)
    bar.Paint = nil
    local function Respond(accept)
        SendDiplo(8, fromSlot, function() net.WriteBool(accept) end)
        if IsValid(f) then f:Remove() end
    end
    local yes = vgui.Create("DButton", bar)
    yes:Dock(LEFT)
    yes:SetWide(180)
    yes:SetText("Allow")
    StyleButton(yes)
    yes.DoClick = function() Respond(true) end
    local no = vgui.Create("DButton", bar)
    no:Dock(RIGHT)
    no:SetWide(180)
    no:SetText("Refuse")
    StyleButton(no)
    no.DoClick = function() Respond(false) end

    timer.Simple(30, function() if IsValid(f) then f:Remove() end end)
end

local function ShowLetter(name, text)
    local f = vgui.Create("DFrame")
    f:SetTitle("Letter from " .. name)
    f:SetSize(380, 220)
    f:Center()
    f:MakePopup()
    StyleFrame(f)

    local close = vgui.Create("DButton", f)
    StyleButton(close)
    close:Dock(BOTTOM)
    close:SetTall(30)
    close:DockMargin(8, 4, 8, 8)
    close:SetText("Close")
    close.DoClick = function() f:Remove() end

    WrapLabel(f, text)
end

local function ShowChoice(remaining, opts)
    if IsValid(GC.choiceFrame) then GC.choiceFrame:Remove() end
    local map = GC.UI and GC.UI.game and GC.UI.game.map
    if not IsValid(map) then return end

    local data, maxLines, total = {}, 0, 0
    for k, inst in ipairs(opts) do
        local name, lines = GC.SpiritLines(inst, GC.players)
        local tw = 0
        surface.SetFont("GCapture.Small")
        for j = 2, #lines do tw = math.max(tw, surface.GetTextSize(lines[j])) end
        surface.SetFont("GCapture.Stat")
        tw = math.max(tw, surface.GetTextSize(name))
        local d = GC.SpiritDefs[inst.id]
        data[k] = { name = name, lines = lines, w = math.max(170, tw + 28), T = inst.target and GC.players[inst.target], rare = d and d.rare }
        maxLines = math.max(maxLines, #lines - 1)
        total = total + data[k].w + 6
    end
    local cardH = 38 + maxLines * 18 + 8 + 34 + 16
    local fullW, fullH = total + 20, 30 + cardH + 10
    local deadline = CurTime() + remaining

    local f = vgui.Create("DPanel", map)
    f:SetSize(fullW, fullH)
    f.collapsed = false
    GC.choiceFrame = f
    f.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, TH.accent)
        draw.RoundedBox(8, 1, 1, w - 2, h - 2, Color(TH.bg.r, TH.bg.g, TH.bg.b, 245))
        draw.SimpleText(s.collapsed and "National Spirit" or "Choose your National Spirit", "GCapture.Stat", 12, 5, TH.accent)
        local left = math.max(0, math.ceil(deadline - CurTime()))
        draw.SimpleText("random in " .. left .. " s", "GCapture.Small", w - 82, 8, TH.muted, TEXT_ALIGN_RIGHT)
    end

    local hide = vgui.Create("DButton", f)
    hide:SetText("Hide")
    StyleButton(hide)
    hide.DoClick = function()
        f.collapsed = not f.collapsed
        hide:SetText(f.collapsed and "Show" or "Hide")
    end

    local row = vgui.Create("DPanel", f)
    row:SetPos(10, 30)
    row:SetSize(total, cardH)
    row.Paint = nil

    f.Think = function(s)
        if math.ceil(deadline - CurTime()) <= 0 then s:Remove() return end
        local w, h = fullW, fullH
        if s.collapsed then w, h = 360, 30 end
        if s:GetWide() ~= w or s:GetTall() ~= h then s:SetSize(w, h) end
        s:SetPos(math.floor((map:GetWide() - w) / 2), map:GetTall() - h - 14)
        hide:SetPos(w - 70, 4)
        hide:SetSize(62, 22)
        row:SetVisible(not s.collapsed)
    end

    for k, inst in ipairs(opts) do
        local d = data[k]
        local card = vgui.Create("DPanel", row)
        card:Dock(LEFT)
        card:SetWide(d.w)
        card:DockMargin(0, 0, 6, 0)
        card.hv = 0
        card.Paint = function(s, w, h)
            s.hv = Lerp(math.min(1, FrameTime() * 12), s.hv, (s:IsHovered() or s:IsChildHovered()) and 1 or 0)
            draw.RoundedBox(6, 0, 0, w, h, LerpColor(s.hv, TH.accentDim, TH.accent))
            draw.RoundedBox(6, 1, 1, w - 2, h - 2, LerpColor(s.hv, TH.row, TH.rowHover))
            local nc = d.rare and GC.UncommonColor or (d.T and d.T.color) or TH.text
            draw.SimpleText(d.name, "GCapture.Stat", w / 2, 8, nc, TEXT_ALIGN_CENTER)
            surface.SetDrawColor(TH.accentDim)
            surface.DrawRect(10, 32, w - 20, 1)
            for j = 2, #d.lines do
                draw.SimpleText(d.lines[j], "GCapture.Small", 12, 38 + (j - 2) * 18, TH.text)
            end
        end

        local btn = vgui.Create("DButton", card)
        btn:Dock(BOTTOM)
        btn:SetTall(26)
        btn:DockMargin(8, 0, 8, 8)
        btn:SetText("Choose")
        StyleButton(btn)
        btn.DoClick = function()
            net.Start("GCapture_Pick")
            net.WriteUInt(k, 2)
            net.SendToServer()
            f:Remove()
        end
    end
end

net.Receive("GCapture_Choice", function()
    local remaining, n = net.ReadUInt(7), net.ReadUInt(2)
    local opts = {}
    for k = 1, n do
        local id = net.ReadString()
        local target = net.ReadUInt(8)
        opts[k] = { id = id, target = target ~= 0 and target or nil }
    end
    if n > 0 then ShowChoice(remaining, opts) end
end)

net.Receive("GCapture_Access", function()
    GC.access, GC.muted = {}, {}
    for _ = 1, net.ReadUInt(12) do
        local g, e = net.ReadUInt(8), net.ReadUInt(8)
        GC.access[g * 256 + e] = true
    end
    for _ = 1, net.ReadUInt(8) do
        local c = net.ReadUInt(8)
        if GC.mySlot then GC.muted[GC.mySlot * 256 + c] = true end
    end
end)

net.Receive("GCapture_Diplo", function()
    local kind, from, name = net.ReadUInt(2), net.ReadUInt(8), net.ReadString()
    if kind == 1 then
        ShowOffer(from, name)
    elseif kind == 2 then
        ShowLetter(name, net.ReadString())
    elseif kind == 3 then
        ShowAccessOffer(from, name)
    end
end)

CreateClientConVar("cl_gc_record", "0", true, false)
local DEMO_DIR = "gcapture/demos/"

function GC.SendRec(v)
    net.Start("GCapture_Rec")
    net.WriteBool(v and true or false)
    net.SendToServer()
end

net.Receive("GCapture_DemoSend", function()
    if net.ReadBool() then
        GC.dl = { parts = {}, dur = net.ReadUInt(32), ts = net.ReadUInt(32), win = net.ReadString(), pl = net.ReadString(),
            total = net.ReadUInt(32), crc = net.ReadString() }
    end
    local part = net.ReadData(net.ReadUInt(16))
    local last = net.ReadBool()
    local dl = GC.dl
    if not dl then return end
    dl.parts[#dl.parts + 1] = part
    if not last then return end
    GC.dl = nil
    local all = table.concat(dl.parts)
    if #all ~= dl.total or util.CRC(all) ~= dl.crc then
        LocalMsg("Demo is corrupted, not saved.")
        return
    end

    file.CreateDir("gcapture")
    file.CreateDir("gcapture/demos")
    local function clean(s) return (string.gsub(s, "[|\r\n]", " ")) end
    local fname = os.date("%Y-%m-%d_%H-%M-%S", dl.ts) .. ".txt"
    local head = string.format("GCDEMO1|%d|%d|%s|%s\n", dl.dur, dl.ts, clean(dl.win), clean(dl.pl))
    file.Write(DEMO_DIR .. fname, head .. util.Base64Encode(all))
    LocalMsg("Demo saved: data/" .. DEMO_DIR .. fname)
    print("[GCapture] Demo saved: data/" .. DEMO_DIR .. fname)
end)

local function DemoClearFx()
    GC.cellFx, GC.bSpawn, GC.bGhost, GC.armySpawn, GC.armyGhost, GC.flashes, GC.orgFlashes = {}, {}, {}, {}, {}, {}, {}
end

local function DemoBiome(value)
    value = tonumber(value)
    if value and GC.Biomes[value] then return value end

    return GC.PLAINS or 1
end

local function DemoReset(dm)
    GC.owner, GC.build, GC.ship, GC.blevel, GC.army = {}, {}, {}, {}, {}
    for i = 1, GCN do GC.owner[i], GC.build[i], GC.ship[i], GC.blevel[i] = 0, 0, 0, 0 end
    for i = 1, GCN do GC.biome[i] = DemoBiome(dm.d.biome and dm.d.biome[i]) end
    dm.rebuild = true
    for _, P in ipairs(GC.players) do P.spirits = {} P.ever, P.dead = false, false end
    DemoClearFx()
    GC.eventBanner, GC.virusEnd, GC.screenFlash = nil, nil, nil
    dm.k = 0
end

local function DemoCell(i, o, b, lvl, live)
    if live then
        local ob, oo, now = GC.build[i], GC.owner[i], CurTime()
        if b ~= ob then
            if ob ~= 0 and ob ~= GC.B_FIRE and mats[ob] then GC.bGhost[i] = { b = ob, t = now } end
            if b ~= 0 then GC.bSpawn[i] = now end
            if b ~= 0 and b ~= GC.B_FIRE then GC.cellFx[i] = { kind = "build", t = now } end
        elseif b == GC.B_BARRICADE and lvl ~= (GC.blevel[i] or 0) then
            GC.bSpawn[i] = now
            GC.cellFx[i] = { kind = "build", t = now }
        end
        local fx = GC.cellFx[i]
        if o ~= oo and o ~= 0 and not (fx and fx.kind == "build") then
            local P = GC.players[o]
            local c = P and P.color or color_white
            GC.cellFx[i] = { kind = "claim", t = now, r = Lerp(0.45, c.r, 255), g = Lerp(0.45, c.g, 255), b = Lerp(0.45, c.b, 255) }
        end
    end
    GC.owner[i], GC.build[i], GC.blevel[i] = o, b, lvl
end

local function DemoArmies(a, live)
    local now = CurTime()
    local oldById = {}
    for cell, A in pairs(GC.army) do oldById[A.id] = { cell = cell, A = A } end
    local new, newIds = {}, {}
    for j = 1, #a, 10 do
        local A = { id = a[j + 1], owner = a[j + 2], org = a[j + 3], hp = a[j + 4], state = a[j + 5],
            target = a[j + 6], maxOrg = a[j + 7], maxHp = a[j + 8], cav = a[j + 9] == 1 }
        new[a[j]] = A
        newIds[A.id] = true
        if live then
            local o = oldById[A.id]
            if not o then GC.armySpawn[A.id] = now
            elseif A.org < o.A.org then GC.orgFlashes[a[j]] = now end
        end
    end
    if live then
        for id, e in pairs(oldById) do
            if not newIds[id] then GC.armyGhost[e.cell] = { A = e.A, t = now } end
        end
    end
    GC.army = new
end

local function DemoFrame(f, live)
    if f.c then
        for j = 1, #f.c, 4 do DemoCell(f.c[j], f.c[j + 1], f.c[j + 2], f.c[j + 3], live) end
    end
    if f.s then
        for j = 1, #f.s, 2 do GC.ship[f.s[j]] = f.s[j + 1] end
    end
    if f.r then
        for s, P in ipairs(GC.players) do
            local b = (s - 1) * 3
            P.coins, P.pop, P.weapons = f.r[b + 1] or 0, f.r[b + 2] or 0, f.r[b + 3] or 0
        end
    end
    if f.bm then
        for j = 1, #f.bm, 2 do
            local cell = tonumber(f.bm[j])
            if cell and cell >= 1 and cell <= GCN then
                GC.biome[cell] = DemoBiome(f.bm[j + 1])
            end
        end
        if GC.demo then GC.demo.rebuild = true end
    end
    if live and f.ev then
        for _, e in ipairs(f.ev) do
            local kind, title, arg = e[1], e[2], e[3] or 0
            if title ~= "" then GC.eventBanner = { text = title, t = CurTime() } end
            if kind == 3 then GC.screenFlash = { t = CurTime(), c = 255 }
            elseif kind == 4 then GC.screenFlash = { t = CurTime(), c = 0 }
            elseif kind == 6 then GC.virusEnd = CurTime() + arg / math.max(0.1, GC.demo and GC.demo.speed or 1) end
            if kind ~= 4 then GC.PlaySfx("ambient/alarms/warningbell1.wav") end
        end
    end
    if f.sp then
        for s, P in ipairs(GC.players) do
            local l = {}
            for _, e in ipairs(f.sp[s] or {}) do
                local id, t = string.match(e, "^(%w+):(%d+)$")
                if id then l[#l + 1] = { id = id, target = (tonumber(t) or 0) ~= 0 and tonumber(t) or nil } end
            end
            P.spirits = l
        end
    end
    if live and f.e then
        for _, cell in ipairs(f.e) do
            GC.flashes[cell] = CurTime()
            GC.lastBoom, GC.shakeEnd = CurTime(), CurTime() + 0.6
            GC.PlaySfx("gcapture/gc_explode.ogg")
        end
    end
end

local function DemoAlive()
    local has = {}
    for i = 1, GCN do
        local o = GC.owner[i]
        if o ~= 0 then has[o] = true end
    end
    for s, P in ipairs(GC.players) do
        if has[s] then P.ever = true end
        P.dead = (P.ever and not has[s]) or false
    end
end

function GC.DemoSeek(k)
    local dm = GC.demo
    if not dm then return end
    local fr = dm.d.frames
    k = math.Clamp(math.floor(k), 0, #fr)
    if k < dm.k then DemoReset(dm) end
    local step = k - dm.k
    if step <= 0 then return end
    if step > 1 then DemoClearFx() end
    for j = dm.k + 1, k do DemoFrame(fr[j], step == 1) end
    dm.k = k
    if step > 1 or fr[k].a then
        for j = k, 1, -1 do
            if fr[j].a then DemoArmies(fr[j].a, step == 1) break end
        end
    end
    if dm.rebuild then dm.rebuild = false BuildRuns() end
    DemoAlive()
end

hook.Add("Think", "GCapture_Demo", function()
    local dm = GC.demo
    if not dm or GC.demoMode ~= "play" then return end
    GC.dayOffset = (dm.k - 1) - CurTime()
    if not dm.playing then return end
    local total = #dm.d.frames
    dm.acc = dm.acc + FrameTime() * dm.speed
    while dm.acc >= 1 do
        dm.acc = dm.acc - 1
        if dm.k >= total then dm.playing, dm.acc = false, 0 break end
        GC.DemoSeek(dm.k + 1)
    end
end)

function GC.PlayDemo(fname)
    local raw = file.Read(DEMO_DIR .. fname, "DATA")
    local nl = raw and string.find(raw, "\n", 1, true)
    local d
    if nl then
        local body = string.gsub(string.sub(raw, nl + 1), "%s", "")
        local js = util.Decompress(util.Base64Decode(body) or "", 100000000)
        d = js and util.JSONToTable(js)
    end
    local function Bad() return Derma_Message("Corrupted or unknown demo format.", "Demo", "OK") end
    if not d or type(d.frames) ~= "table" or #d.frames == 0 or type(d.players) ~= "table" then return Bad() end

    local w, h, biome = tonumber(d.w), tonumber(d.h), {}
    if type(d.bs) == "string" then
        if not w or not h or #d.bs ~= w * h then return Bad() end
        for i = 1, w * h do biome[i] = math.Clamp(string.byte(d.bs, i) - 48, 1, 5) end
    elseif type(d.biome) == "table" then
        if not w or not h then
            w = math.floor(math.sqrt(#d.biome) + 0.5)
            h = w
        end
        for i = 1, w * h do
            biome[i] = d.biome[i]
            if not biome[i] then return Bad() end
        end
    else
        return Bad()
    end
    if w < 4 or h < 4 or w > 512 or h > 512 then return Bad() end
    d.biome = biome

    GC.SetSize(w, h)
    GC.demoMode = "play"
    GC.seed = d.seed or ""
    GC.demo = { d = d, k = 0, playing = true, speed = 1, acc = 0, evMarks = {} }
    GC.players = {}
    for s, p in ipairs(d.players) do
        GC.players[s] = { name = p[1], color = Color(p[2], p[3], p[4]), diff = p[5] or "", coins = 0, pop = 0, weapons = 0, spirits = {} }
    end
    GC.mySlot, GC.winner, GC.pick, GC.fog, GC.sel = nil, nil, nil, false, {}
    GC.pacts, GC.oilUsed, GC.vis, GC.fogA, GC.clouds, GC.known = {}, {}, {}, {}, nil, {}
    GC.focusPending, GC.runs = nil, nil
    GC.biome = {}
    for i = 1, GCN do
        GC.biome[i] = biome[i]
        GC.known[i] = true
    end
    DemoReset(GC.demo)
    BuildRuns()

    for k, f in ipairs(d.frames) do
        if f.ev then
            for _, e in ipairs(f.ev) do
                if e[2] ~= "" then GC.demo.evMarks[#GC.demo.evMarks + 1] = { k, e[2] } break end
            end
        end
    end

    local m = GC.UI and GC.UI.game and GC.UI.game.map
    if IsValid(m) then m.zoom, m.tz, m.tox, m.toy = 1, 1, nil, nil end
    GC.playing = true
    GC.DemoSeek(1)
    GC.RefreshUI()
end

function GC.EnterDemoList()
    GC.demoMode, GC.demo, GC.playing = "list", nil, false
    net.Start("GCapture_View")
    net.WriteBool(false)
    net.SendToServer()
    GC.RefreshUI()
end

function GC.ExitDemo()
    GC.demo, GC.demoMode, GC.playing, GC.gameId = nil, "list", false, nil
    GC.army, GC.players, GC.owner, GC.build, GC.ship = {}, {}, {}, {}, {}
    DemoClearFx()
    GC.RefreshUI()
end

function GC.LeaveDemos()
    GC.demoMode, GC.demo, GC.playing, GC.gameId = nil, nil, false, nil
    net.Start("GCapture_View")
    net.WriteBool(true)
    net.SendToServer()
    GC.RefreshUI()
end

local function ReadDemoHeader(fn)
    local f = file.Open(DEMO_DIR .. fn, "r", "DATA")
    if not f then return end
    local line = f:ReadLine()
    f:Close()
    local dur, ts, win, pl = string.match(line or "", "^GCDEMO1|(%d+)|(%d+)|([^|]*)|([^\r\n]*)")
    if not dur then return end
    return tonumber(dur), tonumber(ts), win, pl
end

local function BuildDemos(root)
    local p = vgui.Create("DPanel", root)
    p:Dock(FILL)
    p.Paint = nil
    p:SetVisible(false)

    local box = vgui.Create("DPanel", p)
    box:Dock(FILL)
    box.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, TH.accentDim)
        draw.RoundedBox(6, 1, 1, w - 2, h - 2, TH.bg)
        GC.PanelBloom(w, h, 0.7)
    end

    local title = vgui.Create("DLabel", box)
    title:Dock(TOP)
    title:SetTall(30)
    title:SetFont("GCapture.Stat")
    title:SetTextColor(TH.accent)
    title:SetText("  Demos  (data/gcapture/demos)")

    local bottom = vgui.Create("DPanel", box)
    bottom:Dock(BOTTOM)
    bottom:SetTall(40)
    bottom:DockMargin(6, 0, 6, 6)
    bottom.Paint = nil

    local ui = { panel = p }

    local back = vgui.Create("DButton", bottom)
    back:Dock(LEFT) back:SetWide(110) back:SetText("Back to Lobby") StyleButton(back)
    back.DoClick = function() GC.LeaveDemos() end

    local play = vgui.Create("DButton", bottom)
    play:Dock(RIGHT) play:SetWide(130) play:DockMargin(6, 0, 0, 0) play:SetText("Play Demo") StyleButton(play)
    play.DoClick = function() if ui.sel then GC.PlayDemo(ui.sel) end end

    local del = vgui.Create("DButton", bottom)
    del:Dock(RIGHT) del:SetWide(110) del:SetText("Delete") StyleButton(del)
    del.DoClick = function()
        local fn = ui.sel
        if not fn then return end
        Derma_Query("Delete this demo?", "Delete Demo", "Delete", function()
            file.Delete(DEMO_DIR .. fn)
            ui.Refresh()
        end, "Cancel")
    end

    local scroll = vgui.Create("DScrollPanel", box)
    scroll:Dock(FILL)
    scroll:DockMargin(6, 0, 6, 6)
    StyleScroll(scroll)

    local function UpdateBtns()
        play:SetEnabled(ui.sel ~= nil)
        del:SetEnabled(ui.sel ~= nil)
    end

    function ui.Refresh()
        scroll:Clear()
        ui.sel = nil
        UpdateBtns()
        local files = file.Find(DEMO_DIR .. "*.txt", "DATA", "datedesc") or {}
        if #files == 0 then
            local l = scroll:Add("DLabel")
            l:Dock(TOP)
            l:SetTall(60)
            l:DockMargin(8, 8, 8, 0)
            l:SetFont("GCapture.Small")
            l:SetTextColor(TH.muted)
            l:SetWrap(true)
            l:SetText("No demos yet. Enable \"Record Demo\" in the lobby.")
            return
        end
        for _, fn in ipairs(files) do
            local dur, ts, win, pl = ReadDemoHeader(fn)
            local when = ts and os.date("%Y-%m-%d  %H:%M:%S", ts) or fn
            local info = dur and string.format("%d:%02d   Winner: %s", math.floor(dur / 60), dur % 60, win ~= "" and win or "-") or "unknown format"
            local kb = string.format("%.0f KB", file.Size(DEMO_DIR .. fn, "DATA") / 1024)

            local row = scroll:Add("DButton")
            row:Dock(TOP)
            row:SetTall(48)
            row:DockMargin(0, 0, 0, 4)
            row:SetText("")
            row.hv = 0
            row.Paint = function(s, w, h)
                s.hv = Lerp(math.min(1, FrameTime() * 14), s.hv, s:IsHovered() and 1 or 0)
                local sel = ui.sel == fn
                draw.RoundedBox(4, 0, 0, w, h, sel and TH.accent or LerpColor(s.hv, TH.hd, TH.accentDim))
                draw.RoundedBox(4, 1, 1, w - 2, h - 2, sel and TH.rowHover or LerpColor(s.hv, TH.row, TH.rowHover))
                draw.SimpleText(when .. "    " .. info, "GCapture.Stat", 10, 5, TH.text)
                draw.SimpleText((pl or "") .. "    (" .. kb .. ")", "GCapture.Small", 10, 28, TH.muted)
            end
            row.DoClick = function() ui.sel = fn UpdateBtns() end
            row.DoDoubleClick = function() ui.sel = fn GC.PlayDemo(fn) end
        end
    end

    return ui
end

local MAP_DIR = "gcapture/maps/"
local DIG = { "1", "2", "3", "4", "5" }

local function MapHeader(fn)
    local f = file.Open(MAP_DIR .. fn, "r", "DATA")
    if not f then return end
    local line = f:ReadLine()
    f:Close()
    local w, h, np, name = string.match(line or "", "^GCMAP2|(%d+)|(%d+)|(%d+)|([^\r\n]*)")
    if w then return tonumber(w), tonumber(h), name, tonumber(np) end
    w, h, name = string.match(line or "", "^GCMAP1|(%d+)|(%d+)|([^\r\n]*)")
    if w then return tonumber(w), tonumber(h), name, 0 end
end

local function MapRead(fn)
    local raw = file.Read(MAP_DIR .. fn, "DATA")
    local nl = raw and string.find(raw, "\n", 1, true)
    if not nl then return end
    local body = string.gsub(string.sub(raw, nl + 1), "%s", "")
    local js = util.Decompress(util.Base64Decode(body) or "", 20000000)
    local d = js and util.JSONToTable(js)
    if not d or type(d.w) ~= "number" or type(d.h) ~= "number" or type(d.b) ~= "string" then return end
    if d.w < 1 or d.h < 1 or d.w > 512 or d.h > 512 or #d.b ~= d.w * d.h then return end
    d.name = tostring(d.name or "Map")
    return d
end

local function MapWrite(E)
    local t, s, v, c = {}, {}, {}, {}
    for i = 1, E.w * E.h do t[i] = DIG[E.biome[i]] or "5" end
    for cell, m in pairs(E.mark) do
        if m == "s" then s[#s + 1] = cell elseif m == "v" then v[#v + 1] = cell else c[#c + 1] = cell end
    end
    table.sort(s) table.sort(v) table.sort(c)

    local by = {}
    for cell, id in pairs(E.terr or {}) do
        local l = by[id]
        if not l then l = {} by[id] = l end
        l[#l + 1] = cell
    end
    local pre = {}
    for _, C in ipairs(E.pre or {}) do
        local cells = by[C.id] or {}
        table.sort(cells)
        pre[#pre + 1] = { n = string.Trim(C.name or ""), s = C.spawn or 0, c = cells,
            k = C.color and { C.color.r, C.color.g, C.color.b } or nil }
    end
    local js = util.TableToJSON({ w = E.w, h = E.h, name = E.name, b = table.concat(t), s = s, v = v, c = c, p = pre })
    file.CreateDir("gcapture")
    file.CreateDir("gcapture/maps")
    local head = string.format("GCMAP2|%d|%d|%d|%s\n", E.w, E.h, #pre, (string.gsub(E.name, "[|\r\n]", " ")))
    file.Write(MAP_DIR .. E.fname .. ".txt", head .. util.Base64Encode(util.Compress(js)))
end

function GC.UploadMap(fn)
    if not fn then
        net.Start("GCapture_MapUp")
        net.WriteBool(false)
        net.SendToServer()
        return
    end
    local d = MapRead(fn)
    if not d then return Derma_Message("Corrupted map file.", "Map", "OK") end
    local data = util.Compress(util.TableToJSON({ w = d.w, h = d.h, b = d.b, s = d.s or {}, v = d.v or {}, c = d.c or {}, p = d.p or {} }))
    local CH = 30000
    local n = math.max(1, math.ceil(#data / CH))
    for k = 1, n do
        timer.Simple((k - 1) * 0.1, function()
            local part = string.sub(data, (k - 1) * CH + 1, k * CH)
            net.Start("GCapture_MapUp")
            net.WriteBool(true)
            net.WriteBool(k == 1)
            if k == 1 then net.WriteString(d.name) end
            net.WriteUInt(#part, 16)
            net.WriteData(part, #part)
            net.WriteBool(k == n)
            net.SendToServer()
        end)
    end
end

local function MapRename(fn, newName, newFile)
    local raw = file.Read(MAP_DIR .. fn, "DATA")
    local nl = raw and string.find(raw, "\n", 1, true)
    if not nl then return false, "File not readable." end
    local body = string.gsub(string.sub(raw, nl + 1), "%s", "")
    local js = util.Decompress(util.Base64Decode(body) or "", 20000000)
    local d = js and util.JSONToTable(js)
    if not d then return false, "Corrupted map file." end
    d.name = newName
    local target = (newFile ~= "" and newFile or string.StripExtension(fn)) .. ".txt"
    if target ~= fn and file.Exists(MAP_DIR .. target, "DATA") then return false, "File name already taken." end
    local head = string.format("GCMAP2|%d|%d|%d|%s\n", d.w, d.h, type(d.p) == "table" and #d.p or 0, (string.gsub(newName, "[|\r\n]", " ")))
    file.Write(MAP_DIR .. target, head .. util.Base64Encode(util.Compress(util.TableToJSON(d))))
    if target ~= fn then file.Delete(MAP_DIR .. fn) end
    return true
end

function GC.OpenMapRename(fn, done)
    local _, _, name = MapHeader(fn)
    local f = vgui.Create("DFrame")
    f:SetTitle("Rename Map")
    f:SetSize(380, 220)
    f:Center()
    f:MakePopup()
    StyleFrame(f)
    local function Field(y, label, def)
        local l = vgui.Create("DLabel", f)
        l:SetPos(16, y)
        l:SetFont("GCapture.Small")
        l:SetTextColor(TH.muted)
        l:SetText(label)
        l:SizeToContents()
        local te = vgui.Create("DTextEntry", f)
        te:SetPos(16, y + 18)
        te:SetSize(348, 26)
        te:SetValue(def)
        StyleEntry(te)
        return te
    end
    local tn = Field(36, "Map name", name or "")
    local tf = Field(90, "File name (letters, digits, _ and -)", string.StripExtension(fn))
    tn.OnChange = function(s) local t = s:GetValue() if #t > 40 then s:SetValue(string.sub(t, 1, 40)) end end
    tf.OnChange = function(s)
        local t = s:GetValue()
        local c = string.sub(string.gsub(t, "[^%w_%-]", ""), 1, 40)
        if c ~= t then s:SetValue(c) s:SetCaretPos(#c) end
    end
    local go = vgui.Create("DButton", f)
    go:SetPos(16, 160)
    go:SetSize(348, 34)
    go:SetText("Rename")
    StyleButton(go)
    go.DoClick = function()
        local nn = string.Trim(tn:GetValue())
        if nn == "" then return Derma_Message("Enter a map name.", "Rename", "OK") end
        local ok, err = MapRename(fn, nn, string.gsub(tf:GetValue(), "[^%w_%-]", ""))
        if not ok then return Derma_Message(err or "Failed.", "Rename", "OK") end
        f:Remove()
        if done then done() end
    end
end

function GC.OpenMapEditor(E)
    if IsValid(GC.mmFrame) then GC.mmFrame:Remove() end
    E.mark = E.mark or {}
    E.runs, E.dirty, E.undo, E.redo = {}, {}, {}, {}
    E.tool, E.brush, E.changed = { biome = 1 }, 3, false
    E.fill = false

    E.pre, E.terr, E.nid, E.edit = E.pre or {}, E.terr or {}, E.nid or 0, nil

    local function Country(id)
        for _, C in ipairs(E.pre) do
            if C.id == id then return C end
        end
    end
    local function PCol(id)
        local C = Country(id)
        if C and C.color then return Color(C.color.r, C.color.g, C.color.b) end
        return HSVToColor((id * 67) % 360, 0.75, 1)
    end

    local function PickColor(C)
        if IsValid(E.colorWin) then E.colorWin:Remove() end
        local w = vgui.Create("DFrame")
        w:SetTitle("Country color")
        w:SetSize(300, 252)
        w:Center()
        w:MakePopup()
        StyleFrame(w)
        E.colorWin = w
        local c0 = PCol(C.id)
        local mx = vgui.Create("DColorMixer", w)
        mx:SetPos(10, 34)
        mx:SetSize(280, 160)
        mx:SetPalette(false)
        mx:SetAlphaBar(false)
        mx:SetWangs(true)
        mx:SetColor(Color(c0.r, c0.g, c0.b))
        mx.ValueChanged = function(s, col)
            if not C.color and col.r == c0.r and col.g == c0.g and col.b == c0.b then return end
            C.color = Color(col.r, col.g, col.b)
            E.changed = true
        end
        local ok = vgui.Create("DButton", w)
        ok:SetPos(10, 206)
        ok:SetSize(280, 30)
        ok:SetText("OK")
        StyleButton(ok)
        ok.DoClick = function() w:Remove() end
    end

    local function Raw(k, c, v)
        if k == "b" then
            E.biome[c] = v
            E.dirty[math.floor((c - 1) / E.w)] = true
        elseif k == "t" then
            E.terr[c] = v
        elseif k == "sp" then
            local C = Country(c)
            if C then C.spawn = v end
        else
            E.mark[c] = v
        end
    end
    local function Set(k, c, v)
        local old
        if k == "b" then old = E.biome[c]
        elseif k == "t" then old = E.terr[c]
        elseif k == "sp" then local C = Country(c) old = C and C.spawn
        else old = E.mark[c] end
        if old == v then return end
        Raw(k, c, v)
        local st = E.stroke
        if st then st[#st + 1] = { k = k, c = c, o = old, n = v } end
    end
    local function Begin() E.stroke = {} end
    local function End()
        local st = E.stroke
        E.stroke = nil
        if st and #st > 0 then
            E.undo[#E.undo + 1] = st
            if #E.undo > 200 then table.remove(E.undo, 1) end
            E.redo = {}
            E.changed = true
        end
    end
    local function Undo()
        local st = table.remove(E.undo)
        if not st then return end
        for k = #st, 1, -1 do Raw(st[k].k, st[k].c, st[k].o) end
        E.redo[#E.redo + 1] = st
        E.changed = true
    end
    local function Redo()
        local st = table.remove(E.redo)
        if not st then return end
        for k = 1, #st do Raw(st[k].k, st[k].c, st[k].n) end
        E.undo[#E.undo + 1] = st
        E.changed = true
    end
    local function Note(t) E.msg, E.msgT = t, CurTime() end
    local function Editing() return E.edit ~= nil and E.tool.terr ~= nil and Country(E.edit) ~= nil end

    local function DropOnWater(c)
        if E.mark[c] then Set("m", c, nil) end
        local id = E.terr[c]
        if id then
            Set("t", c, nil)
            local C = Country(id)
            if C and C.spawn == c then Set("sp", id, nil) end
        end
    end

    local function Stamp(cell)
        local cx, cy = (cell - 1) % E.w, math.floor((cell - 1) / E.w)
        local R = E.brush / 2
        local r = math.ceil(R)
        local id = E.tool.biome
        for y = math.max(0, cy - r), math.min(E.h - 1, cy + r) do
            for x = math.max(0, cx - r), math.min(E.w - 1, cx + r) do
                if (x - cx) ^ 2 + (y - cy) ^ 2 <= R * R then
                    local c = y * E.w + x + 1
                    Set("b", c, id)
                    if id == 5 then DropOnWater(c) end
                end
            end
        end
    end
    local function PlaceMark(cell)
        local t = E.tool
        if t.erase then Set("m", cell, nil) return end
        if E.biome[cell] == 5 then return Note("Markers go on land only.") end
        if E.mark[cell] == t.mark then Set("m", cell, nil) else Set("m", cell, t.mark) end
    end

    local function Fill(cell)
        local id, old = E.tool.biome, E.biome[cell]
        if id == old then return end
        local w, hgt = E.w, E.h
        local q, head, seen = { cell }, 1, { [cell] = true }
        while head <= #q do
            local c = q[head]
            head = head + 1
            Set("b", c, id)
            if id == 5 then DropOnWater(c) end
            local x, y = (c - 1) % w, math.floor((c - 1) / w)
            local nb = {}
            if x > 0 then nb[#nb + 1] = c - 1 end
            if x < w - 1 then nb[#nb + 1] = c + 1 end
            if y > 0 then nb[#nb + 1] = c - w end
            if y < hgt - 1 then nb[#nb + 1] = c + w end
            for _, j in ipairs(nb) do
                if not seen[j] and E.biome[j] == old then
                    seen[j] = true
                    q[#q + 1] = j
                end
            end
        end
    end

    local function Line(from, to, fn)
        local fx, fy = (from - 1) % E.w, math.floor((from - 1) / E.w)
        local tx, ty = (to - 1) % E.w, math.floor((to - 1) / E.w)
        local steps = math.max(math.abs(tx - fx), math.abs(ty - fy))
        for k = 0, steps do
            local t = steps == 0 and 0 or k / steps
            fn(math.floor(fy + (ty - fy) * t + 0.5) * E.w + math.floor(fx + (tx - fx) * t + 0.5) + 1)
        end
    end

    local function StampT(cell, add)
        local C = Country(E.edit)
        if not C then return end
        local cx, cy = (cell - 1) % E.w, math.floor((cell - 1) / E.w)
        local R = E.brush / 2
        local r = math.ceil(R)
        for y = math.max(0, cy - r), math.min(E.h - 1, cy + r) do
            for x = math.max(0, cx - r), math.min(E.w - 1, cx + r) do
                if (x - cx) ^ 2 + (y - cy) ^ 2 <= R * R then
                    local c = y * E.w + x + 1
                    if E.biome[c] ~= 5 then
                        local o = E.terr[c]
                        if add then
                            if o == nil then Set("t", c, C.id) end
                        elseif o == C.id then
                            Set("t", c, nil)
                            if C.spawn == c then Set("sp", C.id, nil) end
                        end
                    end
                end
            end
        end
    end
    local function PlaceSpawn(cell)
        local C = Country(E.edit)
        if not C then return end
        if E.biome[cell] == 5 then return Note("Spawn must be on land.") end
        local o = E.terr[cell]
        if o ~= nil and o ~= C.id then return Note("This cell belongs to another country.") end
        if o == nil then Set("t", cell, C.id) end
        Set("sp", C.id, cell)
    end

    local function Apply(from, to)
        local T = E.tool
        if T.terr then
            if T.terr == "spawn" then
                if not from then PlaceSpawn(to) end
                return
            end
            local add = T.terr == "add"
            if not from then return StampT(to, add) end
            return Line(from, to, function(c) StampT(c, add) end)
        end
        if not E.tool.biome then
            if not from then PlaceMark(to) end
            return
        end
        if not from then
            if E.fill then return Fill(to) end
            return Stamp(to)
        end
        local fx, fy = (from - 1) % E.w, math.floor((from - 1) / E.w)
        local tx, ty = (to - 1) % E.w, math.floor((to - 1) / E.w)
        local steps = math.max(math.abs(tx - fx), math.abs(ty - fy))
        for k = 0, steps do
            local t = steps == 0 and 0 or k / steps
            Stamp(math.floor(fy + (ty - fy) * t + 0.5) * E.w + math.floor(fx + (tx - fx) * t + 0.5) + 1)
        end
    end

    local function Runs(y)
        if E.runs[y] and not E.dirty[y] then return E.runs[y] end
        local row, x, base = {}, 0, y * E.w
        while x < E.w do
            local b, s = E.biome[base + x + 1], x
            while x < E.w and E.biome[base + x + 1] == b do x = x + 1 end
            row[#row + 1] = { s, x - s, b }
        end
        E.runs[y], E.dirty[y] = row, nil
        return row
    end

    local f = vgui.Create("DFrame")
    f:SetTitle("Map Maker - " .. E.name .. " (" .. E.w .. "x" .. E.h .. ")")
    f:SetSize(math.min(1300, ScrW() - 60), math.min(900, ScrH() - 60))
    f:Center()
    f:MakePopup()
    StyleFrame(f)
    GC.mmFrame = f

    local function Save()
        local land = false
        for i = 1, E.w * E.h do if E.biome[i] ~= 5 then land = true break end end
        if not land then return Note("No land, nothing to save.") end
        MapWrite(E)
        E.changed = false
        local bad = 0
        for _, C in ipairs(E.pre) do if not C.spawn then bad = bad + 1 end end
        Note("Saved: data/" .. MAP_DIR .. E.fname .. ".txt" ..
            (bad > 0 and (" (" .. bad .. " countries without a spawn are skipped)") or ""))
    end
    local function Exit()
        if E.changed then
            Derma_Query("Exit without saving?", "Map Maker", "Exit", function() if IsValid(f) then f:Remove() end end, "Cancel")
        else
            f:Remove()
        end
    end
    f.btnClose.DoClick = Exit

    local bar = vgui.Create("DPanel", f)
    bar:Dock(TOP)
    bar:SetTall(72)
    bar:DockMargin(0, 0, 0, 4)
    bar.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, TH.accentDim)
        draw.RoundedBox(6, 1, 1, w - 2, h - 2, TH.bg)
        GC.PanelBloom(w, h, 0.7)
        local ns, nv, nc = 0, 0, 0
        for _, m in pairs(E.mark) do
            if m == "s" then ns = ns + 1 elseif m == "v" then nv = nv + 1 else nc = nc + 1 end
        end
        draw.SimpleText(string.format("%dx%d     Player spawns: %d     Villages: %d     Chests: %d     Countries: %d%s", E.w, E.h, ns, nv, nc,
            #E.pre, E.changed and "     (unsaved)" or ""), "GCapture.Small", 770, 46, TH.muted)
    end

    local function TB(x, y, w, text, fn, active, swatch, tip)
        local b = vgui.Create("DButton", bar)
        b:SetPos(x, y)
        b:SetSize(w, 26)
        b:SetText(text)
        if tip then b:SetTooltip(tip) end
        StyleButton(b)
        b.DoClick = fn
        local base = b.Paint
        b.Paint = function(s, bw, bh)
            base(s, bw, bh)
            if swatch then draw.RoundedBox(2, 6, bh / 2 - 6, 12, 12, swatch) end
            if active and active() then
                surface.SetDrawColor(TH.accent)
                surface.DrawOutlinedRect(0, 0, bw, bh, 2)
            end
        end
    end

    local side
    local x = 8
    for _, id in ipairs({ 5, 1, 2, 3, 4 }) do
        local B = GC.Biomes[id]
        TB(x, 6, 94, "  " .. B.name, function() E.tool = { biome = id } end,
            function() return E.tool.biome == id end, B.color)
        x = x + 98
    end
    x = x + 14
    TB(x, 6, 112, "Player Spawn", function() E.tool = { mark = "s" } end, function() return E.tool.mark == "s" end, nil, "Player start (optional)")
    TB(x + 116, 6, 84, "Village", function() E.tool = { mark = "v" } end, function() return E.tool.mark == "v" end, nil, "Neutral village (optional)")
    TB(x + 204, 6, 78, "Chest", function() E.tool = { mark = "c" } end, function() return E.tool.mark == "c" end, nil, "Chest (optional)")
    TB(x + 286, 6, 110, "Clear Marker", function() E.tool = { mark = "x", erase = true } end, function() return E.tool.erase end)

    local sl = vgui.Create("DPanel", bar)
    sl:SetPos(8, 38)
    sl:SetSize(250, 26)
    sl.Paint = function(s, w, h)
        draw.SimpleText("Brush: " .. E.brush, "GCapture.Small", 0, h / 2, TH.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local f_ = (E.brush - 1) / 31
        draw.RoundedBox(3, 70, h / 2 - 3, w - 76, 6, TH.hd)
        draw.RoundedBox(3, 70, h / 2 - 3, (w - 76) * f_, 6, TH.accent)
        draw.RoundedBox(4, 70 + (w - 76) * f_ - 5, h / 2 - 9, 10, 18, TH.text)
    end
    local function BrushFromCursor(s)
        local cx = s:CursorPos()
        E.brush = math.Clamp(math.Round((cx - 70) / (s:GetWide() - 76) * 31) + 1, 1, 32)
    end
    sl.OnMousePressed = function(s) s.drag = true s:MouseCapture(true) BrushFromCursor(s) end
    sl.OnCursorMoved = function(s) if s.drag then BrushFromCursor(s) end end
    sl.OnMouseReleased = function(s) s.drag = false s:MouseCapture(false) end

    TB(270, 38, 84, "Undo", Undo, nil, nil, "Ctrl+Z")
    TB(358, 38, 84, "Redo", Redo, nil, nil, "Ctrl+Y (or Ctrl+Shift+Z)")
    TB(446, 38, 100, "Save", Save)
    TB(550, 38, 80, "Fill", function() E.fill = not E.fill end, function() return E.fill end, nil, "Bucket: fills the connected area with the biome")
    TB(640, 38, 118, "Countries", function() side:SetVisible(not side:IsVisible()) end, function() return side:IsVisible() end, nil,
        "Preset countries: players take them first, then bots")
    local ex = vgui.Create("DButton", bar)
    ex:Dock(RIGHT)
    ex:SetWide(90)
    ex:DockMargin(0, 6, 8, 6)
    ex:SetText("Exit")
    StyleButton(ex)
    ex.DoClick = Exit

    side = vgui.Create("DPanel", f)
    side:Dock(RIGHT)
    side:SetWide(330)
    side:DockMargin(4, 0, 0, 0)
    side:SetVisible(false)
    side.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, TH.accentDim)
        draw.RoundedBox(6, 1, 1, w - 2, h - 2, TH.bg)
    end
    local hdr = vgui.Create("DLabel", side)
    hdr:Dock(TOP) hdr:SetTall(26) hdr:SetFont("GCapture.Stat") hdr:SetTextColor(TH.accent) hdr:SetText("  Preset Countries")
    local hint = vgui.Create("DLabel", side)
    hint:Dock(TOP) hint:DockMargin(8, 0, 8, 4)
    hint:SetFont("GCapture.Small") hint:SetTextColor(TH.muted) hint:SetWrap(true) hint:SetAutoStretchVertical(true)
    hint:SetText("Players get these first, then bots. Standard mode only.")
    local addBtn = vgui.Create("DButton", side)
    addBtn:Dock(TOP) addBtn:SetTall(30) addBtn:DockMargin(8, 0, 8, 6)
    addBtn:SetText("+  Add Country")
    StyleButton(addBtn)

    local edit = vgui.Create("DPanel", side)
    edit:Dock(BOTTOM) edit:SetTall(96) edit:DockMargin(6, 0, 6, 6)
    edit.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, TH.accentDim)
        draw.RoundedBox(6, 1, 1, w - 2, h - 2, TH.hd)
        local C = Country(E.edit)
        local idx = 0
        for k, c in ipairs(E.pre) do if c == C then idx = k end end
        draw.SimpleText("Editing: " .. (C and ((C.name or "") ~= "" and C.name or ("Country #" .. idx)) or "?"), "GCapture.Small", 8, 6, TH.accent)
    end
    local function EB(x, y, w, text, fn, active, tip)
        local b = vgui.Create("DButton", edit)
        b:SetPos(x, y) b:SetSize(w, 26) b:SetText(text)
        if tip then b:SetTooltip(tip) end
        StyleButton(b)
        b.DoClick = fn
        local base = b.Paint
        b.Paint = function(s, bw, bh)
            base(s, bw, bh)
            if active and active() then surface.SetDrawColor(TH.accent) surface.DrawOutlinedRect(0, 0, bw, bh, 2) end
        end
    end
    EB(8, 26, 96, "Paint", function() E.tool = { terr = "add" } E.fill = false end, function() return E.tool.terr == "add" end, "Add land to the territory")
    EB(110, 26, 96, "Erase", function() E.tool = { terr = "del" } E.fill = false end, function() return E.tool.terr == "del" end, "Remove cells from the territory")
    EB(212, 26, 106, "Set Spawn", function() E.tool = { terr = "spawn" } end, function() return E.tool.terr == "spawn" end, "Click a cell to place the capital")
    EB(8, 60, 310, "Done", function() E.edit = nil E.tool = { biome = 1 } end)

    side.OnRemove = function() if IsValid(E.colorWin) then E.colorWin:Remove() end end
    local list = vgui.Create("DScrollPanel", side)
    list:Dock(FILL) list:DockMargin(6, 0, 6, 6)
    StyleScroll(list)

    local counts, cntT = {}, 0
    side.Think = function(s)
        edit:SetVisible(Editing() and true or false)
        if CurTime() > cntT then
            cntT = CurTime() + 0.3
            counts = {}
            for _, id in pairs(E.terr) do counts[id] = (counts[id] or 0) + 1 end
        end
    end

    local Rebuild
    Rebuild = function()
        list:Clear()
        for k, C in ipairs(E.pre) do
            local row = list:Add("DPanel")
            row:Dock(TOP) row:SetTall(148) row:DockMargin(0, 0, 0, 6)
            row.Paint = function(s, w, h)
                local on = Editing() and E.edit == C.id
                draw.RoundedBox(4, 0, 0, w, h, on and TH.accent or TH.accentDim)
                draw.RoundedBox(4, 1, 1, w - 2, h - 2, TH.row)
                draw.RoundedBox(3, 8, 8, 14, 14, PCol(C.id))
                draw.SimpleText("Country #" .. k, "GCapture.Stat", 28, 4, TH.text)
                local ok = C.spawn ~= nil
                draw.SimpleText(string.format("Cells: %d     Spawn: %s", counts[C.id] or 0, ok and "set" or "NOT SET (ignored)"),
                    "GCapture.Small", 8, 28, ok and TH.muted or Color(255, 150, 90))
                draw.SimpleText("Name (optional)", "GCapture.Small", 8, 46, TH.muted)
                draw.SimpleText("Color", "GCapture.Small", 8, 96, TH.muted)
            end
            local te = vgui.Create("DTextEntry", row)
            te:SetValue(C.name or "")
            StyleEntry(te)
            te.OnChange = function(s)
                local t = s:GetValue()
                local cut = GC.CutName(t)
                if cut ~= t then s:SetValue(cut) s:SetCaretPos(#cut) end
                C.name = cut
                E.changed = true
            end
            local cb = vgui.Create("DButton", row)
            cb:SetText("")
            cb:SetTooltip("Overrides the player color")
            StyleButton(cb)
            local cbBase = cb.Paint
            cb.Paint = function(s, bw, bh)
                cbBase(s, bw, bh)
                local col = PCol(C.id)
                draw.RoundedBox(3, 3, 3, bw - 6, bh - 6, col)
                local dark = (col.r * 0.3 + col.g * 0.59 + col.b * 0.11) < 140
                draw.SimpleText(C.color and "Custom color" or "Auto color", "GCapture.Small", bw / 2, bh / 2,
                    dark and color_white or color_black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            cb.DoClick = function() PickColor(C) end
            local cr = vgui.Create("DButton", row)
            cr:SetText("Auto")
            cr:SetTooltip("Back to automatic color")
            StyleButton(cr)
            cr.DoClick = function()
                if C.color then C.color = nil E.changed = true end
                if IsValid(E.colorWin) then E.colorWin:Remove() end
            end
            local eb = vgui.Create("DButton", row)
            eb:SetText("Edit Territory")
            StyleButton(eb)
            eb.DoClick = function()
                if Editing() and E.edit == C.id then
                    E.edit = nil
                    E.tool = { biome = 1 }
                else
                    E.edit, E.tool, E.fill = C.id, { terr = "add" }, false
                    Note("Paint the territory first, then set the spawn.")
                end
            end
            eb.Think = function(s)
                local t = (Editing() and E.edit == C.id) and "Stop Editing" or "Edit Territory"
                if s:GetText() ~= t then s:SetText(t) end
            end
            local del = vgui.Create("DButton", row)
            del:SetText("Delete")
            StyleButton(del)
            del.DoClick = function()
                Derma_Query("Delete this country?", "Preset Countries", "Delete", function()
                    for cell, id in pairs(E.terr) do if id == C.id then E.terr[cell] = nil end end
                    for i, c in ipairs(E.pre) do if c == C then table.remove(E.pre, i) break end end
                    if E.edit == C.id then E.edit, E.tool = nil, { biome = 1 } end
                    E.undo, E.redo, E.changed = {}, {}, true
                    if IsValid(list) then Rebuild() end
                end, "Cancel")
            end
            row.PerformLayout = function(s, w, h)
                te:SetPos(8, 62) te:SetSize(w - 16, 24)
                local bw = math.floor((w - 24) * 0.65)
                cb:SetPos(52, 90) cb:SetSize(w - 52 - 8 - 56, 24)
                cr:SetPos(w - 8 - 52, 90) cr:SetSize(52, 24)
                eb:SetPos(8, 120) eb:SetSize(bw, 22)
                del:SetPos(16 + bw, 120) del:SetSize(w - 24 - bw, 22)
            end
        end
    end
    addBtn.DoClick = function()
        E.nid = E.nid + 1
        E.pre[#E.pre + 1] = { id = E.nid, name = "" }
        E.changed = true
        Rebuild()
        timer.Simple(0.05, function()
            if IsValid(list) then local vb = list:GetVBar() vb:SetScroll(vb.CanvasSize) end
        end)
    end
    Rebuild()

    local cv = vgui.Create("DPanel", f)
    cv:Dock(FILL)
    cv.zoom, cv.ox, cv.oy = 1, 0, 0

    function cv:Base() return math.min(self:GetWide() / E.w, self:GetTall() / E.h) end
    function cv:CS() return self:Base() * self.zoom end
    function cv:Clamp()
        local w, h = self:GetSize()
        local cs = self:CS()
        local sw, sh = cs * E.w, cs * E.h
        if sw <= w then self.ox = (w - sw) / 2 else self.ox = math.Clamp(self.ox, w - sw, 0) end
        if sh <= h then self.oy = (h - sh) / 2 else self.oy = math.Clamp(self.oy, h - sh, 0) end
    end
    function cv:CellAt(mx, my)
        local cs = self:CS()
        local cx, cy = math.floor((mx - self.ox) / cs), math.floor((my - self.oy) / cs)
        if cx < 0 or cy < 0 or cx >= E.w or cy >= E.h then return end
        return cy * E.w + cx + 1
    end
    function cv:OnMouseWheeled(d)
        local mx, my = self:CursorPos()
        local old = self:CS()
        self.zoom = math.Clamp(self.zoom * (d > 0 and 1.25 or 0.8), 1, math.max(1.5, 48 / self:Base()))
        local new = self:CS()
        self.ox = mx - (mx - self.ox) / old * new
        self.oy = my - (my - self.oy) / old * new
        self:Clamp()
    end
    function cv:OnMousePressed(code)
        local mx, my = self:CursorPos()
        if code == MOUSE_LEFT then
            local c = self:CellAt(mx, my)
            self.paint, self.last = true, nil
            Begin()
            self:MouseCapture(true)
            if c then Apply(nil, c) self.last = c end
        else
            self.drag = { mx = mx, my = my, ox = self.tox or self.ox, oy = self.toy or self.oy }
            self:MouseCapture(true)
        end
    end
    function cv:OnCursorMoved(mx, my)
        if self.paint then
            local c = self:CellAt(mx, my)
            if c and c ~= self.last and ((E.tool.biome and not E.fill) or E.tool.terr == "add" or E.tool.terr == "del") then
                Apply(self.last, c)
                self.last = c
            end
        elseif self.drag then
            self.ox = self.drag.ox + (mx - self.drag.mx)
            self.oy = self.drag.oy + (my - self.drag.my)
            self:Clamp()
        end
    end
    function cv:OnMouseReleased()
        if self.paint then self.paint = false End() end
        self.drag = nil
        self:MouseCapture(false)
    end

    function cv:Think()
        local ctrl = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
        local shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
        local z, y = input.IsKeyDown(KEY_Z), input.IsKeyDown(KEY_Y)
        if ctrl and z and not self.zd and not self.paint then
            self.zd = true
            if shift then Redo() else Undo() end
        elseif not z then
            self.zd = false
        end
        if ctrl and y and not self.yd and not self.paint then
            self.yd = true
            Redo()
        elseif not y then
            self.yd = false
        end
    end

    local mk = { s = { Color(255, 80, 80), mats[GC.B_CAPITAL] }, v = { Color(255, 215, 70), mats[GC.B_VILLAGE] },
        c = { Color(90, 210, 255), mats[GC.B_CHEST] } }
    function cv:Paint(w, h)
        surface.SetDrawColor(6, 10, 8, 255)
        surface.DrawRect(0, 0, w, h)
        self:Clamp()
        local cs, ox, oy = self:CS(), self.ox, self.oy
        local floor = math.floor
        local y0, y1 = math.max(0, floor(-oy / cs)), math.min(E.h - 1, floor((h - oy) / cs))
        local x0, x1 = math.max(0, floor(-ox / cs)), math.min(E.w - 1, floor((w - ox) / cs))

        for y = y0, y1 do
            local py = floor(oy + y * cs)
            local ph = math.max(1, floor(oy + (y + 1) * cs) - py)
            for _, r in ipairs(Runs(y)) do
                if r[1] + r[2] - 1 >= x0 and r[1] <= x1 then
                    local px = floor(ox + r[1] * cs)
                    local pw = math.max(1, floor(ox + (r[1] + r[2]) * cs) - px)
                    local c = GC.Biomes[r[3]].color
                    surface.SetDrawColor(c.r, c.g, c.b, 255)
                    surface.DrawRect(px, py, pw, ph)
                end
            end
        end

        if next(E.terr) then
            draw.NoTexture()
            local ed = Editing() and E.edit or nil
            local pc = {}
            for cell, id in pairs(E.terr) do
                local cx, cy = (cell - 1) % E.w, floor((cell - 1) / E.w)
                if cx >= x0 and cx <= x1 and cy >= y0 and cy <= y1 then
                    local col = pc[id]
                    if not col then col = PCol(id) pc[id] = col end
                    local px, py = floor(ox + cx * cs), floor(oy + cy * cs)
                    surface.SetDrawColor(col.r, col.g, col.b, ed == nil and 120 or (id == ed and 170 or 55))
                    surface.DrawRect(px, py, math.max(1, floor(ox + (cx + 1) * cs) - px), math.max(1, floor(oy + (cy + 1) * cs) - py))
                end
            end
        end

        if cs >= 10 then
            surface.SetDrawColor(0, 0, 0, 55)
            for gx = x0, x1 + 1 do surface.DrawRect(floor(ox + gx * cs), floor(oy + y0 * cs), 1, floor((y1 - y0 + 1) * cs)) end
            for gy = y0, y1 + 1 do surface.DrawRect(floor(ox + x0 * cs), floor(oy + gy * cs), floor((x1 - x0 + 1) * cs), 1) end
        end
        surface.SetDrawColor(TH.accent)
        surface.DrawOutlinedRect(floor(ox) - 1, floor(oy) - 1, floor(E.w * cs) + 2, floor(E.h * cs) + 2)

        for cell, m in pairs(E.mark) do
            local cx, cy = (cell - 1) % E.w, floor((cell - 1) / E.w)
            if cx >= x0 and cx <= x1 and cy >= y0 and cy <= y1 then
                local info = mk[m]
                local sz = math.max(cs, 5)
                local px, py = ox + (cx + 0.5) * cs - sz / 2, oy + (cy + 0.5) * cs - sz / 2
                surface.SetDrawColor(0, 0, 0, 230)
                surface.DrawRect(px - 1, py - 1, sz + 2, sz + 2)
                surface.SetDrawColor(info[1])
                surface.DrawRect(px, py, sz, sz)
                if cs >= 10 and info[2] then
                    surface.SetDrawColor(255, 255, 255, 255)
                    surface.SetMaterial(info[2])
                    surface.DrawTexturedRect(px, py, sz, sz)
                end
            end
        end

        draw.NoTexture()
        for k, C in ipairs(E.pre) do
            if C.spawn then
                local cx, cy = (C.spawn - 1) % E.w, floor((C.spawn - 1) / E.w)
                if cx >= x0 and cx <= x1 and cy >= y0 and cy <= y1 then
                    local col = PCol(C.id)
                    local sz = math.max(cs, 6)
                    local px, py = ox + (cx + 0.5) * cs - sz / 2, oy + (cy + 0.5) * cs - sz / 2
                    surface.SetDrawColor(0, 0, 0, 230)
                    surface.DrawRect(px - 2, py - 2, sz + 4, sz + 4)
                    surface.SetDrawColor(col.r, col.g, col.b, 255)
                    surface.DrawRect(px, py, sz, sz)
                    if cs >= 10 then
                        surface.SetDrawColor(255, 255, 255, 255)
                        surface.SetMaterial(mats[GC.B_CAPITAL])
                        surface.DrawTexturedRect(px, py, sz, sz)
                    end
                    draw.SimpleTextOutlined((C.name or "") ~= "" and C.name or ("#" .. k), "GCapture.Small", px + sz / 2, py - 16,
                        color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
                end
            end
        end

        local mx, my = self:CursorPos()
        local hc = self:IsHovered() and self:CellAt(mx, my)
        if hc then
            local cx, cy = (hc - 1) % E.w, floor((hc - 1) / E.w)
            local n = ((E.tool.biome and not E.fill) or E.tool.terr == "add" or E.tool.terr == "del") and E.brush or 1
            local sz = n * cs
            surface.SetDrawColor(255, 255, 255, 230)
            surface.DrawOutlinedRect(floor(ox + (cx + 0.5) * cs - sz / 2), floor(oy + (cy + 0.5) * cs - sz / 2), math.max(2, floor(sz)), math.max(2, floor(sz)))
            draw.SimpleTextOutlined(string.format("%d, %d", cx, cy), "GCapture.Small", 8, h - 22, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
        end
        draw.SimpleTextOutlined("LMB paint   RMB / MMB drag: pan   Wheel: zoom   Ctrl+Z / Ctrl+Y: undo / redo", "GCapture.Small",
            w - 8, h - 22, Color(210, 230, 215), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, color_black)
        if E.msg and CurTime() - E.msgT < 4 then
            draw.SimpleTextOutlined(E.msg, "GCapture.Stat", w / 2, 10, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
        end
    end
end

function GC.OpenMapMakerSetup()
    if IsValid(GC.mmSetup) then GC.mmSetup:MoveToFront() return end
    local f = vgui.Create("DFrame")
    f:SetTitle("Map Maker - New Map")
    f:SetSize(380, 320)
    f:Center()
    f:MakePopup()
    StyleFrame(f)
    GC.mmSetup = f

    local function Field(y, label, def, numeric)
        local l = vgui.Create("DLabel", f)
        l:SetPos(16, y)
        l:SetFont("GCapture.Small")
        l:SetTextColor(TH.muted)
        l:SetText(label)
        l:SizeToContents()
        local te = vgui.Create("DTextEntry", f)
        te:SetPos(16, y + 18)
        te:SetSize(348, 26)
        te:SetValue(def)
        StyleEntry(te)
        if numeric then te:SetNumeric(true) end
        return te
    end
    local tw = Field(36, "Width (4-512)", "64", true)
    local th = Field(90, "Height (4-512)", "64", true)
    local tn = Field(144, "Map name", "My Map")
    local tf = Field(198, "File name (letters, digits, _ and -, no spaces)", "my_map")
    tn.OnChange = function(s)
        local t = s:GetValue()
        if #t > 40 then s:SetValue(string.sub(t, 1, 40)) end
    end
    tf.OnChange = function(s)
        local t = s:GetValue()
        local c = string.sub(string.gsub(t, "[^%w_%-]", ""), 1, 40)
        if c ~= t then
            s:SetValue(c)
            s:SetCaretPos(#c)
        end
    end

    local go = vgui.Create("DButton", f)
    go:SetPos(16, 262)
    go:SetSize(348, 34)
    go:SetText("Create")
    StyleButton(go)
    go.DoClick = function()
        local w, h = tonumber(tw:GetValue()), tonumber(th:GetValue())
        if not w or not h then return Derma_Message("Enter width and height.", "Map Maker", "OK") end
        w, h = math.Clamp(math.floor(w), 4, 512), math.Clamp(math.floor(h), 4, 512)
        local name = string.Trim(tn:GetValue())
        if name == "" then name = "Unnamed" end
        local fname = string.gsub(tf:GetValue(), "[^%w_%-]", "")
        if fname == "" then fname = string.gsub(string.lower(name), "[^%w_%-]", "") end
        if fname == "" then return Derma_Message("Enter a file name.", "Map Maker", "OK") end

        local function Begin()
            local biome = {}
            for i = 1, w * h do biome[i] = 5 end
            if IsValid(f) then f:Remove() end
            GC.OpenMapEditor({ w = w, h = h, name = name, fname = fname, biome = biome, mark = {} })
        end
        if file.Exists(MAP_DIR .. fname .. ".txt", "DATA") then
            Derma_Query("File name already exists. Overwrite on save?", "Map Maker", "Continue", Begin, "Cancel")
        else
            Begin()
        end
    end
end

function GC.OpenMapPicker()
    if IsValid(GC.mapPicker) then GC.mapPicker:MoveToFront() return end
    local f = vgui.Create("DFrame")
    f:SetTitle("Choose Map")
    f:SetSize(560, 440)
    f:Center()
    f:MakePopup()
    StyleFrame(f)
    GC.mapPicker = f

    local sel
    local bottom = vgui.Create("DPanel", f)
    bottom:Dock(BOTTOM)
    bottom:SetTall(40)
    bottom:DockMargin(6, 0, 6, 6)
    bottom.Paint = nil
    local function Btn(text, side, wide, fn)
        local b = vgui.Create("DButton", bottom)
        b:Dock(side)
        b:SetWide(wide)
        b:DockMargin(side == RIGHT and 6 or 0, 0, side == LEFT and 6 or 0, 0)
        b:SetText(text)
        StyleButton(b)
        b.DoClick = fn
        return b
    end
    local scroll = vgui.Create("DScrollPanel", f)
    scroll:Dock(FILL)
    scroll:DockMargin(6, 6, 6, 6)
    StyleScroll(scroll)

    local bSel, bEdit, bDel, bRen
    local function Upd()
        bSel:SetEnabled(sel ~= nil and GC.isHost)
        bEdit:SetEnabled(sel ~= nil and sel ~= "")
        bDel:SetEnabled(sel ~= nil and sel ~= "")
        bRen:SetEnabled(sel ~= nil and sel ~= "")
    end
    local Refresh
    bSel = Btn("Select", LEFT, 100, function()
        if sel == nil then return end
        GC.UploadMap(sel ~= "" and sel or nil)
        f:Remove()
    end)
    bSel:SetTooltip("Host only")
    bEdit = Btn("Edit", LEFT, 80, function()
        local d = sel and sel ~= "" and MapRead(sel)
        if not d then return Derma_Message("Corrupted map file.", "Map", "OK") end
        local biome = {}
        for i = 1, d.w * d.h do biome[i] = math.Clamp(string.byte(d.b, i) - 48, 1, 5) end
        local mark = {}
        for _, c in ipairs(d.s or {}) do mark[c] = "s" end
        for _, c in ipairs(d.v or {}) do mark[c] = "v" end
        for _, c in ipairs(d.c or {}) do mark[c] = "c" end
        local pre, terr, nid = {}, {}, 0
        for _, C in ipairs(type(d.p) == "table" and d.p or {}) do
            nid = nid + 1
            local sp = tonumber(C.s)
            local col
            if type(C.k) == "table" and tonumber(C.k[1]) and tonumber(C.k[2]) and tonumber(C.k[3]) then
                col = Color(math.Clamp(math.floor(C.k[1]), 0, 255), math.Clamp(math.floor(C.k[2]), 0, 255), math.Clamp(math.floor(C.k[3]), 0, 255))
            end
            pre[#pre + 1] = { id = nid, name = tostring(C.n or ""), spawn = (sp and sp > 0) and sp or nil, color = col }
            for _, c in ipairs(type(C.c) == "table" and C.c or {}) do
                if type(c) == "number" and c >= 1 and c <= d.w * d.h then terr[c] = nid end
            end
        end
        f:Remove()
        GC.OpenMapEditor({ w = d.w, h = d.h, name = d.name, fname = string.StripExtension(sel), biome = biome, mark = mark,
            pre = pre, terr = terr, nid = nid })
    end)
    bDel = Btn("Delete", LEFT, 80, function()
        local fn = sel
        Derma_Query("Delete this map?", "Delete Map", "Delete", function()
            file.Delete(MAP_DIR .. fn)
            Refresh()
        end, "Cancel")
    end)
    bRen = Btn("Rename", LEFT, 80, function()
        if sel and sel ~= "" then GC.OpenMapRename(sel, function() Refresh() end) end
    end)
    Btn("Close", RIGHT, 80, function() f:Remove() end)

    local function Row(key, title, sub, flag)
        local row = scroll:Add("DButton")
        row:Dock(TOP)
        row:SetTall(46)
        row:DockMargin(0, 0, 0, 4)
        row:SetText("")
        row.hv = 0
        row.Paint = function(s, w, h)
            s.hv = Lerp(math.min(1, FrameTime() * 14), s.hv, s:IsHovered() and 1 or 0)
            local on = sel == key
            draw.RoundedBox(4, 0, 0, w, h, on and TH.accent or LerpColor(s.hv, TH.hd, TH.accentDim))
            draw.RoundedBox(4, 1, 1, w - 2, h - 2, on and TH.rowHover or LerpColor(s.hv, TH.row, TH.rowHover))
            draw.SimpleText(title, "GCapture.Stat", 10, 4, TH.text)
            draw.SimpleText(sub, "GCapture.Small", 10, 26, TH.muted)
            if flag then
                surface.SetFont("GCapture.Small")
                local tw = surface.GetTextSize(flag)
                draw.RoundedBox(4, w - tw - 22, 8, tw + 14, 20, Color(120, 80, 10))
                draw.SimpleText(flag, "GCapture.Small", w - tw - 15, 11, Color(255, 210, 90))
            end
        end
        if flag then row:SetTooltip("Has preset countries") end
        row.DoClick = function() sel = key Upd() end
        row.DoDoubleClick = function() sel = key Upd() if GC.isHost then bSel:DoClick() end end
    end

    Refresh = function()
        scroll:Clear()
        sel = nil
        Row("", "Random map (generated)", "Size and seed from the lobby")
        for _, fn in ipairs(file.Find(MAP_DIR .. "*.txt", "DATA", "datedesc") or {}) do
            local w, h, name, np = MapHeader(fn)
            if w then
                Row(fn, name, string.format("%dx%d     %s     %s", w, h, fn,
                    os.date("%Y-%m-%d %H:%M", file.Time(MAP_DIR .. fn, "DATA"))),
                    (np or 0) > 0 and ("Preset countries: " .. np) or nil)
            end
        end
        Upd()
    end
    Refresh()
end

local function SendColor(c)
    net.Start("GCapture_Color")
    net.WriteBool(c ~= nil)
    if c then net.WriteUInt(c.r, 8) net.WriteUInt(c.g, 8) net.WriteUInt(c.b, 8) end
    net.SendToServer()
end

local function MyLobbyColor()
    for k, p in ipairs(GC.lobbyList or {}) do
        if p == LocalPlayer() then return (GC.lobbyColors or {})[k] end
    end
end

local DNAMES = { [0] = "Easy", [1] = "Normal", [2] = "Hard", [3] = "Emperor", [4] = "Randomized" }
local DTIPS = {
    [0] = "Slow and passive. No navy or airbase. Recommended for begginers",
    [1] = "Uses Navy.",
    [2] = "Fast. Uses airbases.",
    [3] = "Impossible to beat.",
    [4] = "Random difficulty for each bot.",
}

function GC.SetOpt(k, v)
    local o = GC.lobbyOpts or {}
    GC.lobbyOpts = o
    o[k] = v
    net.Start("GCapture_Opts")
    net.WriteUInt(o.mode or 0, 2)
    net.WriteBool(o.nofog or false)
    net.WriteUInt(o.bots or 0, 6)
    net.WriteUInt(o.diff or 1, 3)
    net.WriteUInt(o.btype or 0, 2)
    net.WriteUInt(o.size or 1, 2)
    net.WriteBool(o.observe or false)
    net.WriteString(o.seed or "")
    net.WriteBool(o.noevents or false)
    net.WriteBool(o.emperor or false)
    for _, k in ipairs(GC.OptFlags) do net.WriteBool(o[k] or false) end
    net.SendToServer()
end

function GC.SendName(t)
    net.Start("GCapture_Name")
    net.WriteString(string.Trim(t or ""))
    net.SendToServer()
end

GC.optWins = GC.optWins or {}
function GC.CloseOptWins()
    for _, f in pairs(GC.optWins) do if IsValid(f) then f:Remove() end end
    GC.optWins = {}
end
function GC.SyncOptWins()
    for _, f in pairs(GC.optWins) do if IsValid(f) and f.Sync then f:Sync() end end
end
local function OptWin(id, title, w, h)
    if IsValid(GC.optWins[id]) then GC.optWins[id]:MoveToFront() return end
    local f = vgui.Create("DFrame")
    f:SetTitle(title)
    f:SetSize(w, h)
    f:Center()
    f:MakePopup()
    StyleFrame(f)
    GC.optWins[id] = f
    return f
end
local function Lab(parent, text, x, y)
    local l = vgui.Create("DLabel", parent)
    l:SetPos(x, y)
    l:SetFont("GCapture.Small")
    l:SetTextColor(TH.muted)
    l:SetText(text)
    l:SizeToContents()
    return l
end
local function LCheck(parent, y, text, get, set, anyone, x, w)
    local b = vgui.Create("DButton", parent)
    b:SetPos(x or 14, y)
    b:SetSize(w or (parent:GetWide() - 28), 26)
    b:SetText("")
    b.hv = 0
    b.Paint = function(s, w, h)
        s.hv = Lerp(math.min(1, FrameTime() * 14), s.hv, s:IsHovered() and 1 or 0)
        local can = anyone or GC.isHost
        if s.hv > 0.01 then draw.RoundedBox(4, 0, 0, w, h, Color(TH.row.r, TH.row.g, TH.row.b, 255 * s.hv)) end
        draw.RoundedBox(3, 4, h / 2 - 8, 16, 16, can and TH.accentDim or TH.hd)
        draw.RoundedBox(3, 5, h / 2 - 7, 14, 14, TH.hd)
        if get() then draw.RoundedBox(2, 8, h / 2 - 4, 8, 8, can and TH.accent or TH.muted) end
        draw.SimpleText(text, "GCapture.Small", 30, h / 2, can and TH.text or TH.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    b.DoClick = function() if anyone or GC.isHost then set(not get()) end end
    return b
end
local function Opts() return GC.lobbyOpts or {} end

local MODE_NAMES = { [0] = "Standard Mode", [1] = "Rush Mode", [2] = "Deploy Mode" }
local MODE_TIPS = {
    [0] = "Random start positions.",
    [1] = "Land is split evenly. 1000 starting coins.",
    [2] = "This mode lets you choose your starting position.",
}

local function OpenGameOptions()
    local f = OptWin("opts", "Game Options", 520, 376)
    if not f then return end
    Lab(f, "Game mode", 14, 34)
    for m = 0, 2 do
        local b = vgui.Create("DButton", f)
        b:SetPos(14 + m * 166, 52)
        b:SetSize(160, 28)
        b:SetText(MODE_NAMES[m])
        b:SetTooltip(MODE_TIPS[m])
        StyleButton(b)
        local base = b.Paint
        b.Paint = function(s, w, h)
            base(s, w, h)
            if (Opts().mode or 0) == m then surface.SetDrawColor(TH.accent) surface.DrawOutlinedRect(0, 0, w, h, 2) end
        end
        b.DoClick = function() if GC.isHost then GC.SetOpt("mode", m) end end
    end

    local function Flag(key, text, tip, x, y, w)
        local c = LCheck(f, y, text, function() return Opts()[key] end, function(v) GC.SetOpt(key, v) end, nil, x, w)
        c:SetTooltip(tip)
        return c
    end
    local warn = vgui.Create("DLabel", f)
    warn:SetPos(14, 342)
    warn:SetFont("GCapture.Small")
    warn:SetTextColor(TH.muted)
    warn:SetText("")
    warn:SetSize(492, 20)
    warn.Think = function(s)
        if not GC.isHost then s:SetText("Host only.") s:SetTextColor(TH.muted)
        elseif (s.warnUntil or 0) > CurTime() then s:SetText("Can't leave only ocean.") s:SetTextColor(Color(255, 150, 120))
        else s:SetText("") end
    end

    Lab(f, "Rules", 14, 92)
    local y = 112
    Flag("nofog", "Disable Fog of War", "Everyone sees the whole map.", 14, y, 244) y = y + 28
    Flag("noevents", "Disable Events", "No random events.", 14, y, 244) y = y + 28
    Flag("observe", "Host Observes", "Host watches, doesn't play.", 14, y, 244) y = y + 28
    Flag("nochests", "Disable Chests", "No chests on the map.", 14, y, 244) y = y + 28
    Flag("nospirits", "Disable National Spirit Choice", "Spirits are given at random.", 14, y, 244) y = y + 28
    Flag("novillages", "Disable Random Villages", "No random neutral villages.", 14, y, 244) y = y + 28
    Flag("nonight", "Disable Night Debuff", "No attack penalty at night.", 14, y, 244) y = y + 28
    Flag("nopresets", "Disable Preset Countries", "Ignore preset countries on custom maps.", 14, y, 244)

    Lab(f, "Terrain (random maps)", 270, 92)
    local LAND = { "noplains", "noforest", "nodesert", "notundra" }
    local function Terrain(key, text, y2)
        local isLand = key ~= "noocean"
        local c = LCheck(f, y2, text, function() return Opts()[key] end, function(v)
            if v and isLand then
                local others = 0
                for _, k in ipairs(LAND) do if k ~= key and Opts()[k] then others = others + 1 end end
                if others >= #LAND - 1 then
                    warn.warnUntil = CurTime() + 3
                    surface.PlaySound("buttons/button10.wav")
                    return
                end
            end
            GC.SetOpt(key, v)
        end, nil, 270, 236)
        c:SetTooltip("No " .. string.lower(string.sub(text, 9)) .. " on random maps.")
    end
    Terrain("noplains", "Disable Plains", 112)
    Terrain("noforest", "Disable Forest", 140)
    Terrain("notundra", "Disable Tundra", 168)
    Terrain("nodesert", "Disable Desert", 196)
    Terrain("noocean", "Disable Ocean", 224)
end

local function OpenBots()
    local f = OptWin("bots", "Bots", 420, 284)
    if not f then return end
    local TX, TW = 90, 290
    local sl = vgui.Create("DPanel", f)
    sl:SetPos(14, 38)
    sl:SetSize(392, 30)
    sl.Paint = function(s, w, h)
        local v = s.drag and s.val or (Opts().bots or 0)
        local en, fr = GC.isHost, v / GC.MaxBots
        draw.SimpleText("Bots: " .. v, "GCapture.Stat", 0, h / 2, en and TH.text or TH.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.RoundedBox(3, TX, h / 2 - 3, TW, 6, TH.hd)
        draw.RoundedBox(3, TX, h / 2 - 3, TW * fr, 6, en and TH.accent or TH.accentDim)
        draw.RoundedBox(4, TX + TW * fr - 5, h / 2 - 9, 10, 18, en and TH.text or TH.muted)
    end
    local function Set(s)
        local x = s:CursorPos()
        local v = math.Clamp(math.Round((x - TX) / TW * GC.MaxBots), 0, GC.MaxBots)
        if v ~= s.val then s.val = v GC.SetOpt("bots", v) end
    end
    sl.OnMousePressed = function(s)
        if not GC.isHost then return end
        s.drag, s.val = true, Opts().bots or 0
        s:MouseCapture(true)
        Set(s)
    end
    sl.OnCursorMoved = function(s) if s.drag then Set(s) end end
    sl.OnMouseReleased = function(s) s.drag = false s:MouseCapture(false) end
    Lab(f, "Difficulty", 14, 84)
    for d = 0, 4 do
        local b = vgui.Create("DButton", f)
        b:SetPos(14 + d * 78, 104)
        b:SetSize(72, 28)
        b:SetText(DNAMES[d])
        StyleButton(b)
        local base = b.Paint
        b.Paint = function(s, w, h)
            base(s, w, h)
            if (Opts().diff or 1) == d then surface.SetDrawColor(TH.accent) surface.DrawOutlinedRect(0, 0, w, h, 2) end
        end
        b.DoClick = function() if GC.isHost then GC.SetOpt("diff", d) end end
    end

    local emp = LCheck(f, 136, "Allow Emperor", function() return Opts().emperor end, function(v) GC.SetOpt("emperor", v) end)
    emp:SetTooltip("Bots can roll Emperor")
    emp:SetVisible((Opts().diff or 1) == 4)
    local tip = vgui.Create("DLabel", f)
    tip:SetPos(14, 170)
    tip:SetSize(392, 36)
    tip:SetFont("GCapture.Small")
    tip:SetTextColor(TH.text)
    tip:SetWrap(true)
    tip:SetContentAlignment(7)
    tip.Think = function(s)
        s:SetText(DTIPS[Opts().diff or 1] or "")
        local want = (Opts().diff or 1) == 4
        if IsValid(emp) and emp:IsVisible() ~= want then emp:SetVisible(want) end
    end

    Lab(f, "Bot Type", 14, 214)
    local TYPES = {
        [0] = { "Random", "Random type for each bot." },
        [1] = { "Aggressive", "All bots are aggressive." },
        [2] = { "Defensive", "All bots are defensive." },
        [3] = { "Dynamic", "Every 30 s a bot has a 50% chance to switch type." },
    }
    for t = 0, 3 do
        local b = vgui.Create("DButton", f)
        b:SetPos(14 + t * 98, 234)
        b:SetSize(92, 28)
        b:SetText(TYPES[t][1])
        b:SetTooltip(TYPES[t][2])
        StyleButton(b)
        local base = b.Paint
        b.Paint = function(s, w, h)
            base(s, w, h)
            if (Opts().btype or 0) == t then surface.SetDrawColor(TH.accent) surface.DrawOutlinedRect(0, 0, w, h, 2) end
        end
        b.DoClick = function() if GC.isHost then GC.SetOpt("btype", t) end end
    end
end

local function OpenMap()
    local f = OptWin("map", "Map", 420, 270)
    if not f then return end
    f.tab = (Opts().map or "") ~= "" and 2 or 1
    local function Tab(x, text, id)
        local b = vgui.Create("DButton", f)
        b:SetPos(x, 34)
        b:SetSize(192, 28)
        b:SetText(text)
        StyleButton(b)
        local base = b.Paint
        b.Paint = function(s, w, h)
            base(s, w, h)
            if f.tab == id then surface.SetDrawColor(TH.accent) surface.DrawOutlinedRect(0, 0, w, h, 2) end
        end
        b.DoClick = function()
            if not GC.isHost then return end
            f.tab = id
            if id == 1 and (Opts().map or "") ~= "" then
                f.wantRandom = true
                GC.UploadMap(nil)
            elseif id == 2 and (Opts().map or "") == "" then
                f.wantCustom = true
                GC.OpenMapPicker()
            end
            f:Sync()
        end
    end
    Tab(14, "Random map", 1)
    Tab(214, "Custom map", 2)
    local p1 = vgui.Create("DPanel", f)
    p1:SetPos(0, 72)
    p1:SetSize(420, 190)
    p1.Paint = nil
    Lab(p1, "Seed", 14, 2)
    local te = vgui.Create("DTextEntry", p1)
    te:SetPos(14, 22)
    te:SetSize(290, 26)
    te:SetTooltip("Same seed, size and players = same map.")
    StyleEntry(te)
    GC.seedTe = te
    local function SendSeed() if GC.isHost then GC.SetOpt("seed", string.Trim(te:GetValue())) end end
    te.OnChange = function(s)
        local t = s:GetValue()
        if #t > 24 then t = string.sub(t, 1, 24) s:SetValue(t) s:SetCaretPos(#t) end
    end
    te.OnEnter = SendSeed
    local oldLose = te.OnLoseFocus
    te.OnLoseFocus = function(s) if oldLose then oldLose(s) end SendSeed() end
    local rnd = vgui.Create("DButton", p1)
    rnd:SetPos(312, 22)
    rnd:SetSize(94, 26)
    rnd:SetText("Random")
    StyleButton(rnd)
    rnd.DoClick = function() if GC.isHost then te:SetValue("") GC.SetOpt("seed", "") end end
    Lab(p1, "Map size", 14, 62)
    for sI = 0, 3 do
        local b = vgui.Create("DButton", p1)
        b:SetPos(14 + sI * 98, 82)
        b:SetSize(94, 28)
        b:SetText(GC.SizeList[sI] .. "x" .. GC.SizeList[sI])
        StyleButton(b)
        local base = b.Paint
        b.Paint = function(s, w, h)
            base(s, w, h)
            if (Opts().size or 1) == sI then surface.SetDrawColor(TH.accent) surface.DrawOutlinedRect(0, 0, w, h, 2) end
        end
        b.DoClick = function() if GC.isHost then GC.SetOpt("size", sI) end end
    end
    Lab(p1, "=).", 14, 124)
    local p2 = vgui.Create("DPanel", f)
    p2:SetPos(0, 72)
    p2:SetSize(420, 190)
    p2.Paint = nil
    local ch = vgui.Create("DButton", p2)
    ch:SetPos(14, 4)
    ch:SetSize(392, 30)
    ch:SetText("Choose Map")
    StyleButton(ch)
    ch.DoClick = function() GC.OpenMapPicker() end
    local cur = vgui.Create("DLabel", p2)
    cur:SetPos(14, 46)
    cur:SetSize(392, 40)
    cur:SetFont("GCapture.Small")
    cur:SetTextColor(TH.text)
    cur:SetWrap(true)
    cur:SetContentAlignment(7)
    cur.Think = function(s)
        local m = Opts().map or ""
        s:SetText(m ~= "" and ("Current map: " .. m) or "No map selected.")
    end
    Lab(p2, "Size and seed are ignored for custom maps.", 14, 96)
    function f:Sync()
        local currentMap = (Opts().map or "") ~= ""
        if self.wantRandom then
            self.tab = 1
            if not currentMap then self.wantRandom = nil end
        elseif currentMap then
            self.tab = 2
            self.wantCustom = nil
        elseif not GC.isHost then
            self.tab = 1
        elseif self.wantCustom then
            self.tab = 2
        end
        p1:SetVisible(self.tab == 1)
        p2:SetVisible(self.tab == 2)
        if not te:HasFocus() then te:SetValue(Opts().seed or "") end
        ch:SetEnabled(GC.isHost)
    end
    f:Sync()
end

local function OpenPlayer()
    local f = OptWin("player", "Player", 420, 360)
    if not f then return end
    Lab(f, "Country name", 14, 32)
    local te = vgui.Create("DTextEntry", f)
    te:SetPos(14, 50)
    te:SetSize(392, 28)
    te:SetValue(GC.DefaultName(LocalPlayer()))
    StyleEntry(te)
    GC.nameTe = te
    te.OnChange = function(s)
        local t = s:GetValue()
        local cut = GC.CutName(t)
        if cut ~= t then s:SetValue(cut) s:SetCaretPos(#cut) end
    end
    te.OnEnter = function(s) GC.SendName(s:GetValue()) end
    local oldLose = te.OnLoseFocus
    te.OnLoseFocus = function(s) if oldLose then oldLose(s) end GC.SendName(s:GetValue()) end
    f.OnRemove = function() if IsValid(te) then GC.SendName(te:GetValue()) end end
    Lab(f, "Your color", 14, 90)
    local mixer = vgui.Create("DColorMixer", f)
    mixer:SetPos(14, 108)
    mixer:SetSize(392, 140)
    mixer:SetPalette(false)
    mixer:SetAlphaBar(false)
    mixer:SetWangs(true)
    mixer:SetColor(Color(60, 200, 90))
    mixer.ValueChanged = function(s)
        if f.updating then return end
        timer.Create("GCapture_ColorSend", 0.3, 1, function()
            if not IsValid(s) then return end
            local c = s:GetColor()
            SendColor(Color(c.r, c.g, c.b))
        end)
    end
    local rnd = vgui.Create("DButton", f)
    rnd:SetPos(14, 254)
    rnd:SetSize(392, 26)
    rnd:SetText("Random color")
    StyleButton(rnd)
    rnd.DoClick = function() SendColor(nil) end
    LCheck(f, 296, "Record Demo",
        function() return GetConVar("cl_gc_record"):GetBool() end,
        function(v) RunConsoleCommand("cl_gc_record", v and "1" or "0") GC.SendRec(v) end, true)
    function f:Sync()
        if not te:HasFocus() then
            for k, ply in ipairs(GC.lobbyList or {}) do
                if ply == LocalPlayer() and GC.lobbyNames[k] then te:SetValue(GC.lobbyNames[k]) end
            end
        end
        local mc = MyLobbyColor()
        if mc and not mixer:IsChildHovered() then
            self.updating = true
            mixer:SetColor(Color(mc.r, mc.g, mc.b))
            self.updating = false
        end
    end
    f:Sync()
end

GC.OnlineURL = "gcapture-online.vercel.app"

GC.OnlineMaxBytes = 4000000

do
    local OWN_FILE = "gcapture/online_owned.json"
    local PAGE = 20
    local RED = Color(255, 120, 110)
    local GOLD = Color(255, 210, 90)
    local BROWN = Color(120, 80, 10)

    local owned = {}
    do
        local raw = file.Read(OWN_FILE, "DATA")
        local t = raw and util.JSONToTable(raw)
        if type(t) == "table" then owned = t end
    end
    local function SaveOwned()
        file.CreateDir("gcapture")
        file.Write(OWN_FILE, util.TableToJSON(owned) or "{}")
    end

    local function UrlEnc(s)
        return (string.gsub(tostring(s), "[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end))
    end

    local function BaseURL()
        local u = GC.OnlineURL
        if type(u) ~= "string" or u == "" or string.find(u, "YOUR-PROJECT", 1, true) then return nil end
        if not string.find(u, "^https?://") then u = "https://" .. u end
        return (string.gsub(u, "/+$", ""))
    end

    local function Http(method, path, query, body, cb)
        local base = BaseURL()
        if not base then
            return cb(0, nil, "Online server is not set up: put your Vercel URL into GC.OnlineURL (client.lua).")
        end
        local url = base .. path
        if query then
            local parts = {}
            for k, v in pairs(query) do parts[#parts + 1] = k .. "=" .. UrlEnc(v) end
            table.sort(parts)
            url = url .. "?" .. table.concat(parts, "&")
        end
        local fin = false
        local function Done(c, r, e)
            if fin then return end
            fin = true
            cb(c, r, e)
        end
        local sent = HTTP({
            url = url,
            method = method,
            body = body,
            type = body and "application/json" or nil,
            headers = { Accept = "application/json, text/plain" },
            timeout = 30,
            success = function(code, resp) Done(code, resp, nil) end,
            failed = function(reason) Done(0, nil, "Can't reach the server (" .. tostring(reason) .. ").") end,
        })
        if not sent then Done(0, nil, "The game blocked the HTTP request.") end
    end

    local function ErrText(code, resp, err)
        if err then return err end
        local d = resp and util.JSONToTable(resp)
        if type(d) == "table" and d.error then return tostring(d.error) end
        return "Server error (HTTP " .. tostring(code) .. ")."
    end

    local function Json(method, path, query, tbl, cb)
        local body = tbl and util.TableToJSON(tbl)
        if tbl and not body then return cb(false, nil, "Can't encode the request (bad characters in the text?).") end
        Http(method, path, query, body, function(code, resp, err)
            local d = resp and util.JSONToTable(resp)
            if code == 200 and type(d) == "table" and d.ok then return cb(true, d, nil) end
            cb(false, type(d) == "table" and d or nil, ErrText(code, resp, err))
        end)
    end

    local function Cut(s, n)
        s = string.gsub(tostring(s or ""), "%c", " ")
        local len = utf8.len(s)
        if not len then return string.sub(s, 1, n) end
        if len > n then s = string.sub(s, 1, utf8.offset(s, n + 1) - 1) end
        return s
    end

    local function Fit(txt, font, maxw)
        txt = tostring(txt or "")
        surface.SetFont(font)
        if surface.GetTextSize(txt) <= maxw then return txt end
        local n = utf8.len(txt) or #txt
        while n > 1 do
            n = n - 1
            local off = utf8.offset(txt, n + 1)
            local s = string.sub(txt, 1, (off or (#txt + 1)) - 1) .. "..."
            if surface.GetTextSize(s) <= maxw then return s end
        end
        return "..."
    end

    local function Ago(ts)
        ts = tonumber(ts) or 0
        local d = os.time() - ts
        if d < 60 then return "just now" end
        if d < 3600 then return math.floor(d / 60) .. " min ago" end
        if d < 86400 then return math.floor(d / 3600) .. " h ago" end
        if d < 86400 * 60 then return math.floor(d / 86400) .. " d ago" end
        return os.date("%Y-%m-%d", ts)
    end

    local function SizeText(n)
        n = tonumber(n) or 0
        if n < 1048576 then return string.format("%d KB", math.max(1, math.floor(n / 1024 + 0.5))) end
        return string.format("%.1f MB", n / 1048576)
    end

    local function SafeId(id) return (string.gsub(tostring(id or ""), "[^%w_%-]", "")) end
    local function Dir(kind) return kind == "map" and MAP_DIR or DEMO_DIR end
    local function LocalName(id) return "online_" .. SafeId(id) .. ".txt" end
    local function Saved(kind, id) return file.Exists(Dir(kind) .. LocalName(id), "DATA") end

    local function Badge(text, rx, y, bg, fg)
        surface.SetFont("GCapture.Small")
        local tw = surface.GetTextSize(text)
        draw.RoundedBox(4, rx - tw - 14, y, tw + 14, 20, bg)
        draw.SimpleText(text, "GCapture.Small", rx - tw - 7, y + 3, fg)
        return rx - tw - 20
    end

    function GC.OnlineDownload(kind, id, done)
        id = SafeId(id)
        if id == "" then return done(false, "Bad id.") end
        Http("GET", "/api/download", { kind = kind, id = id }, nil, function(code, resp, err)
            if code ~= 200 or type(resp) ~= "string" then return done(false, ErrText(code, resp, err)) end
            local nl = string.find(resp, "\n", 1, true)
            local head = nl and string.sub(resp, 1, nl - 1) or ""
            local good
            if kind == "map" then
                good = string.match(head, "^GCMAP[12]|%d+|%d+|") ~= nil
            else
                good = string.match(head, "^GCDEMO1|%d+|%d+|") ~= nil
            end
            if not good then return done(false, "The server sent a file in an unknown format.") end

            file.CreateDir("gcapture")
            file.CreateDir(kind == "map" and "gcapture/maps" or "gcapture/demos")
            local fn = LocalName(id)
            file.Write(Dir(kind) .. fn, resp)
            if not file.Exists(Dir(kind) .. fn, "DATA") then return done(false, "Can't save the file to disk.") end
            if kind == "map" and not MapRead(fn) then
                file.Delete(Dir(kind) .. fn)
                return done(false, "The map file is corrupted.")
            end
            done(true, fn)
        end)
    end

    function GC.OnlineUpload(kind, fn, title, desc, done)
        local raw = file.Read(Dir(kind) .. fn, "DATA")
        if not raw or raw == "" then return done(false, "Can't read the file.") end
        if #raw > GC.OnlineMaxBytes then
            return done(false, string.format("The file is too big: %s (limit %s).", SizeText(#raw), SizeText(GC.OnlineMaxBytes)))
        end
        local lp = LocalPlayer()
        Json("POST", "/api/upload", nil, {
            kind = kind,
            title = title,
            desc = desc,
            author = IsValid(lp) and lp:Nick() or "Player",
            sid = IsValid(lp) and (lp:SteamID64() or "") or "",
            data = raw,
        }, function(ok, d, err)
            if not ok then return done(false, err) end
            if d.id and d.token then
                owned[kind .. ":" .. d.id] = d.token
                SaveOwned()
            end
            done(true, d.id)
        end)
    end

    function GC.OnlineDelete(kind, id, done)
        local key = kind .. ":" .. tostring(id)
        local tok = owned[key]
        if not tok then return done(false, "You can only delete your own uploads.") end
        Json("POST", "/api/delete", nil, { kind = kind, id = id, token = tok }, function(ok, d, err)
            if ok or (d and d.gone) then
                owned[key] = nil
                SaveOwned()
                return done(true)
            end
            done(false, err)
        end)
    end

    function GC.OpenOnlineUpload(kind, onDone)
        if IsValid(GC.onlineUp) then GC.onlineUp:Remove() end
        local isMap = kind == "map"
        local f = vgui.Create("DFrame")
        f:SetTitle(isMap and "Upload a Map" or "Upload a Demo")
        f:SetSize(620, 540)
        f:Center()
        f:MakePopup()
        StyleFrame(f)
        GC.onlineUp = f

        local sel, busy = nil, false

        local bottom = vgui.Create("DPanel", f)
        bottom:Dock(BOTTOM)
        bottom:SetTall(40)
        bottom:DockMargin(6, 0, 6, 6)
        bottom.Paint = nil

        local bUp = vgui.Create("DButton", bottom)
        bUp:Dock(RIGHT) bUp:SetWide(140) bUp:SetText("Upload") StyleButton(bUp)
        local bCancel = vgui.Create("DButton", bottom)
        bCancel:Dock(RIGHT) bCancel:SetWide(90) bCancel:DockMargin(0, 0, 6, 0) bCancel:SetText("Cancel") StyleButton(bCancel)
        bCancel.DoClick = function() f:Remove() end

        local st = vgui.Create("DLabel", f)
        st:Dock(BOTTOM) st:SetTall(36) st:DockMargin(10, 0, 10, 0)
        st:SetFont("GCapture.Small") st:SetTextColor(TH.muted) st:SetWrap(true) st:SetText("")
        local function SetSt(t, col)
            if not IsValid(st) then return end
            st:SetText(t or "")
            st:SetTextColor(col or TH.muted)
        end

        local fields = vgui.Create("DPanel", f)
        fields:Dock(BOTTOM)
        fields:SetTall(150)
        fields:DockMargin(6, 4, 6, 0)
        fields.Paint = nil
        local function Lbl(text, y)
            local l = vgui.Create("DLabel", fields)
            l:SetPos(2, y)
            l:SetFont("GCapture.Small")
            l:SetTextColor(TH.muted)
            l:SetText(text)
            l:SizeToContents()
        end
        Lbl("Title (shown to everyone)", 0)
        local te = vgui.Create("DTextEntry", fields)
        te:SetPos(0, 18) te:SetSize(588, 26) StyleEntry(te)
        Lbl("Description (optional)", 50)
        local de = vgui.Create("DTextEntry", fields)
        de:SetPos(0, 68) de:SetSize(588, 56) de:SetMultiline(true) StyleEntry(de)
        Lbl("Uploads are public. Max " .. SizeText(GC.OnlineMaxBytes) .. " per file. Files you downloaded can't be re-uploaded.", 128)

        local intro = vgui.Create("DLabel", f)
        intro:Dock(TOP) intro:SetTall(22) intro:DockMargin(10, 2, 10, 2)
        intro:SetFont("GCapture.Small") intro:SetTextColor(TH.muted)
        intro:SetText("Pick one of your local " .. (isMap and "maps" or "demos") .. ":")

        local scroll = vgui.Create("DScrollPanel", f)
        scroll:Dock(FILL)
        scroll:DockMargin(6, 0, 6, 0)
        StyleScroll(scroll)

        local function AddRow(fn, title, sub, defTitle)
            local row = scroll:Add("DButton")
            row:Dock(TOP) row:SetTall(46) row:DockMargin(0, 0, 0, 4) row:SetText("")
            row.hv = 0
            local t1, t2 = Fit(title, "GCapture.Stat", 560), Fit(sub, "GCapture.Small", 560)
            row.Paint = function(s, w, h)
                s.hv = Lerp(math.min(1, FrameTime() * 14), s.hv, s:IsHovered() and 1 or 0)
                local on = sel ~= nil and sel.fn == fn
                draw.RoundedBox(4, 0, 0, w, h, on and TH.accent or LerpColor(s.hv, TH.hd, TH.accentDim))
                draw.RoundedBox(4, 1, 1, w - 2, h - 2, on and TH.rowHover or LerpColor(s.hv, TH.row, TH.rowHover))
                draw.SimpleText(t1, "GCapture.Stat", 10, 4, TH.text)
                draw.SimpleText(t2, "GCapture.Small", 10, 26, TH.muted)
            end
            row.DoClick = function()
                sel = { fn = fn, size = file.Size(Dir(kind) .. fn, "DATA") or 0 }
                te:SetValue(defTitle)
                SetSt("", TH.muted)
            end
        end

        local count = 0
        for _, fn in ipairs(file.Find(Dir(kind) .. "*.txt", "DATA", "datedesc") or {}) do
            if string.sub(fn, 1, 7) ~= "online_" then
                if isMap then
                    local w, h, name, np = MapHeader(fn)
                    if w then
                        count = count + 1
                        AddRow(fn, name, string.format("%dx%d     %s     %s%s", w, h, fn, SizeText(file.Size(MAP_DIR .. fn, "DATA")),
                            (np or 0) > 0 and ("     Preset countries: " .. np) or ""), name)
                    end
                else
                    local dur, ts, win, pl = ReadDemoHeader(fn)
                    if dur then
                        count = count + 1
                        AddRow(fn, (ts and os.date("%Y-%m-%d  %H:%M:%S", ts) or fn) .. string.format("     %d:%02d", math.floor(dur / 60), dur % 60),
                            string.format("Winner: %s     %s     %s", win ~= "" and win or "-", SizeText(file.Size(DEMO_DIR .. fn, "DATA")), pl or ""),
                            win ~= "" and ("Winner: " .. win) or "Game demo")
                    end
                end
            end
        end
        if count == 0 then
            local l = scroll:Add("DLabel")
            l:Dock(TOP) l:SetTall(50) l:DockMargin(8, 8, 8, 0)
            l:SetFont("GCapture.Small") l:SetTextColor(TH.muted) l:SetWrap(true)
            l:SetText(isMap and "You have no maps yet. Create one in Map Maker." or "You have no demos yet. Enable \"Record Demo\" in the lobby.")
        end

        bUp.DoClick = function()
            if busy then return end
            if not sel then return SetSt("Pick a file from the list first.", RED) end
            local title = string.Trim(te:GetValue() or "")
            if title == "" then return SetSt("Enter a title.", RED) end
            if sel.size > GC.OnlineMaxBytes then
                return SetSt(string.format("The file is too big: %s (limit %s).", SizeText(sel.size), SizeText(GC.OnlineMaxBytes)), RED)
            end
            busy = true
            bUp:SetEnabled(false)
            SetSt("Uploading " .. SizeText(sel.size) .. "...", TH.muted)
            GC.OnlineUpload(kind, sel.fn, Cut(title, 60), string.Trim(Cut(de:GetValue(), 200)), function(ok, res)
                busy = false
                if IsValid(bUp) then bUp:SetEnabled(true) end
                if not ok then return SetSt(res, RED) end
                if IsValid(f) then f:Remove() end
                if onDone then onDone() end
                Derma_Message("Uploaded! Everyone can now find it in Online " .. (isMap and "Maps" or "Demos") .. ".", "Upload", "OK")
            end)
        end
    end

    function GC.OpenOnline(kind)
        if IsValid(GC.onlineWin) then
            if GC.onlineWin.kind == kind then GC.onlineWin:MoveToFront() return end
            GC.onlineWin:Remove()
        end
        local isMap = kind == "map"
        local f = vgui.Create("DFrame")
        f:SetTitle(isMap and "Online Maps" or "Online Demos")
        f:SetSize(780, 560)
        f:Center()
        f:MakePopup()
        StyleFrame(f)
        f.kind = kind
        GC.onlineWin = f

        local sort, page, items, hasMore, total = "new", 0, {}, false, 0
        local sel, busy, filter, reqId = nil, false, "", 0
        local rows = {}
        local Load, Rebuild, UpdateBtns
        local bDl, bPlay, bDel, bMore

        local bottom = vgui.Create("DPanel", f)
        bottom:Dock(BOTTOM)
        bottom:SetTall(40)
        bottom:DockMargin(6, 0, 6, 6)
        bottom.Paint = nil
        local function Btn(text, side, wide, fn)
            local b = vgui.Create("DButton", bottom)
            b:Dock(side)
            b:SetWide(wide)
            b:DockMargin(side == RIGHT and 6 or 0, 0, side == LEFT and 6 or 0, 0)
            b:SetText(text)
            StyleButton(b)
            b.DoClick = fn
            return b
        end

        local statusLbl = vgui.Create("DLabel", f)
        statusLbl:Dock(BOTTOM) statusLbl:SetTall(22) statusLbl:DockMargin(10, 0, 10, 0)
        statusLbl:SetFont("GCapture.Small") statusLbl:SetTextColor(TH.muted) statusLbl:SetText("")
        local function SetStatus(t, col)
            if not IsValid(statusLbl) then return end
            statusLbl:SetText(t or "")
            statusLbl:SetTextColor(col or TH.muted)
        end

        local function Go(it, play)
            busy = true
            UpdateBtns()
            SetStatus("Downloading \"" .. Cut(it.title, 40) .. "\"...", TH.muted)
            GC.OnlineDownload(kind, it.id, function(ok, res)
                if not IsValid(f) then return end
                busy = false
                if not ok then
                    SetStatus(res, RED)
                    UpdateBtns()
                    return
                end
                local row = rows[SafeId(it.id)]
                if row then row.saved = true end
                if play then
                    f:Remove()
                    GC.CloseOptWins()
                    GC.EnterDemoList()
                    GC.PlayDemo(res)
                    return
                end
                SetStatus(isMap and "Saved! Open Other > Browse maps to use it." or "Saved! Open Other > Demos to watch it.", TH.accent)
                UpdateBtns()
            end)
        end

        local function DoGet(play)
            if not sel or busy then return end
            local it = sel
            if play and GC.playing and not GC.demoMode then
                return Derma_Query("Watching a demo will leave your current game. Continue?", "Play Demo", "Continue", function()
                    if IsValid(f) then Go(it, true) end
                end, "Cancel")
            end
            Go(it, play)
        end

        bDl = Btn("Download", RIGHT, 110, function() DoGet(false) end)
        if not isMap then bPlay = Btn("Download & Play", RIGHT, 140, function() DoGet(true) end) end
        bDel = Btn("Delete", RIGHT, 80, function()
            if not sel or busy then return end
            local it = sel
            Derma_Query("Delete \"" .. Cut(it.title, 40) .. "\" from the server for everyone?", "Delete", "Delete", function()
                if not IsValid(f) then return end
                busy = true
                UpdateBtns()
                GC.OnlineDelete(kind, it.id, function(ok, err)
                    if not IsValid(f) then return end
                    busy = false
                    if not ok then
                        SetStatus(err, RED)
                        UpdateBtns()
                        return
                    end
                    sel = nil
                    Load(true, true)
                end)
            end, "Cancel")
        end)
        bMore = Btn("Load more", RIGHT, 100, function() if not busy then Load(false) end end)
        Btn("Upload " .. (isMap and "Map" or "Demo") .. "...", LEFT, 150, function()
            GC.OpenOnlineUpload(kind, function() if IsValid(f) then Load(true, true) end end)
        end)
        Btn("Close", LEFT, 80, function() f:Remove() end)

        local top = vgui.Create("DPanel", f)
        top:Dock(TOP)
        top:SetTall(32)
        top:DockMargin(6, 4, 6, 4)
        top.Paint = nil

        local function Tab(text, key)
            local b = vgui.Create("DButton", top)
            b:Dock(LEFT)
            b:SetWide(90)
            b:DockMargin(0, 0, 6, 0)
            b:SetText(text)
            StyleButton(b)
            local base = b.Paint
            b.Paint = function(s, w, h)
                if sort == key then
                    draw.RoundedBox(4, 0, 0, w, h, TH.accent)
                    draw.RoundedBox(4, 1, 1, w - 2, h - 2, TH.rowHover)
                    s:SetTextColor(Color(255, 255, 255))
                else
                    base(s, w, h)
                end
            end
            b.DoClick = function() if sort ~= key and not busy then sort = key Load(true) end end
        end
        Tab("New", "new")
        Tab("Popular", "popular")

        local refresh = vgui.Create("DButton", top)
        refresh:Dock(RIGHT) refresh:SetWide(90) refresh:DockMargin(6, 0, 0, 0) refresh:SetText("Refresh") StyleButton(refresh)
        refresh.DoClick = function() if not busy then Load(true, true) end end

        local search = vgui.Create("DTextEntry", top)
        search:Dock(FILL)
        StyleEntry(search)
        local basePaint = search.Paint
        search.Paint = function(s, w, h)
            basePaint(s, w, h)
            if (s:GetValue() or "") == "" then
                draw.SimpleText("Filter loaded items by name or author...", "GCapture.Small", 8, h / 2, TH.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
        search.OnChange = function(s)
            filter = string.lower(s:GetValue() or "")
            Rebuild()
        end

        local scroll = vgui.Create("DScrollPanel", f)
        scroll:Dock(FILL)
        scroll:DockMargin(6, 0, 6, 6)
        StyleScroll(scroll)

        local function AddRow(it)
            local id = SafeId(it.id)
            local row = scroll:Add("DButton")
            row:Dock(TOP)
            row:SetTall(68)
            row:DockMargin(0, 0, 0, 4)
            row:SetText("")
            row.hv = 0
            row.saved = Saved(kind, id)
            rows[id] = row
            local mine = owned[kind .. ":" .. id] ~= nil

            local parts = { "by " .. Cut(it.author or "Player", 32) }
            if isMap then
                parts[#parts + 1] = string.format("%dx%d", math.floor(tonumber(it.w) or 0), math.floor(tonumber(it.h) or 0))
                if (tonumber(it.np) or 0) > 0 then parts[#parts + 1] = math.floor(it.np) .. " preset countries" end
            else
                local dur = math.floor(tonumber(it.dur) or 0)
                parts[#parts + 1] = string.format("%d:%02d", math.floor(dur / 60), dur % 60)
                if (it.win or "") ~= "" then parts[#parts + 1] = "Winner: " .. Cut(it.win, 40) end
            end
            parts[#parts + 1] = SizeText(it.size)
            parts[#parts + 1] = Ago(it.ts)
            parts[#parts + 1] = math.floor(tonumber(it.downloads) or 0) .. " downloads"

            local desc = it.desc or ""
            if desc == "" and not isMap and (it.pl or "") ~= "" then desc = "Players: " .. it.pl end
            local t1 = Fit(it.title or "?", "GCapture.Stat", 500)
            local t2 = Fit(table.concat(parts, "   |   "), "GCapture.Small", 720)
            local t3 = Fit(desc, "GCapture.Small", 720)

            row.Paint = function(s, w, h)
                s.hv = Lerp(math.min(1, FrameTime() * 14), s.hv, s:IsHovered() and 1 or 0)
                local on = sel ~= nil and sel.id == it.id
                draw.RoundedBox(4, 0, 0, w, h, on and TH.accent or LerpColor(s.hv, TH.hd, TH.accentDim))
                draw.RoundedBox(4, 1, 1, w - 2, h - 2, on and TH.rowHover or LerpColor(s.hv, TH.row, TH.rowHover))
                draw.SimpleText(t1, "GCapture.Stat", 10, 4, TH.text)
                draw.SimpleText(t2, "GCapture.Small", 10, 28, TH.muted)
                if t3 ~= "" then draw.SimpleText(t3, "GCapture.Small", 10, 46, TH.text) end
                local rx = w - 8
                if mine then rx = Badge("YOURS", rx, 6, BROWN, GOLD) end
                if s.saved then rx = Badge("SAVED", rx, 6, TH.accentDim, TH.text) end
            end
            row.DoClick = function()
                sel = it
                UpdateBtns()
            end
            row.DoDoubleClick = function()
                sel = it
                UpdateBtns()
                DoGet(not isMap)
            end
        end

        Rebuild = function()
            scroll:Clear()
            rows = {}
            local shown = 0
            for _, it in ipairs(items) do
                local hay = string.lower((it.title or "") .. " " .. (it.author or "") .. " " .. (it.desc or "") .. " " .. (it.win or "") .. " " .. (it.pl or ""))
                if filter == "" or string.find(hay, filter, 1, true) then
                    shown = shown + 1
                    AddRow(it)
                end
            end
            if shown == 0 then
                local l = scroll:Add("DLabel")
                l:Dock(TOP) l:SetTall(60) l:DockMargin(8, 8, 8, 0)
                l:SetFont("GCapture.Small") l:SetTextColor(TH.muted) l:SetWrap(true)
                l:SetText(#items > 0 and "No matches among the loaded items." or (busy and "" or "Nothing here yet. Be the first: press Upload."))
            end
        end

        UpdateBtns = function()
            local has = sel ~= nil and not busy
            bDl:SetEnabled(has)
            if bPlay then bPlay:SetEnabled(has) end
            bDel:SetEnabled(has and owned[kind .. ":" .. SafeId(sel.id)] ~= nil)
            bMore:SetEnabled(hasMore and not busy)
        end

        Load = function(reset, bust)
            if reset then
                page, items, hasMore, total, sel = 0, {}, false, 0, nil
            end
            reqId = reqId + 1
            local my = reqId
            busy = true
            UpdateBtns()
            Rebuild()
            SetStatus("Loading...", TH.muted)
            local q = { kind = kind, sort = sort, page = page, limit = PAGE }
            if bust then q.t = os.time() end
            Json("GET", "/api/list", q, nil, function(ok, d, err)
                if not IsValid(f) or my ~= reqId then return end
                busy = false
                if not ok then
                    SetStatus(err, RED)
                    UpdateBtns()
                    return
                end
                for _, it in ipairs(d.items or {}) do items[#items + 1] = it end
                hasMore = d.hasMore and true or false
                total = tonumber(d.total) or #items
                page = page + 1
                SetStatus(string.format("Showing %d of %d", #items, total), TH.muted)
                Rebuild()
                UpdateBtns()
            end)
        end

        UpdateBtns()
        Load(true)
    end
end

local function OpenOther()
    local f = OptWin("other", "Other", 300, 170)
    if not f then return end
    local function B(y, text, tip, fn)
        local b = vgui.Create("DButton", f)
        b:SetPos(14, y)
        b:SetSize(272, 34)
        b:SetText(text)
        if tip then b:SetTooltip(tip) end
        StyleButton(b)
        b.DoClick = fn
        return b
    end
    B(38, "Map Maker", nil, function() GC.OpenMapMakerSetup() end)
    B(80, "Browse maps", "Your maps", function() GC.OpenMapPicker() end)
    B(122, "Demos", "Open demos", function() GC.CloseOptWins() GC.EnterDemoList() end)
end

local cvGuide = CreateClientConVar("cl_gc_guide_seen", "0", true, false, "GCapture: guide button was opened once")
local GUIDE = {
    { "Goal & Basics", {
        "# Goal",
        "Capture enemy capitals. The last player standing wins. A captured capital gives its land and ships to the conqueror, its armies vanish.",
        "# Start",
        "- Pick a national spirit. You get a random one if you don't.",
        "- Expand around the capital and grab neutral villages and chests.",
        "- Build Villages, then a Weaponry and an Army Center.",
        "- Keep an army at the capital.",
    } },
    { "Controls", {
        "- Wheel: zoom. Middle mouse or Alt + left drag: move the map.",
        "- Right-click a cell: actions for that cell.",
        "- Hover a cell: biome, owner, structure, army.",
        "- Left-click selects an army, drag selects many (Shift or Ctrl adds).",
        "- Hover a counter in the top panel to see its modifiers.",
        "- Game messages are at the bottom left.",
    } },
    { "Territory & Biomes", {
        "# Expanding",
        "Expand onto free land next to your land or ship, one cell at a time. Cells with enemy armies are blocked. Expand onto a village or chest to take it.",
        "# Biomes",
        "- Plains: best population.",
        "- Forest: average income. Some spirits favor it.",
        "- Desert: slows armies. Oil Rigs only.",
        "- Tundra: armies attack and defend worse. Most chests are here.",
        "- Water: can't be owned. Ships only.",
        "# Cut-off land",
        "Land cut off from the capital can't build or recruit. On another island you need a ship touching both islands.",
    } },
    { "Buildings", {
        "Build on an empty own cell connected to the capital (right-click).",
        "- Village: coins. Armies nearby recover organization.",
        "- Weaponry: weapons.",
        "- Army / Cavalry Center: recruit infantry / cavalry here.",
        "- Fortress: blocks the cell. 3 levels, each attack or airstrike removes one. Upgradable.",
        "- Trap: hidden from enemies. The first attacker loses population and the trap is gone.",
        "- Oil Rig: desert only. Big income for a short time, then gone. Once per cell.",
        "- Coast Guard: coast only. Sinks enemy ships in range and warns of landings.",
        "- Airbase: bombs enemy cells in range, has a reload time.",
        "- Chest: open it on your land for a national spirit.",
        "- Fire: left after a bombing, burns out. Crater: left by meteors, permanent, blocks armies.",
        "Delete Structure gives no refund. The capital can't be deleted.",
    } },
    { "Armies", {
        "# Recruiting",
        "Right-click an empty own cell with an Army or Cavalry Center. New armies need a moment to train. Each army costs upkeep.",
        "# Stats",
        "- Organization (blue): moving costs it, at 0 the army can't attack. Recovers near villages.",
        "- HP (red): lost on defeat, doesn't regenerate.",
        "- Cavalry: more organization, less HP, better attack, worse defense, faster.",
    } },
    { "Combat", {
        "# Rounds",
        "One round per second. The attacker either takes 1 organization from the defender or loses 1, then the defender may take 1 back. Defense is a bit stronger, so don't attack with equal organization.",
        "# Result",
        "At 0 organization the defender loses 1 HP and retreats to a free neighboring own cell, or is destroyed if there is none. At 0 HP the army dies. If the attacker runs out first, the attack stops.",
        "# Notes",
        "- Several armies can attack one defender.",
        "- Attacking an empty cell takes a moment. Fortresses lose a level per attack, traps cost the attacker population.",
        "- Retreat gives up the cell and saves the army.",
        "- Tundra, desert, night and spirits change the chances (see the ATK/DEF counters).",
        "- Every 5th won battle gives a national spirit choice.",
        "- Capturing a capital eliminates its owner.",
    } },
    { "Ships", {
        "- Build a ship on water next to your land and sail it cell by cell. It carries one army.",
        "- Load an army by moving it onto the ship. Disembark onto a coast cell: own = unload, neutral = claim, enemy = landing battle.",
        "- Disassemble a ship next to land to get part of the cost back.",
        "- A Coast Guard in range can sink enemy ships. The army on board drowns.",
        "- A ship lets you expand onto land next to it and build on other islands.",
    } },
    { "National Spirits", {
        "Permanent bonuses that stack. Hover a spirit to see its modifiers.",
        "# How to get them",
        "- At the start: 1 of 3.",
        "- Every 7 minutes: everyone picks again.",
        "- Every 5th won battle.",
        "- Chests: a random spirit, 50% chance of an uncommon one.",
        "# Uncommon spirits",
        "Red and much stronger. They come only from chests.",
        "# Hate spirits",
        "Bonus attack against one random rival. That rival's color appears in the spirit's name.",
    } },
    { "Diplomacy", {
        "Right-click an enemy cell, then Diplomacy.",
        "- Propose Pact: for a while nobody can attack or bomb the other.",
        "- Send Letter, Donate resources.",
        "- Allow / Revoke Military Access: foreign armies can enter your land, nobody can attack while it's open. On revoke they teleport to their nearest cell.",
        "- Request Military Access: ask for the same.",
        "- Sever Relations: you stop getting their messages. Restore Relations undoes it.",
        "Actions have cooldowns. Bots accept pacts only when defensive and never read letters. Sometimes a bot lets you through if it has another enemy.",
    } },
    { "Fog, Day & Night", {
        "# Fog of war",
        "You see only the area around your land and ships. Explored terrain is remembered, but enemies outside your view are hidden and you can't give orders there. After you lose, the fog disappears.",
        "# Day and night",
        "The day counter is at the top right. At night the map darkens and armies attack a bit worse.",
    } },
    { "Tips", {
        "- Grab neutral villages early, they're the cheapest income.",
        "- Build a Weaponry before you need soldiers, weapons come slowly.",
        "- Rest armies near villages. Don't attack with low organization.",
        "- Keep one army at the capital.",
        "- Watch upkeep: too many armies drain your coins.",
        "- Fortresses and traps on chokepoints. Pacts buy time against a strong neighbor.",
        "- Open chests, spirits add up over a long game.",
        "- Defend at night, push by day.",
    } },
}

local function WrapText(text, font, maxw)
    surface.SetFont(font)
    local out, line = {}, ""
    for word in string.gmatch(text, "%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if line ~= "" and surface.GetTextSize(try) > maxw then out[#out + 1] = line line = word else line = try end
    end
    if line ~= "" then out[#out + 1] = line end
    return out
end
local function GuideLayout(items, w)
    local lay, y = {}, 8
    for _, it in ipairs(items) do
        local kind, text = "p", it
        if string.sub(it, 1, 2) == "# " then kind, text = "h", string.sub(it, 3)
        elseif string.sub(it, 1, 2) == "- " then kind, text = "b", string.sub(it, 3) end
        local font = (kind == "h") and "GCapture.Stat" or "GCapture.Small"
        local indent = (kind == "b") and 18 or 0
        if kind == "h" then y = y + 8 end
        for k, l in ipairs(WrapText(text, font, w - 24 - indent)) do
            lay[#lay + 1] = { l, font, 12 + indent, y, kind, k == 1 }
            y = y + (kind == "h" and 24 or 17)
        end
        y = y + (kind == "h" and 4 or 5)
    end
    return lay, y + 10
end
function GC.OpenGuide()
    local f = OptWin("guide", "Guide", 860, 580)
    if not f then return end
    local nav = vgui.Create("DScrollPanel", f)
    nav:Dock(LEFT) nav:SetWide(190) nav:DockMargin(6, 6, 4, 6) StyleScroll(nav)
    local content = vgui.Create("DScrollPanel", f)
    content:Dock(FILL) content:DockMargin(4, 6, 6, 6) StyleScroll(content)
    content.Paint = function(s, w, h) draw.RoundedBox(6, 0, 0, w, h, TH.hd) end
    local CW = 600
    local function Show(k)
        f.sec = k content:Clear()
        local lay, h = GuideLayout(GUIDE[k][2], CW)
        local panel = content:Add("DPanel") panel:Dock(TOP) panel:SetTall(h)
        panel.Paint = function(s, w, hh)
            for _, l in ipairs(lay) do
                local col = (l[5] == "h") and TH.accent or TH.text
                draw.SimpleText(l[1], l[2], l[3], l[4], col)
                if l[5] == "b" and l[6] then draw.RoundedBox(2, l[3] - 11, l[4] + 6, 4, 4, TH.accent) end
            end
        end
        content:GetVBar():SetScroll(0)
    end
    for k, sec in ipairs(GUIDE) do
        local b = nav:Add("DButton") b:Dock(TOP) b:SetTall(30) b:DockMargin(0, 0, 0, 4) b:SetText(sec[1]) StyleButton(b)
        local base = b.Paint
        b.Paint = function(s, w, h) base(s, w, h) if f.sec == k then surface.SetDrawColor(TH.accent) surface.DrawOutlinedRect(0, 0, w, h, 2) end end
        b.DoClick = function() Show(k) end
    end
    Show(1)
end

function GC.OpenSubMods()
    local f = OptWin("submods", "Sub-Mods", 540, 440)
    if not f then return end
    local sc = vgui.Create("DScrollPanel", f)
    sc:Dock(FILL)
    sc:DockMargin(6, 6, 6, 6)
    StyleScroll(sc)
    sc.Paint = function(s, w, h) draw.RoundedBox(6, 0, 0, w, h, TH.hd) end
    local list = GC.Mods and GC.Mods.list or {}
    if #list == 0 then
        local lbl = sc:Add("DLabel")
        lbl:Dock(TOP)
        lbl:DockMargin(14, 14, 14, 0)
        lbl:SetFont("GCapture.Stat")
        lbl:SetTextColor(TH.muted)
        lbl:SetWrap(true)
        lbl:SetAutoStretchVertical(true)
        lbl:SetText("No sub-mods installed. Subscribe to GCapture sub-mods in the Steam Workshop and they will appear here.")
        return
    end
    for _, m in ipairs(list) do
        local nSp, nBd, nAc = 0, 0, 0
        for _, d in pairs(GC.SpiritDefs) do if d.mod == m.id then nSp = nSp + 1 end end
        for _, d in pairs(GC.Build) do if d.mod == m.id then nBd = nBd + 1 end end
        for _, d in ipairs(GC.Mods.Actions) do if d.mod == m.id then nAc = nAc + 1 end end
        local row = sc:Add("DPanel")
        row:Dock(TOP)
        row:SetTall(96)
        row:DockMargin(6, 6, 6, 0)
        row.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, m.failed and Color(150, 40, 40) or TH.accentDim)
            draw.RoundedBox(6, 1, 1, w - 2, h - 2, TH.row)
            draw.SimpleText(m.name, "GCapture.Big", 12, 6, m.failed and Color(255, 120, 120) or TH.accent)
            draw.SimpleText(string.format("v%s by %s  [%s]", m.version, m.author, m.id), "GCapture.Small", 12, 36, TH.muted)
            draw.SimpleText(m.failed and "Failed to load, see the console" or string.format("Spirits: %d   Structures: %d   Actions: %d", nSp, nBd, nAc), "GCapture.Small", 12, 74, m.failed and Color(255, 120, 120) or TH.text)
        end
        local desc = vgui.Create("DLabel", row)
        desc:SetPos(12, 54)
        desc:SetSize(500, 18)
        desc:SetFont("GCapture.Small")
        desc:SetTextColor(TH.text)
        desc:SetText(m.desc ~= "" and m.desc or "No description.")
    end
end

local function BuildLobby(root)
    local lobby = vgui.Create("DPanel", root)
    lobby:Dock(FILL)
    lobby.Paint = nil
    local function Box(panel)
        panel.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, TH.accentDim)
            draw.RoundedBox(6, 1, 1, w - 2, h - 2, TH.bg)
            GC.PanelBloom(w, h, 0.7)
        end
    end
    local left = vgui.Create("DPanel", lobby)
    left:Dock(LEFT)
    left:SetWide(280)
    left:DockMargin(0, 0, 8, 0)
    Box(left)
    local title = vgui.Create("DLabel", left)
    title:Dock(TOP)
    title:SetTall(30)
    title:SetFont("GCapture.Stat")
    title:SetText("  Players")
    title:SetTextColor(TH.accent)
    local scroll = vgui.Create("DScrollPanel", left)
    scroll:Dock(FILL)
    scroll:DockMargin(6, 0, 6, 6)
    StyleScroll(scroll)
    local right = vgui.Create("DPanel", lobby)
    right:Dock(FILL)
    Box(right)
    local btns = {}
    local function Big(text, fn)
        local b = vgui.Create("DButton", right)
        b:SetText(text)
        b:SetFont("GCapture.Stat")
        StyleButton(b)
        b.DoClick = fn
        btns[#btns + 1] = b
        return b
    end
    local hostBtns = { Big("Game Options", OpenGameOptions), Big("Map", OpenMap), Big("Bots", OpenBots) }
    Big("Player", OpenPlayer)
    local function GreenGlow(b)
        local base = b.Paint
        b.Paint = function(s2, w, h)
            base(s2, w, h)
            local p = 0.5 + 0.5 * math.sin(CurTime() * 3)
            draw.RoundedBox(4, 0, 0, w, h, Color(40, 255, 90, 28 + 22 * p))
            surface.SetDrawColor(70, 255, 120, 170 + 60 * p)
            surface.DrawOutlinedRect(0, 0, w, h, 2)
            s2:SetTextColor(Color(190, 255, 205))
        end
    end
    local onDemos = Big("Browse Online Demos", function() GC.OpenOnline("demo") end)
    onDemos:SetTooltip("Download or share demos")
    GreenGlow(onDemos)
    local onMaps = Big("Browse Online Maps", function() GC.OpenOnline("map") end)
    onMaps:SetTooltip("Download or share maps")
    GreenGlow(onMaps)
    Big("Other", OpenOther)
    Big("Settings", function() GC.OpenSettings() end)
    local guideBtn = Big("Guide", function()
        GC.guideSeen = true
        RunConsoleCommand("cl_gc_guide_seen", "1")
        GC.OpenGuide()
    end)
    local gBase = guideBtn.Paint
    guideBtn.Paint = function(s, w, h)
        gBase(s, w, h)
        if not (GC.guideSeen or cvGuide:GetBool()) then
            local p = 0.5 + 0.5 * math.sin(CurTime() * 4)
            draw.RoundedBox(4, 0, 0, w, h, Color(255, 40, 40, 35 + 60 * p))
            surface.SetDrawColor(255, 60, 60, 150 + 105 * p)
            surface.DrawOutlinedRect(0, 0, w, h, 2)
            s:SetTextColor(Color(255, 190, 190))
        end
    end
    local modsBtn = vgui.Create("DButton", right)
    modsBtn:SetFont("GCapture.Stat")
    StyleButton(modsBtn)
    modsBtn.Paint = function(s, w, h)
        s.hv = Lerp(math.min(1, FrameTime() * 14), s.hv, s:IsHovered() and 1 or 0)
        s.pr = Lerp(math.min(1, FrameTime() * 30), s.pr, s:IsDown() and 1 or 0)
        local k = s.hv
        draw.RoundedBox(4, 0, 0, w, h, LerpColor(k, Color(150, 36, 36), Color(240, 70, 70)))
        local inset = 1 + math.floor(s.pr + 0.5)
        draw.RoundedBox(4, inset, inset, w - inset * 2, h - inset * 2, LerpColor(k, Color(70, 18, 18), Color(110, 28, 28)))
        s:SetTextColor(LerpColor(k, Color(255, 205, 205), Color(255, 255, 255)))
    end
    modsBtn.Think = function(s)
        local n = GC.Mods and #GC.Mods.list or 0
        local t = n > 0 and ("Sub-Mods (" .. n .. ")") or "Sub-Mods"
        if s.txt ~= t then s.txt = t s:SetText(t) end
    end
    modsBtn.DoClick = function() GC.OpenSubMods() end
    local menuBtn = vgui.Create("DButton", right)
    menuBtn:SetText("Main Menu")
    menuBtn:SetFont("GCapture.Stat")
    StyleButton(menuBtn)
    menuBtn.DoClick = function() GC.GoMenu() end
    local info = vgui.Create("DPanel", right)
    info.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, TH.accentDim)
        draw.RoundedBox(6, 1, 1, w - 2, h - 2, TH.hd)
        draw.SimpleText(GC.single and "Singleplayer" or "Lobby", "GCapture.Stat", 12, 5, TH.accent)
        local o = GC.lobbyOpts or {}
        local custom = (o.map or "") ~= ""
        local sz = GC.SizeList[o.size or 1] or 32
        local nb = o.bots or 0
        local function OnOff(v) return v and "On" or "Off" end
        local npre, mode = (custom and not o.nopresets) and (o.presets or 0) or 0, o.mode or 0
        local seedRow = { "Seed", custom and "-" or ((o.seed or "") ~= "" and o.seed or "random") }
        if npre > 0 then
            seedRow = { "Countries", mode ~= 1 and (npre .. " preset") or (npre .. " (off in Rush)"), Color(255, 200, 90) }
        end
        local cols = {
            { { "Map", custom and o.map or string.format("Random %dx%d", sz, sz) },
              seedRow,
              { "Bots", nb == 0 and "None" or (nb .. " (" .. (DNAMES[o.diff or 1] or "?") .. ")") },
              { "Players", tostring(#(GC.lobbyList or {})) } },
            { { "Fog of war", OnOff(not o.nofog) }, { "Events", OnOff(not o.noevents) },
              { "Mode", (string.gsub(MODE_NAMES[mode] or "?", " Mode", "")) }, { "Host observes", OnOff(o.observe) } },
        }
        surface.SetFont("GCapture.Small")
        for c, rows in ipairs(cols) do
            local x0 = c == 1 and 12 or (w / 2 + 6)
            local maxw = w / 2 - 100
            for r, row in ipairs(rows) do
                local y = 30 + (r - 1) * 20
                draw.SimpleText(row[1], "GCapture.Small", x0, y, TH.muted)
                local value = row[2]
                while #value > 3 and surface.GetTextSize(value) > maxw do value = string.sub(value, 1, #value - 2) end
                if value ~= row[2] then value = value .. ".." end
                draw.SimpleText(value, "GCapture.Small", x0 + 82, y, row[3] or TH.text)
            end
        end
    end
    local startBtn = vgui.Create("DButton", right)
    startBtn:SetText("Start")
    startBtn:SetFont("GCapture.Big")
    StyleButton(startBtn)
    startBtn.DoClick = function()
        if IsValid(GC.nameTe) then GC.SendName(GC.nameTe:GetValue()) end
        if IsValid(GC.seedTe) and GC.isHost then GC.SetOpt("seed", string.Trim(GC.seedTe:GetValue())) end
        net.Start("GCapture_Start")
        net.SendToServer()
    end
    local wait = vgui.Create("DLabel", right)
    wait:SetFont("GCapture.Small")
    wait:SetText("Waiting for the host...")
    wait:SetTextColor(TH.muted)
    wait:SizeToContents()
    local autoLbl = vgui.Create("DLabel", right)
    autoLbl:SetFont("GCapture.Stat")
    autoLbl:SetTextColor(TH.accent)
    autoLbl:SetContentAlignment(5)
    autoLbl.Think = function(s)
        local e = GC.autoEnd
        if e then s:SetVisible(true) s:SetText("Auto start in " .. math.max(0, math.ceil(e - CurTime())) .. " s")
        else s:SetVisible(false) end
    end
    right.PerformLayout = function(s, w, h)
        local bw = math.floor((w - 36) / 2)

        local nrows = math.floor((#btns - 1) / 2) + 1
        local infoTop = h - 86 - 112
        local pitch = math.Clamp(math.floor((infoTop - 8 - 14) / nrows), 30, 42)
        local bh = pitch - 8
        for k, b in ipairs(btns) do
            b:SetPos(14 + ((k - 1) % 2) * (bw + 8), 14 + math.floor((k - 1) / 2) * pitch)
            b:SetSize(bw, bh)
        end
        local lastRow = math.floor((#btns - 1) / 2)
        if #btns % 2 == 0 then lastRow = lastRow + 1 end
        guideBtn:SetPos(14, 14 + lastRow * pitch)
        guideBtn:SetSize(bw, bh)
        modsBtn:SetPos(14 + bw + 8, 14 + lastRow * pitch)
        modsBtn:SetSize(bw, bh)
        local mw = math.floor((w - 28) * 0.36)
        local sw = w - 28 - mw - 8
        menuBtn:SetPos(w - 14 - mw, h - 60)
        menuBtn:SetSize(mw, 46)
        startBtn:SetSize(sw, 46)
        startBtn:SetPos(14, h - 60)
        wait:SizeToContents()
        wait:SetPos(14 + (sw - wait:GetWide()) / 2, h - 44)
        autoLbl:SetPos(14, h - 86)
        autoLbl:SetSize(w - 28, 22)
        info:SetSize(w - 28, 112)
        info:SetPos(14, infoTop)
    end
    local ui = { panel = lobby }
    function ui.SetSingle(v)
        left:SetVisible(not v)
        lobby:InvalidateLayout(true)
    end
    function ui.Refresh()
        startBtn:SetVisible(GC.isHost)
        wait:SetVisible(not GC.isHost)
        for _, hb in ipairs(hostBtns) do
            hb:SetEnabled(GC.isHost == true)
            hb:SetTooltip(not GC.isHost and "Host only" or nil)
        end
        if not GC.isHost then
            for _, id in ipairs({ "opts", "bots", "map" }) do
                local w = GC.optWins[id]
                if IsValid(w) then w:Remove() GC.optWins[id] = nil end
            end
        end
        GC.SyncOptWins()
        scroll:Clear()
        for k, ply in ipairs(GC.lobbyList or {}) do
            if IsValid(ply) then
                local row = scroll:Add("DPanel")
                row:Dock(TOP)
                row:SetTall(30)
                row:DockMargin(0, 0, 0, 4)
                row.Paint = function(s, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, TH.row)
                    local c = (GC.lobbyColors or {})[k]
                    if c then draw.RoundedBox(3, w - 20, h / 2 - 7, 14, 14, c) end
                end
                local av = vgui.Create("AvatarImage", row)
                av:SetSize(26, 26)
                av:SetPos(2, 2)
                av:SetPlayer(ply, 32)
                local lbl = vgui.Create("DLabel", row)
                lbl:Dock(FILL)
                lbl:DockMargin(34, 0, 24, 0)
                lbl:SetFont("GCapture.Small")
                lbl:SetTextColor(TH.text)
                lbl:SetText((GC.lobbyNames[k] or ply:Nick()) .. (ply == LocalPlayer() and "  (you)" or ""))
                lbl:SetTooltip(ply:Nick())
            end
        end
    end
    return ui
end

local TIP_GOOD, TIP_BAD = Color(110, 235, 140), Color(255, 110, 110)

local function MyPlayer() return GC.players[GC.mySlot or 0] end
local function Sec(v)
    v = math.Round(v, 2)
    if v == 0 then v = 0 end
    return string.format("%+g/s", v)
end
local function Pct(v) return string.format("%+g%%", math.Round(v * 100, 2)) end
local function Pc(v) return string.format("%g%%", math.Round(v * 100, 1)) end

local function Chance(slot, cav, def)
    local C = GC.Combat
    if def then
        return C.DefenseChance + GC.DefenseMods(slot, cav, 0)
    end
    return C.AttackChance + GC.AttackMods(slot, cav, 0, nil) + GC.NightAtk()
end

local function Counts(slot)
    local c = { vill = 0, weap = 0, oil = 0, army = 0, cav = 0 }
    for i = 1, GCN do
        if GC.owner[i] == slot then
            local b = GC.build[i]
            if b == GC.B_VILLAGE then c.vill = c.vill + 1
            elseif b == GC.B_WEAPONRY then c.weap = c.weap + 1
            elseif b == GC.B_OIL then c.oil = c.oil + 1 end
        end
    end
    for _, A in pairs(GC.army) do
        if A.owner == slot then
            if A.cav then c.cav = c.cav + 1 else c.army = c.army + 1 end
        end
    end
    return c
end

local function Row(rows, label, v, text, lcol)
    rows[#rows + 1] = { label, text, v == 0 and TH.muted or (v > 0 and TIP_GOOD or TIP_BAD), lcol }
end
local function Plain(rows, label, text) rows[#rows + 1] = { label, text, TH.text } end

local function SpiritRows(rows, key, fmt, suffix)
    local me, sum = MyPlayer(), 0
    for _, inst in ipairs(me and me.spirits or {}) do
        local d = GC.SpiritDefs[inst.id]
        local v = d and d.mods and d.mods[key]
        if v then
            sum = sum + v
            Row(rows, GC.SpiritName(inst, GC.players) .. (suffix or ""), v, fmt(v), d.rare and GC.UncommonColor or nil)
        end
    end
    return sum
end

local function TipCoins()
    local slot, rows = GC.mySlot, {}
    local c = Counts(slot)
    local vc = c.vill * (GC.Build[GC.B_VILLAGE].coin or 0)
    if c.vill > 0 then Row(rows, "Villages (" .. c.vill .. ")", vc, Sec(vc)) end
    local oilEach = math.max(0, GC.Build[GC.B_OIL].coin + GC.Mod(slot, "oilCoin"))
    local oc = c.oil * oilEach
    if c.oil > 0 then Row(rows, "Oil Rigs (" .. c.oil .. ")", oc, Sec(oc)) end
    local sp = SpiritRows(rows, "coins", Sec)
    local up = 0
    for _, A in pairs(GC.army) do
        if A.owner == slot then up = up + GC.UpkeepPerArmy(slot, A.cav) end
    end
    if up > 0 then Row(rows, "Army upkeep", -up, Sec(-up)) end
    local vir = (GC.virusEnd and CurTime() < GC.virusEnd) and -10 or 0
    if vir ~= 0 then Row(rows, "Virus", vir, Sec(vir)) end
    local me = MyPlayer()
    local disc = (me and me.discEnd and CurTime() < me.discEnd) and (me.disc or 0) or 0
    if disc > 0 then Row(rows, string.format("Discontent (%d s)", math.ceil(me.discEnd - CurTime())), -disc, Sec(-disc)) end
    return "Coins per second", rows, "TOTAL: " .. Sec(vc + oc + sp - up + vir - disc), "Limit: " .. GC.CoinLimit
end

local function TipPop()
    local slot, rows, cnt = GC.mySlot, {}, {}
    for i = 1, GCN do
        if GC.owner[i] == slot then cnt[GC.biome[i]] = (cnt[GC.biome[i]] or 0) + 1 end
    end
    local terr = 0
    for b = 1, 4 do
        local n = cnt[b]
        if n then
            local v = n * GC.Biomes[b].pop
            terr = terr + v
            Row(rows, "Territory: " .. GC.Biomes[b].name .. " (" .. n .. ")", v, Sec(v))
        end
    end
    local sp = SpiritRows(rows, "pop", Sec)
    local vir = (GC.virusEnd and CurTime() < GC.virusEnd) and -500 or 0
    if vir ~= 0 then Row(rows, "Virus", vir, Sec(vir)) end
    return "Population per second", rows, "TOTAL: " .. Sec(terr + sp + vir),
        "Limit: " .. GC.PopLimit(slot) .. " (" .. GC.PopPerCell .. " per cell)"
end

local function TipWeapons()
    local slot, rows = GC.mySlot, {}
    local c = Counts(slot)
    local wc = c.weap * (GC.Build[GC.B_WEAPONRY].weapon or 0)
    if c.weap > 0 then Row(rows, "Weaponry (" .. c.weap .. ")", wc, Sec(wc)) end
    local sp = SpiritRows(rows, "weapons", Sec)
    return "Weapons per second", rows, "TOTAL: " .. Sec(wc + sp)
end

local function TipChance(cav, def)
    return function()
        local slot, C, me, rows = GC.mySlot, GC.Combat, MyPlayer(), {}
        local key, ckey = def and "defense" or "attack", def and "cavDefense" or "cavAttack"
        Plain(rows, "Base", Pc(def and C.DefenseChance or C.AttackChance))
        if cav then
            local cb = def and C.CavDefense or C.CavAttack
            Row(rows, "Cavalry", cb, Pct(cb))
        end
        if not cav then SpiritRows(rows, key, Pct) end
        if not def then
            local np = GC.NightAtk()
            if np < -0.001 then Row(rows, "Night", np, Pct(np)) end
        end
        if cav then SpiritRows(rows, ckey, Pct, " (cav)") end

        local any = false
        local tund = def and C.TundraDefense or C.TundraAttack
        Row(rows, "On Tundra", tund, Pct(tund), TH.muted)
        for _, inst in ipairs(me and me.spirits or {}) do
            local d = GC.SpiritDefs[inst.id]
            local nm = GC.SpiritName(inst, GC.players)
            if not cav and d and d.vs and d.vs[key] then
                local T = GC.players[inst.target or 0]
                Row(rows, nm .. " vs " .. (T and T.name or "?"), d.vs[key], Pct(d.vs[key]), TH.muted)
                any = true
            end
            if d and d.biome then
                for b = 1, 4 do
                    local bm = d.biome[b]
                    if bm then
                        for _, k in ipairs(cav and { ckey } or { key }) do
                            if bm[k] then
                                Row(rows, nm .. " on " .. GC.Biomes[b].name, bm[k], Pct(bm[k]), TH.muted)
                                any = true
                            end
                        end
                    end
                end
            end
        end
        return (cav and "Cavalry " or "Army ") .. (def and "Defense Chance" or "Attack Chance"),
            rows, "TOTAL: " .. Pc(Chance(slot, cav, def)), "Gray rows: only in some cases"
    end
end
local TipAA, TipAD, TipCA, TipCD = TipChance(false, false), TipChance(false, true), TipChance(true, false), TipChance(true, true)

local function TipVillages()
    local c, rows = Counts(GC.mySlot), {}
    local each = GC.Build[GC.B_VILLAGE].coin or 0
    Plain(rows, "Villages", tostring(c.vill))
    Row(rows, "Income each", each, Sec(each))
    Plain(rows, "Supply radius", GC.SupplyRadius .. " cells")
    return "Villages", rows, "TOTAL: " .. Sec(c.vill * each), "Armies near villages regain organization"
end

local function TipWeaponry()
    local c, rows = Counts(GC.mySlot), {}
    local each = GC.Build[GC.B_WEAPONRY].weapon or 0
    Plain(rows, "Weaponry", tostring(c.weap))
    Row(rows, "Production each", each, Sec(each))
    return "Weaponry", rows, "TOTAL: " .. Sec(c.weap * each)
end

local function TipArmies(cav)
    return function()
        local slot, rows = GC.mySlot, {}
        local c = Counts(slot)
        local n = cav and c.cav or c.army
        local u = GC.UpkeepPerArmy(slot, cav)
        Plain(rows, cav and "Cavalry units" or "Armies", tostring(n))
        Row(rows, "Upkeep each", -u, Sec(-u))
        Plain(rows, "Max Organization", tostring(GC.MaxOrg(slot, cav)))
        Plain(rows, "Max HP", tostring(GC.MaxHP(slot, cav)))
        Plain(rows, "Training time", GC.TrainTime(slot, cav) .. " sec")
        return cav and "Cavalry" or "Armies", rows, "TOTAL upkeep: " .. Sec(-u * n), "Upkeep is paid in coins"
    end
end
local TipArmy, TipCav = TipArmies(false), TipArmies(true)

local function TipPlayers()
    local rows, alive = {}, 0
    for _, P in ipairs(GC.players) do
        if not (GC.demo and not P.ever) then
            local nm = P.name .. ((P.diff and P.diff ~= "") and (" [" .. P.diff .. "]") or "")
            if P.dead then
                rows[#rows + 1] = { nm, "eliminated", TIP_BAD, TH.muted }
            else
                alive = alive + 1
                rows[#rows + 1] = { nm, "", TH.text, P.color }
            end
        end
    end
    return "Players", rows, "Alive: " .. alive
end

local function DrawTopTip(w, h)
    local t = GC.topTip
    if not t then return end
    local title, rows, total, foot = t.fn()
    if not title then return end

    surface.SetFont("GCapture.Stat")
    local bw = math.max(surface.GetTextSize(title), total and surface.GetTextSize(total) or 0)
    surface.SetFont("GCapture.Small")
    for _, r in ipairs(rows) do
        bw = math.max(bw, surface.GetTextSize(r[1]) + surface.GetTextSize(r[2]) + 24)
    end
    if foot then bw = math.max(bw, (surface.GetTextSize(foot))) end
    bw = bw + 24
    local bh = 36 + math.max(1, #rows) * 17 + (total and 28 or 0) + (foot and 18 or 0) + 6
    local x, y = math.Clamp(t.x, 4, math.max(4, w - bw - 4)), 4

    draw.RoundedBox(6, x, y, bw, bh, TH.accent)
    draw.RoundedBox(6, x + 1, y + 1, bw - 2, bh - 2, Color(8, 14, 10, 245))
    draw.SimpleText(title, "GCapture.Stat", x + 12, y + 6, TH.accent)
    surface.SetDrawColor(TH.accentDim)
    surface.DrawRect(x + 10, y + 30, bw - 20, 1)

    local cy = y + 36
    if #rows == 0 then
        draw.SimpleText("No modifiers", "GCapture.Small", x + 12, cy, TH.muted)
        cy = cy + 17
    end
    for _, r in ipairs(rows) do
        draw.SimpleText(r[1], "GCapture.Small", x + 12, cy, r[4] or TH.text)
        draw.SimpleText(r[2], "GCapture.Small", x + bw - 12, cy, r[3], TEXT_ALIGN_RIGHT)
        cy = cy + 17
    end
    if total then
        surface.SetDrawColor(TH.accentDim)
        surface.DrawRect(x + 10, cy + 2, bw - 20, 1)
        draw.SimpleText(total, "GCapture.Stat", x + 12, cy + 6, TH.accent)
        cy = cy + 28
    end
    if foot then draw.SimpleText(foot, "GCapture.Small", x + 12, cy, TH.muted) end
end

do
    local function AllCounts()
        local t = {}
        for s = 1, #GC.players do t[s] = { cells = 0, vill = 0, weap = 0, army = 0, cav = 0 } end
        for i = 1, GCN do
            local c = t[GC.owner[i]]
            if c then
                c.cells = c.cells + 1
                local b = GC.build[i]
                if b == GC.B_VILLAGE then c.vill = c.vill + 1 elseif b == GC.B_WEAPONRY then c.weap = c.weap + 1 end
            end
        end
        for _, A in pairs(GC.army) do
            local c = t[A.owner]
            if c then if A.cav then c.cav = c.cav + 1 else c.army = c.army + 1 end end
        end
        return t
    end
    GC.AllCounts = AllCounts

    function GC.OpenStats()
        if IsValid(GC.statsFrame) then GC.statsFrame:MoveToFront() return end
        local f = vgui.Create("DFrame")
        f:SetTitle("Statistics & National Spirits")
        f:SetSize(640, 540)
        f:Center()
        f:MakePopup()
        StyleFrame(f)
        GC.statsFrame = f

        local p = vgui.Create("DPanel", f)
        p:Dock(FILL)
        p:DockMargin(6, 6, 6, 6)
        p.scroll, p.nextT = 0, 0
        p.OnMouseWheeled = function(s, d) s.scroll = math.max(0, s.scroll - d * 40) end
        p.Paint = function(s, w, h)
            draw.RoundedBox(4, 0, 0, w, h, TH.hd)
            if not s.order or #s.order ~= #GC.players or CurTime() > s.nextT then
                s.cnt, s.nextT, s.order = AllCounts(), CurTime() + 0.5, {}
                for k = 1, #GC.players do s.order[k] = k end
                table.sort(s.order, function(a, b)
                    local ca, cb = s.cnt[a].cells, s.cnt[b].cells
                    if ca ~= cb then return ca > cb end
                    return a < b
                end)
            end
            local hits, y = {}, 4 - s.scroll
            surface.SetFont("GCapture.Small")
            for _, sl in ipairs(s.order) do
                local P, c = GC.players[sl], s.cnt[sl]
                if P and c then

                    local chips, cx, cy = {}, 14, 0
                    for _, inst in ipairs(P.spirits or {}) do
                        local d = GC.SpiritDefs[inst.id]
                        if d then
                            local name = GC.SpiritName(inst, GC.players)
                            local tw = surface.GetTextSize(name) + 14
                            if cx + tw > w - 14 and cx > 14 then cx, cy = 14, cy + 24 end
                            chips[#chips + 1] = { inst = inst, name = name, x = cx, y = cy, w = tw, rare = d.rare,
                                T = d.target and GC.players[inst.target or 0] }
                            cx = cx + tw + 6
                        end
                    end
                    local rh = 66 + ((#chips > 0) and (cy + 24) or 18)

                    draw.RoundedBox(6, 6, y, w - 12, rh, TH.accentDim)
                    draw.RoundedBox(6, 7, y + 1, w - 14, rh - 2, TH.row)
                    surface.SetDrawColor(P.color)
                    surface.DrawRect(14, y + 9, 12, 12)
                    draw.SimpleText(P.name, "GCapture.Stat", 32, y + 4, P.color)
                    draw.SimpleText(string.format("Cells %d     Coins %d     Pop %d     Weapons %d", c.cells,
                        math.floor(P.coins), math.floor(P.pop), math.floor(P.weapons)), "GCapture.Small", 14, y + 28, TH.text)
                    draw.SimpleText(string.format("Villages %d     Weaponry %d     Armies %d     Cavalry %d",
                        c.vill, c.weap, c.army, c.cav), "GCapture.Small", 14, y + 45, TH.muted)

                    local base = y + 64
                    if #chips == 0 then draw.SimpleText("No national spirits", "GCapture.Small", 14, base, TH.muted) end
                    for _, ch in ipairs(chips) do
                        local x0, y0 = ch.x, base + ch.y
                        draw.RoundedBox(4, x0, y0, ch.w, 20, ch.rare and Color(70, 20, 20) or TH.hd)
                        draw.SimpleText(ch.name, "GCapture.Small", x0 + 7, y0 + 3,
                            ch.rare and GC.UncommonColor or (ch.T and ch.T.color) or TH.text)
                        hits[#hits + 1] = { x0, y0, ch.w, 20, ch.inst }
                    end
                    y = y + rh + 6
                end
            end
            s.scroll = math.min(s.scroll, math.max(0, y + s.scroll - h))

            local mx, my = s:CursorPos()
            for _, hb in ipairs(hits) do
                if mx >= hb[1] and mx <= hb[1] + hb[3] and my >= hb[2] and my <= hb[2] + hb[4] then
                    local _, lines = GC.SpiritLines(hb[5], GC.players)
                    surface.SetFont("GCapture.Small")
                    local bw = 0
                    for _, l in ipairs(lines) do bw = math.max(bw, (surface.GetTextSize(l))) end
                    bw = bw + 16
                    local bh = #lines * 16 + 8
                    local tx, ty = math.min(mx + 14, w - bw - 4), math.min(my + 14, h - bh - 4)
                    draw.RoundedBox(4, tx, ty, bw, bh, TH.accent)
                    draw.RoundedBox(4, tx + 1, ty + 1, bw - 2, bh - 2, Color(8, 14, 10, 245))
                    for k, l in ipairs(lines) do
                        draw.SimpleText(l, "GCapture.Small", tx + 8, ty + 4 + (k - 1) * 16, k == 1 and TH.accent or TH.text)
                    end
                    break
                end
            end
        end
    end
end

do
    local function ConSlider(parent, y, text, cv)
        local p = vgui.Create("DPanel", parent)
        p:SetPos(14, y)
        p:SetSize(292, 36)
        local function Set(s)
            local x = s:CursorPos()
            RunConsoleCommand(cv:GetName(), tostring(math.Round(math.Clamp(x / s:GetWide(), 0, 1), 2)))
        end
        p.Paint = function(s, w, h)
            local f = cv:GetFloat()
            draw.SimpleText(text .. ": " .. math.Round(f * 100) .. "%", "GCapture.Small", 0, 0, TH.text)
            draw.RoundedBox(3, 0, 24, w, 6, TH.hd)
            draw.RoundedBox(3, 0, 24, w * f, 6, TH.accent)
            draw.RoundedBox(4, math.Clamp(w * f - 5, 0, w - 10), 18, 10, 18, TH.text)
        end
        p.OnMousePressed = function(s) s.drag = true s:MouseCapture(true) Set(s) end
        p.OnCursorMoved = function(s) if s.drag then Set(s) end end
        p.OnMouseReleased = function(s) s.drag = false s:MouseCapture(false) end
    end

    local function Check(parent, y, text, cvName)
        local cb = vgui.Create("DCheckBoxLabel", parent)
        cb:SetPos(14, y)
        cb:SetSize(280, 20)
        cb:SetText(text)
        cb:SetConVar(cvName)
        cb.Label:SetFont("GCapture.Small")
        cb.Label:SetTextColor(TH.text)
        cb.Button.Paint = function(s, w, h)
            draw.RoundedBox(3, 0, 0, w, h, TH.accentDim)
            draw.RoundedBox(3, 1, 1, w - 2, h - 2, TH.hd)
            if s:GetChecked() then draw.RoundedBox(2, 4, 4, w - 8, h - 8, TH.accent) end
        end
    end

    function GC.OpenSettings()
        if IsValid(GC.settingsFrame) then GC.settingsFrame:MoveToFront() return end
        local f = vgui.Create("DFrame")
        f:SetTitle("Settings")
        f:SetSize(320, 626)
        f:Center()
        f:MakePopup()
        StyleFrame(f)
        GC.settingsFrame = f
        ConSlider(f, 40, "Music volume      ", GC.cvMusVol)
        ConSlider(f, 92, "Sound effects volume      ", GC.cvSfxVol)
        ConSlider(f, 144, "Structure opacity      ", GC.cvBuildAlpha)
        ConSlider(f, 196, "Unit opacity (ships, armies)      ", GC.cvUnitAlpha)
        ConSlider(f, 248, "Combat bubble opacity      ", GC.cvBubbleAlpha)
        ConSlider(f, 300, "HP / organization bar opacity      ", GC.cvBarAlpha)
        Check(f, 356, "Show clouds      ", "cl_gc_clouds")
        Check(f, 384, "Dynamic music      ", "cl_gc_music")
        Check(f, 412, "Fancy water      ", "cl_gc_water_fx")
        local l = vgui.Create("DLabel", f)
        l:SetPos(14, 442)
        l:SetFont("GCapture.Small")
        l:SetTextColor(TH.text)
        l:SetText("Theme color")
        l:SizeToContents()

        local THEMES = { { -1, "Green" }, { 215, "Blue" }, { 180, "Cyan" }, { 275, "Purple" },
            { 325, "Pink" }, { 0, "Red" }, { 28, "Orange" }, { 48, "Gold" } }
        for k, t in ipairs(THEMES) do
            local sw = vgui.Create("DButton", f)
            sw:SetPos(14 + (k - 1) * 36, 462)
            sw:SetSize(30, 30)
            sw:SetText("")
            sw:SetTooltip(t[2])
            local prev = t[1] < 0 and Color(60, 210, 110) or HSVToColor(t[1], 0.70, 0.82)
            sw.hv = 0
            sw.Paint = function(s, w, h)
                s.hv = Lerp(math.min(1, FrameTime() * 14), s.hv, s:IsHovered() and 1 or 0)
                local cur = GetConVar("cl_gc_theme"):GetInt()
                if cur == t[1] then draw.RoundedBox(5, 0, 0, w, h, color_white) end
                local pad = 3 - 2 * s.hv
                draw.RoundedBox(4, pad, pad, w - pad * 2, h - pad * 2, prev)
            end
            sw.DoClick = function() RunConsoleCommand("cl_gc_theme", tostring(t[1])) end
        end

        local hue = vgui.Create("DPanel", f)
        hue:SetPos(14, 502)
        hue:SetSize(292, 26)
        hue.Paint = function(s, w, h)
            for x = 0, w - 1, 2 do
                surface.SetDrawColor(HSVToColor(x / w * 360, 0.70, 0.82))
                surface.DrawRect(x, 8, 2, 10)
            end
            local cur = GetConVar("cl_gc_theme"):GetInt()
            if cur >= 0 then
                local px = cur / 360 * w
                draw.RoundedBox(4, math.Clamp(px - 5, 0, w - 10), 2, 10, 22, color_white)
            end
        end
        local function SetHue(s)
            local x = s:CursorPos()
            RunConsoleCommand("cl_gc_theme", tostring(math.Round(math.Clamp(x / s:GetWide(), 0, 1) * 360)))
        end
        hue.OnMousePressed = function(s) s.drag = true s:MouseCapture(true) SetHue(s) end
        hue.OnCursorMoved = function(s) if s.drag then SetHue(s) end end
        hue.OnMouseReleased = function(s) s.drag = false s:MouseCapture(false) end
        hue:SetTooltip("Custom hue")

        local seed = GC.playing and (GC.seed or "") or ""
        local sl = vgui.Create("DLabel", f)
        sl:SetPos(14, 540)
        sl:SetFont("GCapture.Small")
        sl:SetTextColor(TH.text)
        sl:SetText("Map seed")
        sl:SizeToContents()

        local te = vgui.Create("DTextEntry", f)
        te:SetPos(14, 560)
        te:SetSize(212, 26)
        te:SetEditable(false)
        te:SetValue(seed ~= "" and seed or (GC.playing and "custom map" or "after the game starts"))
        StyleEntry(te)

        local cp = vgui.Create("DButton", f)
        cp:SetPos(232, 560)
        cp:SetSize(74, 26)
        cp:SetText("Copy")
        StyleButton(cp)
        cp:SetEnabled(seed ~= "")
        cp.DoClick = function()
            SetClipboardText(seed)
            table.insert(GC.Msgs, { text = "Seed copied: " .. seed, t = CurTime() })
        end

        local nt = vgui.Create("DLabel", f)
        nt:SetPos(14, 594)
        nt:SetFont("GCapture.Small")
        nt:SetTextColor(TH.muted)
        nt:SetText("Same seed, size and players = same map")
        nt:SizeToContents()
    end
end

local function EdgeGrad(px, py, pw, ph, side, c, a0)
    local steps = 5
    local sz = math.max(3, math.floor(math.min(pw, ph) * 0.55))
    local st = math.max(1, math.floor(sz / steps))
    for k = 0, steps - 1 do
        surface.SetDrawColor(c.r, c.g, c.b, a0 * (1 - k / steps) ^ 2)
        local o = k * st
        if side == 1 then surface.DrawRect(px + o, py, st, ph)
        elseif side == 2 then surface.DrawRect(px + pw - o - st, py, st, ph)
        elseif side == 3 then surface.DrawRect(px, py + o, pw, st)
        else surface.DrawRect(px, py + ph - o - st, pw, st) end
    end
end

local COL_SHALLOW, COL_SHADOW = Color(110, 190, 225), Color(0, 18, 40)
local COL_TREE = Color(6, 40, 18, 55)
local function Blend(bm, b, j, side, px, py, pw, ph)
    local nb = bm[j]
    if not nb or nb == 0 or nb == b then return end
    if b == GC.WATER then
        if not GC.fxWater then return end

        if side == 1 or side == 3 then EdgeGrad(px, py, pw, ph, side, COL_SHADOW, 70)
        else EdgeGrad(px, py, pw, ph, side, COL_SHALLOW, 85) end
    elseif nb ~= GC.WATER then
        EdgeGrad(px, py, pw, ph, side, GC.Biomes[nb].color, 85)
    end
end

local function EdgeShadow(px, py, pw, ph, side, bt, sw)
    local steps = 4
    local st = math.max(1, math.floor(sw / steps))
    for k = 0, steps - 1 do
        surface.SetDrawColor(0, 0, 0, 90 * (1 - k / steps) ^ 2)
        local inn, out = bt + k * st, (k + 1) * st
        if side == 1 then
            surface.DrawRect(px + inn, py, st, ph)
            surface.DrawRect(px - out, py, st, ph)
        elseif side == 2 then
            surface.DrawRect(px + pw - inn - st, py, st, ph)
            surface.DrawRect(px + pw + out - st, py, st, ph)
        elseif side == 3 then
            surface.DrawRect(px, py + inn, pw, st)
            surface.DrawRect(px, py - out, pw, st)
        else
            surface.DrawRect(px, py + ph - inn - st, pw, st)
            surface.DrawRect(px, py + ph + out - st, pw, st)
        end
    end
end

function GC.OpenCountryInfo(slot)
    if not GC.players[slot] then return end
    if IsValid(GC.infoFrame) then GC.infoFrame:Remove() end
    local f = vgui.Create("DFrame")
    f:SetTitle("Country")
    f:SetSize(380, 500)
    f:Center()
    f:MakePopup()
    StyleFrame(f)
    f.slot = slot
    GC.infoFrame = f
    local p = vgui.Create("DPanel", f)
    p:Dock(FILL)
    p:DockMargin(6, 6, 6, 6)
    p.scroll, p.nextT = 0, 0
    p.OnMouseWheeled = function(s, d) s.scroll = math.max(0, s.scroll - d * 40) end
    p.Paint = function(s, w, h)
        local P = GC.players[f.slot]
        if not P then return end
        draw.RoundedBox(4, 0, 0, w, h, TH.hd)
        if CurTime() > s.nextT then
            s.nextT = CurTime() + 0.5
            local all = GC.AllCounts and GC.AllCounts() or {}
            s.cnt = all[f.slot]
            s.cap = nil
            for i = 1, GCN do if GC.owner[i] == f.slot and GC.build[i] == GC.B_CAPITAL then s.cap = i break end end
        end
        local c = s.cnt or { cells = 0, vill = 0, weap = 0, army = 0, cav = 0 }
        local y = 8 - s.scroll
        surface.SetDrawColor(P.color)
        surface.DrawRect(12, y + 5, 14, 14)
        draw.SimpleText(P.name, "GCapture.Big", 34, y, P.color)
        y = y + 32
        local sub = (P.diff and P.diff ~= "") and ("Bot, difficulty: " .. P.diff) or "Player"
        if P.dead then sub = sub .. "   (eliminated)" end
        draw.SimpleText(sub, "GCapture.Small", 12, y, TH.muted)
        y = y + 22
        local function Row(a, b)
            draw.SimpleText(a, "GCapture.Small", 12, y, TH.muted)
            draw.SimpleText(b, "GCapture.Small", w - 14, y, TH.text, TEXT_ALIGN_RIGHT)
            y = y + 18
        end
        Row("Cells", tostring(c.cells))
        Row("Coins", tostring(math.floor(P.coins or 0)))
        Row("Population", tostring(math.floor(P.pop or 0)))
        Row("Weapons", tostring(math.floor(P.weapons or 0)))
        Row("Villages", tostring(c.vill))
        Row("Weaponry", tostring(c.weap))
        Row("Armies", tostring(c.army))
        Row("Cavalry", tostring(c.cav))
        Row("Capital", s.cap and string.format("(%d, %d)", (s.cap - 1) % GCW, math.floor((s.cap - 1) / GCW)) or "lost")
        y = y + 8
        surface.SetDrawColor(TH.accentDim)
        surface.DrawRect(12, y, w - 24, 1)
        y = y + 8
        draw.SimpleText("National spirits", "GCapture.Stat", 12, y, TH.accent)
        y = y + 26
        if #(P.spirits or {}) == 0 then draw.SimpleText("None", "GCapture.Small", 12, y, TH.muted) y = y + 18 end
        for _, inst in ipairs(P.spirits or {}) do
            local d = GC.SpiritDefs[inst.id]
            if d then
                local name, lines = GC.SpiritLines(inst, GC.players)
                local T = d.target and GC.players[inst.target or 0]
                draw.SimpleText(name, "GCapture.Small", 12, y, d.rare and GC.UncommonColor or (T and T.color) or TH.text)
                y = y + 17
                for k = 2, #lines do draw.SimpleText(lines[k], "GCapture.Small", 24, y, TH.muted) y = y + 15 end
                y = y + 6
            end
        end
        s.scroll = math.min(s.scroll, math.max(0, y + s.scroll - h))
    end
end

local function BuildGame(root)
    local game = vgui.Create("DPanel", root)
    game:Dock(FILL)
    game.Paint = nil

    local top = vgui.Create("DPanel", game)
    top:Dock(TOP)
    top:SetTall(82)
    top:DockMargin(0, 0, 0, 6)
    local matHouse, matWeap = mats[GC.B_VILLAGE], mats[GC.B_WEAPONRY]
    top.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, TH.accentDim)
        draw.RoundedBox(6, 1, 1, w - 2, h - 2, TH.bg)
        GC.PanelBloom(w, h, 0.7)
        GC.topTip = nil

        local me = GC.players[GC.mySlot or 0]
        if me then
            local slot = GC.mySlot
            local hov = s:IsHovered()
            local cx, cy = s:CursorPos()
            surface.SetDrawColor(me.color)
            surface.DrawRect(8, 6, 6, 20)

            local x = 22
            local function Stat(mat, text, tip, y, font)
                font = font or "GCapture.Stat"
                surface.SetFont(font)
                local tw = surface.GetTextSize(text)
                local x1 = x + 22 + tw
                if hov and cx >= x - 4 and cx <= x1 + 4 and cy >= y - 2 and cy <= y + 22 then
                    draw.RoundedBox(4, x - 5, y - 2, x1 - x + 10, 24, TH.row)
                    GC.topTip = { fn = tip, x = x - 5 }
                end
                surface.SetDrawColor(255, 255, 255)
                surface.SetMaterial(mat)
                surface.DrawTexturedRect(x, y + 2, 16, 16)
                draw.SimpleText(text, font, x + 22, y, TH.text)
                x = x1 + 22
            end

            Stat(matCoins, string.format("%.1f / %d", me.coins, GC.CoinLimit), TipCoins, 6)
            Stat(matPop, string.format("%d / %d", math.floor(me.pop), GC.PopLimit(slot)), TipPop, 6)
            Stat(matGun, string.format("%d", math.floor(me.weapons)), TipWeapons, 6)

            x = 22
            local c = Counts(slot)
            local F = "GCapture.Mid"
            Stat(matArmy, "ATK " .. Pc(Chance(slot, false, false)), TipAA, 32, F)
            Stat(matArmy, "DEF " .. Pc(Chance(slot, false, true)), TipAD, 32, F)
            Stat(matCav, "ATK " .. Pc(Chance(slot, true, false)), TipCA, 32, F)
            Stat(matCav, "DEF " .. Pc(Chance(slot, true, true)), TipCD, 32, F)
            x = x + 10
            Stat(matHouse, tostring(c.vill), TipVillages, 32, F)
            Stat(matWeap, tostring(c.weap), TipWeaponry, 32, F)
            Stat(matArmy, "Armies " .. c.army, TipArmy, 32, F)
            Stat(matCav, "Cav " .. c.cav, TipCav, 32, F)
        else
            draw.SimpleText(GC.demo and "Demo replay" or "Spectating", "GCapture.Stat", 10, 6, TH.muted)
        end

        local list = {}
        for _, P in ipairs(GC.players) do
            if not P.dead and not (GC.demo and not P.ever) then
                surface.SetFont("GCapture.Small")
                local label = P.name .. ((P.diff and P.diff ~= "") and (" [" .. P.diff .. "]") or "")
                    .. (GC.demo and string.format("  %dc %dp %dw", math.floor(P.coins), math.floor(P.pop), math.floor(P.weapons)) or "")
                list[#list + 1] = { P = P, label = label, tw = surface.GetTextSize(label) }
            end
        end
        local limit, used, shown = w - 440, 10, 0
        for k, e in ipairs(list) do
            local need = e.tw + 30
            local reserve = (k < #list) and 56 or 0
            if used + need + reserve > limit then break end
            used, shown = used + need, k
        end
        local x = 10
        for k = 1, shown do
            local e = list[k]
            surface.SetDrawColor(e.P.color)
            surface.DrawRect(x, 63, 10, 10)
            draw.SimpleText(e.label, "GCapture.Small", x + 14, 60, Color(210, 230, 215))
            x = x + e.tw + 30
        end
        local mx3, my3 = s:CursorPos()
        if shown < #list then
            local txt = "+" .. (#list - shown)
            local cw = surface.GetTextSize(txt) + 14
            local hc = s:IsHovered() and mx3 >= x and mx3 <= x + cw and my3 >= 56 and my3 <= 78
            draw.RoundedBox(4, x, 58, cw, 18, hc and TH.accentDim or TH.row)
            draw.SimpleText(txt, "GCapture.Small", x + 7, 60, TH.text)
        end
        if s:IsHovered() and my3 >= 56 and not GC.topTip then GC.topTip = { fn = TipPlayers, x = mx3 } end
    end

    local stop = vgui.Create("DButton", top)
    StyleButton(stop)
    stop:Dock(RIGHT)
    stop:SetWide(70)
    stop:DockMargin(0, 6, 6, 6)
    stop:SetText("Stop")
    stop.DoClick = function()
        net.Start("GCapture_Stop")
        net.SendToServer()
    end

    local spBtn = vgui.Create("DButton", top)
    StyleButton(spBtn)
    spBtn:Dock(RIGHT)
    spBtn:SetWide(130)
    spBtn:DockMargin(0, 6, 6, 6)
    spBtn:SetText("National Spirits")

    spBtn.DoClick = function() GC.OpenSpirits() end

    local stBtn = vgui.Create("DButton", top)
    stBtn:Dock(RIGHT)
    stBtn:SetWide(100)
    stBtn:DockMargin(0, 6, 6, 6)
    stBtn:SetText("Statistics")

    StyleButton(stBtn)
    stBtn.DoClick = function() GC.OpenStats() end

    local setBtn = vgui.Create("DButton", top)
    setBtn:Dock(RIGHT)
    setBtn:SetWide(90)
    setBtn:DockMargin(0, 6, 6, 6)
    setBtn:SetText("Settings")

    StyleButton(setBtn)
    setBtn.DoClick = function() GC.OpenSettings() end

    local bar = vgui.Create("DPanel", game)
    bar:Dock(BOTTOM)
    bar:SetTall(40)
    bar:DockMargin(0, 6, 0, 0)
    bar:SetVisible(false)
    bar.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, TH.accentDim)
        draw.RoundedBox(6, 1, 1, w - 2, h - 2, TH.bg)
        GC.PanelBloom(w, h, 0.7)
    end

    local function BarBtn(text, wide, dock, fn)
        local b = vgui.Create("DButton", bar)
        b:Dock(dock)
        b:SetWide(wide)
        b:DockMargin(dock == RIGHT and 0 or 4, 5, dock == RIGHT and 4 or 0, 5)
        b:SetText(text)
        StyleButton(b)
        b.DoClick = fn
        return b
    end

    BarBtn("Back", 80, RIGHT, function() GC.ExitDemo() end)

    local timeL = vgui.Create("DLabel", bar)
    timeL:Dock(RIGHT)
    timeL:SetWide(110)
    timeL:SetFont("GCapture.Small")
    timeL:SetTextColor(TH.text)
    timeL:SetContentAlignment(5)
    timeL.Think = function(s)
        local dm = GC.demo
        if not dm then return end
        local t, c = #dm.d.frames - 1, math.max(0, dm.k - 1)
        s:SetText(string.format("%d:%02d / %d:%02d", math.floor(c / 60), c % 60, math.floor(t / 60), t % 60))
    end

    local playB = BarBtn("Pause", 70, LEFT, function()
        local dm = GC.demo
        if not dm then return end
        if not dm.playing and dm.k >= #dm.d.frames then GC.DemoSeek(0) GC.DemoSeek(1) end
        dm.playing = not dm.playing
    end)
    playB.Think = function(s)
        local dm = GC.demo
        if dm then s:SetText(dm.playing and "Pause" or "Play") end
    end
    BarBtn("-10s", 52, LEFT, function() if GC.demo then GC.DemoSeek(math.max(1, GC.demo.k - 10)) end end)
    BarBtn("+10s", 52, LEFT, function() if GC.demo then GC.DemoSeek(GC.demo.k + 10) end end)
    local speeds = { 1, 2, 4, 8, 0.5 }
    local spB
    spB = BarBtn("1x", 52, LEFT, function()
        local dm = GC.demo
        if not dm then return end
        dm.si = (dm.si or 1) % #speeds + 1
        dm.speed = speeds[dm.si]
        spB:SetText(dm.speed .. "x")
    end)

    local sl = vgui.Create("DPanel", bar)
    sl:Dock(FILL)
    sl:DockMargin(10, 8, 10, 8)
    sl.Paint = function(s, w, h)
        draw.RoundedBox(3, 0, h / 2 - 3, w, 6, TH.hd)
        local dm = GC.demo
        if not dm then return end
        local f = (dm.k - 1) / math.max(1, #dm.d.frames - 1)
        local mxs = s:CursorPos()
        for _, m in ipairs(dm.evMarks or {}) do
            local px = (m[1] - 1) / math.max(1, #dm.d.frames - 1) * w
            surface.SetDrawColor(255, 200, 60)
            surface.DrawRect(px - 1, h / 2 - 8, 2, 16)
            if s:IsHovered() and math.abs(mxs - px) < 5 then
                draw.SimpleTextOutlined(m[2], "GCapture.Small", math.Clamp(px, 0, w), -4, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
            end
        end
        draw.RoundedBox(3, 0, h / 2 - 3, w * f, 6, TH.accent)
        draw.RoundedBox(4, math.Clamp(w * f - 5, 0, w - 10), h / 2 - 8, 10, 16, TH.text)
    end
    function sl:SeekToCursor()
        local dm = GC.demo
        if not dm then return end
        local x = self:CursorPos()
        local f = math.Clamp(x / math.max(1, self:GetWide()), 0, 1)
        GC.DemoSeek(1 + math.Round(f * (#dm.d.frames - 1)))
    end
    sl.OnMousePressed = function(s) s.drag = true s:MouseCapture(true) s:SeekToCursor() end
    sl.OnCursorMoved = function(s) if s.drag then s:SeekToCursor() end end
    sl.OnMouseReleased = function(s) s.drag = false s:MouseCapture(false) end

    local map = vgui.Create("DPanel", game)
    map:Dock(FILL)
    map.zoom, map.ox, map.oy = 1, 0, 0
    map.tz, map.tox, map.toy = 1, 0, 0

    function map:CellSize()
        return math.min(self:GetWide() / GCW, self:GetTall() / GCH) * self.zoom
    end

    function map:FocusCell(cell)
        local m = math.max(GCW, GCH)
        self.zoom = math.Clamp(m / 14, 1.5, math.max(6, m / 10))
        local cs = self:CellSize()
        local cx, cy = (cell - 1) % GCW, math.floor((cell - 1) / GCW)
        self.ox = self:GetWide() / 2 - (cx + 0.5) * cs
        self.oy = self:GetTall() / 2 - (cy + 0.5) * cs
        self:ClampPan()
        self.tz, self.tox, self.toy = self.zoom, self.ox, self.oy
    end

    function map:ClampPan()
        local w, h = self:GetSize()
        local cs = self:CellSize()
        local sw, sh = cs * GCW, cs * GCH
        if sw <= w then self.ox = (w - sw) / 2 else self.ox = math.Clamp(self.ox, w - sw, 0) end
        if sh <= h then self.oy = (h - sh) / 2 else self.oy = math.Clamp(self.oy, h - sh, 0) end
    end

    function map:CellAt(mx, my)
        local cs = self:CellSize()
        local x, y = math.floor((mx - self.ox) / cs), math.floor((my - self.oy) / cs)
        if x < 0 or y < 0 or x >= GCW or y >= GCH then return end
        return y * GCW + x + 1
    end

    function map:ClampTarget()
        self.tz = self.tz or self.zoom
        self.tox, self.toy = self.tox or self.ox, self.toy or self.oy
        local w, h = self:GetSize()
        local cs = math.min(w / GCW, h / GCH) * self.tz
        local sw, sh = cs * GCW, cs * GCH
        if sw <= w then self.tox = (w - sw) / 2 else self.tox = math.Clamp(self.tox, w - sw, 0) end
        if sh <= h then self.toy = (h - sh) / 2 else self.toy = math.Clamp(self.toy, h - sh, 0) end
    end

    function map:OnMouseWheeled(delta)
        local mx, my = self:CursorPos()
        self.tz = self.tz or self.zoom
        self.tox, self.toy = self.tox or self.ox, self.toy or self.oy
        local base = math.min(self:GetWide() / GCW, self:GetTall() / GCH)
        local old = base * self.tz
        self.tz = math.Clamp(self.tz * (delta > 0 and 1.25 or 0.8), 1, math.max(6, math.max(GCW, GCH) / 10))
        local new = base * self.tz
        self.tox = mx - (mx - self.tox) / old * new
        self.toy = my - (my - self.toy) / old * new
        self:ClampTarget()
    end

    function map:OnMousePressed(code)

        if GC.pick then
            local pk = GC.pick
            GC.pick = nil
            if code == MOUSE_LEFT then
                local to = self:CellAt(self:CursorPos())
                if to and table.HasValue(PickCandidates(pk), to) then
                    SendAct(pk.from, pk.act, to)
                end
            end
            return
        end

        if code == MOUSE_LEFT then
            local mx, my = self:CursorPos()
            local cell = self:CellAt(mx, my)
            local now = CurTime()
            if cell and self.lastLeftCell == cell and now - (self.lastLeftTime or 0) <= 0.32 then
                self.lastLeftCell, self.lastLeftTime = nil, 0
                if GC.mySlot and GC.owner[cell] == 0 and GC.HasNeighbor(GC.owner, cell, GC.mySlot, GC.ship)
                    and (not GC.fog or GC.vis[cell]) then
                    SendAct(cell, 1)
                    return
                end
            end
            self.lastLeftCell, self.lastLeftTime = cell, now
            if input.IsKeyDown(KEY_LALT) then
                self.drag = { mx = mx, my = my, ox = self.tox or self.ox, oy = self.toy or self.oy }
            else
                self.box = { x0 = mx, y0 = my, x1 = mx, y1 = my,
                    add = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_LCONTROL) }
            end
            self:MouseCapture(true)
        elseif code == MOUSE_MIDDLE then
            local mx, my = self:CursorPos()
            self.drag = { mx = mx, my = my, ox = self.tox or self.ox, oy = self.toy or self.oy }
            self:MouseCapture(true)
        elseif code == MOUSE_RIGHT then
            self:OpenMenu()
        end
    end

    function map:FinishSelect(b)
        local slot = GC.mySlot
        if not slot then return end
        local moved = math.abs(b.x1 - b.x0) > 5 or math.abs(b.y1 - b.y0) > 5
        if not b.add then GC.sel, GC.selShip = {}, {} end
        GC.selShip = GC.selShip or {}
        if not moved then
            local cell = self:CellAt(b.x1, b.y1)
            if cell and GC.ship[cell] == slot and GC.Biomes[GC.biome[cell]].water then
                if b.add and GC.selShip[cell] then GC.selShip[cell] = nil else GC.selShip[cell] = true end
                return
            end
            local A = cell and GC.army[cell]
            if A and A.owner == slot and A.id then
                if b.add and GC.sel[A.id] then GC.sel[A.id] = nil else GC.sel[A.id] = true end
            end
            return
        end
        local cs = self:CellSize()
        local lx, hx = math.min(b.x0, b.x1), math.max(b.x0, b.x1)
        local ly, hy = math.min(b.y0, b.y1), math.max(b.y0, b.y1)
        local function In(cell)
            local cx, cy = (cell - 1) % GCW, math.floor((cell - 1) / GCW)
            local px, py = self.ox + (cx + 0.5) * cs, self.oy + (cy + 0.5) * cs
            return px >= lx and px <= hx and py >= ly and py <= hy
        end
        for cell, A in pairs(GC.army) do
            if A.owner == slot and A.id and not GC.Biomes[GC.biome[cell]].water and In(cell) then GC.sel[A.id] = true end
        end
        for cell, owner in pairs(GC.ship) do if owner == slot and In(cell) then GC.selShip[cell] = true end end
    end

    function map:OnMouseReleased()
        if self.box then
            local b = self.box
            self.box = nil
            self:FinishSelect(b)
            self:MouseCapture(false)
        end
        if self.drag then
            self.drag = nil
            self:MouseCapture(false)
        end
    end

    function map:OnCursorMoved(x, y)
        if self.box then self.box.x1, self.box.y1 = x, y end
        if self.drag then
            self.tox = self.drag.ox + (x - self.drag.mx)
            self.toy = self.drag.oy + (y - self.drag.my)
            self:ClampTarget()
        end
    end

    function map:OpenMenu()
        if GC.winner then return end
        local i = self:CellAt(self:CursorPos())
        local slot = GC.mySlot
        if not i then return end
        if not slot then
            local A0 = GC.army[i]
            local o0 = GC.owner[i]
            if o0 == 0 then o0 = (A0 and A0.owner) or GC.ship[i] end
            if o0 and o0 ~= 0 then GC.OpenCountryInfo(o0) end
            return
        end
        if GC.fog and not GC.vis[i] then return end

        local me = GC.players[slot]
        local menu = DermaMenu()
        StyleMenu(menu)
        local added = 0

        local function Add(act, fn)
            local a = GC.Actions[act]
            local cost = {}
            if a.coins then cost[#cost + 1] = a.coins .. " coins" end
            if a.pop then cost[#cost + 1] = a.pop .. " pop" end
            if a.weapons then cost[#cost + 1] = a.weapons .. " weapons" end
            local label = a.name .. (#cost > 0 and (" (" .. table.concat(cost, ", ") .. ")") or "")
            local opt = menu:AddOption(label, fn or function() SendAct(i, act) end)
            opt:SetIcon(a.icon)
            if (a.coins and me.coins < a.coins) or (a.pop and me.pop < a.pop) or (a.weapons and me.weapons < a.weapons) then
                opt:SetEnabled(false)
            end
            if a.build == GC.B_AIR and not GC.AirbaseUnlocked() then
                opt:SetEnabled(false)
                opt:SetTooltip("Unlocks on day " .. GC.AirbaseMinDay)
            end
            added = added + 1
            return opt
        end

        local sels = GC.SelectedArmies()
        if #sels > 0 then
            local sub, so = menu:AddSubMenu("Selected armies (" .. #sels .. ")")
            so:SetIcon("gcapture/gc_ui_pop.png")
            sub:AddOption("Move here", function() GC.GroupMove(i) end):SetIcon("gcapture/gc_act_red.png")
            sub:AddOption("Go To Border", function() GC.GroupBorder() end):SetIcon("gcapture/gc_act_green.png")
            sub:AddOption("Auto Attack", function() GC.GroupAuto() end):SetIcon("gcapture/gc_act_red.png")
            sub:AddOption("Stop", function() GC.GroupStop() end):SetIcon("gcapture/gc_act_black.png")
            sub:AddOption("Delete Selected", function()
                Derma_Query("Delete selected armies?", "Delete Armies", "Delete", function() GC.GroupDelete() end, "Cancel")
            end):SetIcon("gcapture/gc_act_black.png")
            sub:AddOption("Clear Selection", function() GC.sel = {} end):SetIcon("icon16/cross.png")
            added = added + 1
        end

        local ships = GC.SelectedShips()
        if #ships > 0 then
            local sub, so = menu:AddSubMenu("Selected ships (" .. #ships .. ")")
            so:SetIcon("gcapture/gc_ship.png")
            sub:AddOption("Move here", function() GC.ShipGroupMove(i) end):SetIcon("gcapture/gc_act_blue.png")
            sub:AddOption("Stop", function() GC.ShipGroupStop() end):SetIcon("gcapture/gc_act_black.png")
            sub:AddOption("Clear Selection", function() GC.selShip = {} end):SetIcon("icon16/cross.png")
            added = added + 1
        end

        local A = GC.army[i]
        if A and A.owner == slot then
            if A.state == GC.ST_IDLE then
                if A.trainEnd and CurTime() < A.trainEnd then
                    local o = menu:AddOption(string.format("Training (%d s)", math.ceil(A.trainEnd - CurTime())))
                    o:SetIcon("icon16/clock.png")
                    o:SetEnabled(false)
                    added = added + 1
                elseif GC.Biomes[GC.biome[i]].water then

                    Add(18, function() GC.pick = { from = i, act = 18 } end)
                else
                    Add(14, function() GC.pick = { from = i, act = 14 } end)
                    Add(22)
                    if A.auto then Add(23) else Add(30) end
                end
            elseif A.state == GC.ST_ATTACK then
                Add(16)
            elseif A.state == GC.ST_BORDER then
                Add(23)
            else
                Add(17)
            end
            Add(24, function()
                Derma_Query("Delete this army? No refund.", "Delete Army", "Delete", function() SendAct(i, 24) end, "Cancel")
            end)
        end

        if GC.Biomes[GC.biome[i]].water then
            local sh = GC.ship[i]
            if sh == slot then
                if GC.HasLandNeighbor(i) and not GC.army[i] then Add(10) end
                Add(11, function()
                    GC.selShip = GC.selShip or {}
                    GC.selShip[i] = true
                    LocalMsg("Ship selected. Right-click a destination.")
                end)
            elseif sh ~= 0 then
                if GC.CoastGuardNear(i, slot) and not GC.HasPact(slot, sh) then Add(12) end
            elseif GC.HasNeighbor(GC.owner, i, slot) then
                Add(9)
            end
        else
            local o, bl = GC.owner[i], GC.build[i]
            if o == 0 then
                if GC.HasNeighbor(GC.owner, i, slot, GC.ship) and (not A or A.owner == slot) then Add(1) end
            elseif o == slot then
                local conn = GC.CanBuildAt(slot, i)
                if bl == 0 then
                    if conn then
                        Add(2) Add(3) Add(19) Add(26) Add(27) Add(5) Add(8)
                        if GC.biome[i] == GC.DESERT and not GC.oilUsed[i] then Add(6) end
                        if GC.IsCoast(i) then Add(7) end
                    else
                        local cut = menu:AddOption("Can't build here (cut off from the capital)")
                        cut:SetIcon("icon16/error.png")
                        cut:SetEnabled(false)
                        added = added + 1
                    end
                elseif bl == GC.B_CHEST then
                    Add(21)
                elseif bl == GC.B_BARRICADE then
                    local lvl = GC.blevel[i] or 1
                    if conn and lvl < GC.BarricadeMaxLevel then
                        local cost = GC.BarricadeUpgrade[lvl]
                        local up = menu:AddOption("Upgrade Fortress to Lv " .. (lvl + 1) .. " (" .. cost .. " coins)", function() SendAct(i, 29) end)
                        up:SetIcon("gcapture/gc_act_purple.png")
                        if me.coins < cost then up:SetEnabled(false) end
                        added = added + 1
                    end
                end
                if conn and GC.CanSpawnArmy(slot, i, false) then Add(13) end
                if conn and GC.CanSpawnArmy(slot, i, true) then Add(28) end
                if bl ~= 0 and bl ~= GC.B_CAPITAL and bl ~= GC.B_FIRE and bl ~= GC.B_CRATER then
                    Add(25, function()
                        Derma_Query("Delete this structure?", "Delete Structure", "Delete", function() SendAct(i, 25) end, "Cancel")
                    end)
                end
            else

                local pact = GC.HasPact(slot, o)
                local hasTarget = (bl ~= 0 and bl ~= GC.B_FIRE and bl ~= GC.B_CRATER) or (A and A.owner ~= slot)
                if hasTarget and not pact and not GC.AccessTie(slot, o) and GC.AirbaseNear(i, slot) then Add(20) end

                local sub, subOpt = menu:AddSubMenu("Diplomacy")
                subOpt:SetIcon("gcapture/gc_act_purple.png")
                local po = sub:AddOption(pact and "Non-Aggression Pact (active)" or ("Propose Pact (" .. GC.PactTime .. " sec)"), function() SendDiplo(1, o) end)
                po:SetIcon("gcapture/gc_act_green.png")
                if pact then po:SetEnabled(false) end
                sub:AddOption("Send Letter", function() GC.OpenLetter(o) end):SetIcon("gcapture/gc_act_blue.png")
                sub:AddOption("Donate", function() GC.OpenDonate(o) end):SetIcon("gcapture/gc_act_brown.png")
                if GC.access[slot * 256 + o] then
                    sub:AddOption("Revoke Military Access", function() SendDiplo(6, o) end):SetIcon("gcapture/gc_act_red.png")
                else
                    sub:AddOption("Allow Military Access", function() SendDiplo(5, o) end):SetIcon("gcapture/gc_act_red.png")
                end
                local theirs = GC.access[o * 256 + slot]
                local rq = sub:AddOption(theirs and "Military Access (granted to you)" or "Request Military Access",
                    function() SendDiplo(7, o) end)
                rq:SetIcon("gcapture/gc_act_red.png")
                if theirs then rq:SetEnabled(false) end
                local sev = GC.muted[slot * 256 + o]
                sub:AddOption(sev and "Restore Relations" or "Sever Relations", function() SendDiplo(9, o) end)
                    :SetIcon(sev and "gcapture/gc_act_black.png" or "gcapture/gc_act_black.png")
                added = added + 1
            end
        end

        GC.Mods.PopulateMenu(menu, i, slot, Add, A)

        if added == 0 then menu:Remove() return end
        menu:Open()
    end

    function map:Paint(w, h)
        surface.SetDrawColor(6, 10, 8)
        surface.DrawRect(0, 0, w, h)
        if not GC.runs then return end
        if GC.focusPending and CurTime() >= (GC.focusAt or 0) and w > 200 then
            GC.focusPending = nil
            local cap
            if GC.mySlot then
                for i = 1, GCN do
                    if GC.owner[i] == GC.mySlot and GC.build[i] == GC.B_CAPITAL then cap = i break end
                end
            end
            if cap then self:FocusCell(cap) else
                self.zoom, self.ox, self.oy = 1, 0, 0
                self.tz, self.tox, self.toy = 1, 0, 0
            end
        end

        self:ClampTarget()
        local sk = 1 - math.exp(-14 * FrameTime())
        self.zoom = self.zoom + (self.tz - self.zoom) * sk
        self.ox = self.ox + (self.tox - self.ox) * sk
        self.oy = self.oy + (self.toy - self.oy) * sk
        if math.abs(self.tz - self.zoom) < 0.0005 then self.zoom = self.tz end
        GC.nightA = math.Approach(GC.nightA, GC.NightAmount(CurTime() + GC.dayOffset), FrameTime() * 0.4)
        if not GC.clouds then MakeClouds() end

        self:ClampPan()
        local cs, ox, oy = self:CellSize(), self.ox, self.oy
        local floor = math.floor
        local fancy = GC.cvWater:GetBool()
        GC.fxWater = fancy
        local bA = 255 * GC.cvBuildAlpha:GetFloat()
        local uA = 255 * GC.cvUnitAlpha:GetFloat()
        local y0, y1 = math.max(0, floor(-oy / cs)), math.min(GCH - 1, floor((h - oy) / cs))
        local x0, x1 = math.max(0, floor(-ox / cs)), math.min(GCW - 1, floor((w - ox) / cs))

        for y = y0, y1 do
            local py = floor(oy + y * cs)
            local ph = floor(oy + (y + 1) * cs) - py
            for _, r in ipairs(GC.runs[y]) do
                local sx, len = r[1], r[2]
                if sx + len - 1 >= x0 and sx <= x1 then
                    local px = floor(ox + sx * cs)
                    local pw = floor(ox + (sx + len) * cs) - px
                    local c = (GC.Biomes[r[3]] or GC.Biomes[0]).color
                    surface.SetDrawColor(c.r, c.g, c.b, 255)
                    surface.DrawRect(px, py, pw, ph)
                end
            end
        end

        if fancy and cs >= 10 then
            local t = CurTime()
            for y = y0, y1 do
                local py = floor(oy + y * cs)
                local ph = floor(oy + (y + 1) * cs) - py
                for x = x0, x1 do
                    if GC.biome[y * GCW + x + 1] == GC.WATER then
                        local px = floor(ox + x * cs)
                        surface.SetDrawColor(120, 190, 255, 10 + 9 * math.sin(t * 1.2 + x * 0.7 + y * 0.5))
                        surface.DrawRect(px, py, floor(ox + (x + 1) * cs) - px, ph)
                    end
                end
            end
        end

        do
            local key = GCW * 100003 + GCH
            if GC.shadeKey ~= key then GC.shade, GC.shadeKey = {}, key end
            local sh, bm, t = GC.shade, GC.biome, CurTime()
            if cs >= 4 then
                for y = y0, y1 do
                    local py = floor(oy + y * cs)
                    local ph = floor(oy + (y + 1) * cs) - py
                    for x = x0, x1 do
                        local i = y * GCW + x + 1
                        local b = bm[i]
                        if b and b ~= 0 and (fancy or b ~= GC.WATER) then
                            local sv = sh[i]
                            if not sv then
                                local n = math.sin(x * 0.45 + math.sin(y * 0.31) * 2.1) * math.sin(y * 0.38 + math.cos(x * 0.27) * 1.7)
                                local hh = (math.sin(i * 12.9898) * 43758.5453) % 1
                                sv = n * 0.6 + (hh - 0.5) * 0.9
                                sh[i] = sv
                            end
                            local px = floor(ox + x * cs)
                            local pw = floor(ox + (x + 1) * cs) - px
                            if sv > 0 then surface.SetDrawColor(255, 255, 235, sv * 26)
                            else surface.SetDrawColor(0, 0, 10, -sv * 34) end
                            surface.DrawRect(px, py, pw, ph)
                            if b ~= GC.WATER then
                                if cs >= 10 then
                                    local r = (math.sin(i * 78.233) * 12543.17) % 1
                                    if b == GC.FOREST then
                                        local d = math.max(2, floor(pw * 0.22))
                                        local d1x, d1y = floor(px + pw * (0.12 + r * 0.45)), floor(py + ph * 0.18)
                                        local d2x, d2y = floor(px + pw * (0.55 - r * 0.2)), floor(py + ph * 0.55)
                                        if cs >= 26 then
                                            draw.RoundedBox(floor(d / 2), d1x, d1y, d, d, COL_TREE)
                                            draw.RoundedBox(floor(d / 2), d2x, d2y, d, d, COL_TREE)
                                        else
                                            surface.SetDrawColor(6, 40, 18, 55)
                                            surface.DrawRect(d1x, d1y, d, d)
                                            surface.DrawRect(d2x, d2y, d, d)
                                        end
                                    elseif b == GC.DESERT then
                                        surface.SetDrawColor(255, 240, 170, 55)
                                        surface.DrawRect(px + pw * 0.1, py + ph * (0.3 + r * 0.4), pw * 0.8, math.max(1, floor(ph * 0.06)))
                                    elseif b == GC.TUNDRA then
                                        surface.SetDrawColor(255, 255, 255, 40 + 120 * math.max(0, math.sin(t * 2 + i)))
                                        surface.DrawRect(px + pw * r * 0.8, py + ph * (1 - r) * 0.8, 2, 2)
                                    end
                                end
                                if fancy and cs >= 10 then
                                    local foam = 70 + 35 * math.sin(t * 2 + x * 0.6 + y * 0.4)
                                    local e = math.max(1, floor(cs * 0.07))
                                    surface.SetDrawColor(235, 250, 255, foam)
                                    if x > 0 and bm[i - 1] == GC.WATER then surface.DrawRect(px, py, e, ph) end
                                    if x < GCW - 1 and bm[i + 1] == GC.WATER then surface.DrawRect(px + pw - e, py, e, ph) end
                                    if y > 0 and bm[i - GCW] == GC.WATER then surface.DrawRect(px, py, pw, e) end
                                    if y < GCH - 1 and bm[i + GCW] == GC.WATER then surface.DrawRect(px, py + ph - e, pw, e) end
                                end
                            end
                        end
                    end
                end
            end
        end

        if cs >= 8 then
            local bm, t = GC.biome, CurTime()
            for y = y0, y1 do
                local py = floor(oy + y * cs)
                local ph = floor(oy + (y + 1) * cs) - py
                for x = x0, x1 do
                    local i = y * GCW + x + 1
                    local b = bm[i]
                    if b and b ~= 0 then
                        local px = floor(ox + x * cs)
                        local pw = floor(ox + (x + 1) * cs) - px
                        if x > 0 then Blend(bm, b, i - 1, 1, px, py, pw, ph) end
                        if x < GCW - 1 then Blend(bm, b, i + 1, 2, px, py, pw, ph) end
                        if y > 0 then Blend(bm, b, i - GCW, 3, px, py, pw, ph) end
                        if y < GCH - 1 then Blend(bm, b, i + GCW, 4, px, py, pw, ph) end

                        if fancy and b == GC.WATER and cs >= 12 then
                            local r = (math.sin(i * 12.9898) * 43758.5453) % 1
                            local sp = math.max(0, math.sin(t * 1.4 + r * 40)) ^ 10
                            if sp > 0.05 then
                                surface.SetDrawColor(255, 255, 255, 170 * sp)
                                surface.DrawRect(px + pw * (0.15 + r * 0.7), py + ph * (0.2 + ((r * 7) % 1) * 0.6), 2, 2)
                            end
                        end
                    end
                end
            end
        end

        local owner, build, ship, army, players = GC.owner, GC.build, GC.ship, GC.army, GC.players
        local fog, vis, known = GC.fog, GC.vis, GC.known
        local now = CurTime()
        local bt = math.max(1, floor(cs * 0.07))
        for y = y0, y1 do
            local py = floor(oy + y * cs)
            local ph = floor(oy + (y + 1) * cs) - py
            for x = x0, x1 do
                local i = y * GCW + x + 1
                local o, bl, sh, A = owner[i], build[i], ship[i], army[i]
                if o ~= 0 or bl ~= 0 or sh ~= 0 or A then
                    local px = floor(ox + x * cs)
                    local pw = floor(ox + (x + 1) * cs) - px
                    local P = players[o]
                    if P then
                        surface.SetDrawColor(P.color.r, P.color.g, P.color.b, OWNER_ALPHA)
                        surface.DrawRect(px, py, pw, ph)
                    end

                    if o ~= 0 then
                        local shadow = cs >= 6
                        local sw = math.max(2, floor(cs * 0.14))
                        if x == 0 or owner[i - 1] ~= o then
                            if shadow then EdgeShadow(px, py, pw, ph, 1, bt, sw) end
                            surface.SetDrawColor(0, 0, 0, 255)
                            surface.DrawRect(px, py, bt, ph)
                        end
                        if x == GCW - 1 or owner[i + 1] ~= o then
                            if shadow then EdgeShadow(px, py, pw, ph, 2, bt, sw) end
                            surface.SetDrawColor(0, 0, 0, 255)
                            surface.DrawRect(px + pw - bt, py, bt, ph)
                        end
                        if y == 0 or owner[i - GCW] ~= o then
                            if shadow then EdgeShadow(px, py, pw, ph, 3, bt, sw) end
                            surface.SetDrawColor(0, 0, 0, 255)
                            surface.DrawRect(px, py, pw, bt)
                        end
                        if y == GCH - 1 or owner[i + GCW] ~= o then
                            if shadow then EdgeShadow(px, py, pw, ph, 4, bt, sw) end
                            surface.SetDrawColor(0, 0, 0, 255)
                            surface.DrawRect(px, py + ph - bt, pw, bt)
                        end
                    end

                    if bl ~= 0 and mats[bl] then

                        local bsc, bs0 = 1, GC.bSpawn[i]
                        if bs0 then
                            local a = (now - bs0) / 0.3
                            if a >= 1 then GC.bSpawn[i] = nil else bsc = 0.12 + 0.88 * (1 - (1 - a) ^ 3) end
                        end
                        surface.SetDrawColor(255, 255, 255, bA)
                        surface.SetMaterial(mats[bl])
                        DrawScaled(px, py, pw, ph, bsc)
                    end
                    if bl == GC.B_FIRE then
                        surface.SetDrawColor(255, 120, 20, 45 + 35 * math.sin(now * 12 + i))
                        surface.DrawRect(px, py, pw, ph)
                    elseif bl == GC.B_CAPITAL and P then
                        surface.SetDrawColor(P.color.r, P.color.g, P.color.b, 140 + 100 * math.sin(now * 2.5))
                        surface.DrawOutlinedRect(px + 1, py + 1, pw - 2, ph - 2, 2)
                    end
                    if bl == GC.B_AIR then
                        local readyAt = GC.airCdClient and GC.airCdClient[i] or 0
                        local frac = math.Clamp((readyAt - now) / GC.AirCooldown, 0, 1)
                        local bh = math.max(2, floor(ph * 0.07))
                        local m = pw >= 10 and 1 or 0
                        DrawBar(px + m, py + ph - bh - m, pw - m * 2, bh, 1 - frac, 80, 190, 255)
                    end
                    if bl == GC.B_BARRICADE then

                        local lv = GC.blevel[i] or 1
                        local pp = math.max(2, floor(pw * 0.14))
                        surface.SetDrawColor(0, 0, 0, 220)
                        surface.DrawRect(px + pw - lv * (pp + 1) - 1, py, lv * (pp + 1) + 1, pp + 2)
                        surface.SetDrawColor(255, 220, 60, 255)
                        for k = 1, lv do surface.DrawRect(px + pw - k * (pp + 1), py + 1, pp, pp) end
                    end
                    if sh ~= 0 then
                        local SP = players[sh]
                        DrawTintIcon(matShip, px, py, pw, ph, 1, SP and SP.color, uA)
                    end

                    if A then

                        local offx, offy = 0, 0
                        local orgFlash = GC.orgFlashes and GC.orgFlashes[i]
                        if orgFlash then
                            local age = now - orgFlash
                            if age > 0.45 then
                                GC.orgFlashes[i] = nil
                            else
                                local strength = 1 - age / 0.45
                                offx = math.sin(now * 75) * pw * 0.07 * strength
                                offy = math.cos(now * 83) * ph * 0.07 * strength
                                surface.SetDrawColor(255, 20, 20, 150 * strength)
                                surface.DrawRect(px, py, pw, ph)
                            end
                        end
                        if A.state == GC.ST_ATTACK and A.target ~= 0 then
                            local tx, ty = (A.target - 1) % GCW, floor((A.target - 1) / GCW)
                            offx = (tx > x and 1 or (tx < x and -1 or 0)) * pw * 0.22
                            offy = (ty > y and 1 or (ty < y and -1 or 0)) * ph * 0.22
                        end

                        local training = A.trainEnd and now < A.trainEnd
                        local sc, spAt = 1, GC.armySpawn[A.id]
                        if spAt then
                            if now - spAt >= 0.4 then GC.armySpawn[A.id] = nil else sc = EaseBack((now - spAt) / 0.4) end
                        end

                        local AP = players[A.owner]
                        local acol, aa = AP and AP.color, (training and 130 or 255) * uA / 255
                        local icon = A.cav and matCav or matArmy
                        if GC.Biomes[GC.biome[i]].water then
                            DrawTintIcon(icon, px + pw - floor(pw * 0.5) + offx, py + offy, pw * 0.5, ph * 0.5, sc, acol, aa)
                        else
                            DrawTintIcon(icon, px + pw * 0.125 + offx, py + ph * 0.125 + offy, pw * 0.75, ph * 0.75, sc, acol, aa)
                        end

                        local barA = 255 * GC.cvBarAlpha:GetFloat() * (uA / 255)
                        if barA > 1 then
                            local bh = math.max(2, floor(ph * 0.07))
                            local m = pw >= 10 and 1 or 0
                            local bw_ = pw - m * 2
                            DrawBar(px + m, py + ph - bh * 2 - m - 1, bw_, bh, A.hp / math.max(1, A.maxHp), 235, 70, 70, barA)
                            DrawBar(px + m, py + ph - bh - m, bw_, bh, A.org / math.max(1, A.maxOrg), 90, 150, 255, barA)
                            if training then
                                local frac = math.Clamp((A.trainEnd - now) / GC.Combat.TrainTime, 0, 1)
                                DrawBar(px + m, py + m, bw_, bh, frac, 255, 210, 50, barA)
                            end
                        end

                        if A.state == GC.ST_DEFENSE then
                            surface.SetDrawColor(255, 60, 60, 255)
                            surface.DrawOutlinedRect(px, py, pw, ph)
                        elseif A.state == GC.ST_BORDER then
                            surface.SetDrawColor(80, 210, 255, 255)
                            surface.DrawOutlinedRect(px, py, pw, ph)
                        elseif A.auto then
                            surface.SetDrawColor(255, 90, 220, 255)
                            surface.DrawOutlinedRect(px, py, pw, ph)
                        end
                    end
                end
            end
        end

        do
            local me = GC.mySlot
            local function Tri(tx, ty, bx, by, px_, py_, hw, r, g, b, al)
                local pts = { { x = tx, y = ty }, { x = bx + px_ * hw, y = by + py_ * hw }, { x = bx - px_ * hw, y = by - py_ * hw } }
                local area = 0
                for k = 1, 3 do
                    local p1, p2 = pts[k], pts[k % 3 + 1]
                    area = area + p1.x * p2.y - p2.x * p1.y
                end
                if area < 0 then pts[2], pts[3] = pts[3], pts[2] end
                surface.SetDrawColor(r, g, b, al or 255)
                surface.DrawPoly(pts)
            end
            local function Disc(cx, cy, rad, r_, g_, b_, a_)
                local pts = {}
                for k = 0, 17 do
                    local ang = k / 18 * math.pi * 2
                    pts[#pts + 1] = { x = cx + math.cos(ang) * rad, y = cy + math.sin(ang) * rad }
                end
                surface.SetDrawColor(r_, g_, b_, a_)
                surface.DrawPoly(pts)
            end
            for acell, A in pairs(GC.army) do
                if A.state == GC.ST_ATTACK and A.target ~= 0 then
                    local D = GC.army[A.target]

                    if D and D.owner ~= A.owner and (me == nil or me == A.owner or me == D.owner)
                        and not (D.state == GC.ST_ATTACK and D.target == acell and A.target < acell) then
                        local mine, foe = A, D
                        if me == D.owner then mine, foe = D, A end
                        local ax, ay = (acell - 1) % GCW, floor((acell - 1) / GCW)
                        local dx_, dy_ = (A.target - 1) % GCW, floor((A.target - 1) / GCW)
                        local bx = ox + ((ax + dx_) / 2 + 0.5) * cs
                        local by = oy + ((ay + dy_) / 2 + 0.5) * cs
                        local cr, cg, cb = 255, 215, 40
                        if foe.org < mine.org then cr, cg, cb = 60, 220, 90
                        elseif foe.org > mine.org then cr, cg, cb = 240, 60, 60 end
                        local bAl = 255 * GC.cvBubbleAlpha:GetFloat()
                        if bAl > 1 then
                        local r = math.Clamp(cs * 0.12, 4, 9)
                        local pulse = 0.9 + 0.1 * math.sin(now * 6)
                        draw.NoTexture()

                        local vx, vy = dx_ - ax, dy_ - ay
                        local len = math.sqrt(vx * vx + vy * vy)
                        if len > 0 then
                            vx, vy = vx / len, vy / len
                            local nx, ny = -vy, vx
                            local baseD, tipD, hw = r * 0.5, r * 2.6, r * 0.95
                            Tri(bx + vx * (tipD + 1.5), by + vy * (tipD + 1.5), bx + vx * (baseD - 1), by + vy * (baseD - 1), nx, ny, hw + 1.5, 14, 16, 22, bAl)
                            Tri(bx + vx * tipD, by + vy * tipD, bx + vx * baseD, by + vy * baseD, nx, ny, hw, 255, 255, 255, bAl)
                        end

                        Disc(bx, by, r + 2.5, 14, 16, 22, 235 * bAl / 255)
                        Disc(bx, by, r + 1.2, 245, 246, 250, bAl)
                        Disc(bx, by, r, cr, cg, cb, bAl * pulse)
                        end
                    end
                end
            end
        end

        if cs >= 12 and next(GC.odds) then
            for acell, o in pairs(GC.odds) do
                if now - o.t > 2.2 or not GC.army[acell] then
                    GC.odds[acell] = nil
                else
                    local cell = o.att and o.dcell or acell
                    local cx_, cy_ = (cell - 1) % GCW, floor((cell - 1) / GCW)
                    local tx_ = floor(ox + (cx_ + 1) * cs) - 2
                    local ty_ = floor(oy + cy_ * cs) + 1
                    local col = o.att and Color(120, 200, 255) or Color(255, 120, 110)
                    draw.SimpleTextOutlined(o.pct .. "%", "GCapture.Small", tx_, ty_, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 230))
                end
            end
        end

        for cell, f in pairs(GC.cellFx) do
            local age = now - f.t
            local dur = (f.kind == "build") and 1.0 or 0.7
            if age > dur then
                GC.cellFx[cell] = nil
            else
                local k = 1 - age / dur
                k = k * k * (3 - 2 * k)
                local fx_, fy_ = (cell - 1) % GCW, floor((cell - 1) / GCW)
                local px, py = floor(ox + fx_ * cs), floor(oy + fy_ * cs)
                local pw, ph = floor(ox + (fx_ + 1) * cs) - px, floor(oy + (fy_ + 1) * cs) - py
                if f.kind == "build" then surface.SetDrawColor(255, 255, 255, 235 * k)
                else surface.SetDrawColor(f.r, f.g, f.b, 150 * k) end
                surface.DrawRect(px, py, pw, ph)
                local e = floor(cs * 0.6 * (age / dur))
                surface.SetDrawColor(255, 255, 255, 200 * k)
                surface.DrawOutlinedRect(px - e, py - e, pw + e * 2, ph + e * 2)
            end
        end

        for cell in pairs(GC.selShip or {}) do
            if GC.ship[cell] == GC.mySlot then
                local sx, sy = (cell - 1) % GCW, floor((cell - 1) / GCW)
                local spx, spy = floor(ox + sx * cs), floor(oy + sy * cs)
                surface.SetDrawColor(80, 200, 255, 200 + 55 * math.sin(CurTime() * 6))
                surface.DrawOutlinedRect(spx, spy, floor(ox + (sx + 1) * cs) - spx, floor(oy + (sy + 1) * cs) - spy, 2)
            end
        end

        for cell, ep in pairs(GC.expPend or {}) do
            if now > ep.t1 + 1 then
                GC.expPend[cell] = nil
            else
                local kk = math.Clamp((now - ep.t0) / math.max(0.1, ep.t1 - ep.t0), 0, 1)
                local ex_, ey_ = (cell - 1) % GCW, floor((cell - 1) / GCW)
                local px, py = floor(ox + ex_ * cs), floor(oy + ey_ * cs)
                local pw, ph = floor(ox + (ex_ + 1) * cs) - px, floor(oy + (ey_ + 1) * cs) - py
                surface.SetDrawColor(255, 255, 255, 50 + 30 * math.sin(now * 8))
                surface.DrawRect(px, py + floor(ph * (1 - kk)), pw, math.max(1, floor(ph * kk)))
                surface.SetDrawColor(255, 255, 255, 220)
                surface.DrawOutlinedRect(px, py, pw, ph, 2)
            end
        end

        for cell, g in pairs(GC.bGhost) do
            local age = now - g.t
            if age > 0.5 or not mats[g.b] then
                GC.bGhost[cell] = nil
            else
                local gx, gy = (cell - 1) % GCW, floor((cell - 1) / GCW)
                local px, py = floor(ox + gx * cs), floor(oy + gy * cs)
                local pw, ph = floor(ox + (gx + 1) * cs) - px, floor(oy + (gy + 1) * cs) - py
                local cover = (age < 0.12) and (age / 0.12) or (1 - (age - 0.12) / 0.38)
                surface.SetDrawColor(255, 255, 255, bA * math.Clamp(1 - age / 0.5, 0, 1))
                surface.SetMaterial(mats[g.b])
                surface.DrawTexturedRect(px, py, pw, ph)
                surface.SetDrawColor(0, 0, 0, 235 * math.Clamp(cover, 0, 1))
                surface.DrawRect(px, py, pw, ph)
            end
        end

        for cell, g in pairs(GC.armyGhost) do
            local age = now - g.t
            if age > 0.35 then
                GC.armyGhost[cell] = nil
            else
                local k = 1 - age / 0.35
                local gx, gy = (cell - 1) % GCW, floor((cell - 1) / GCW)
                local px, py = floor(ox + gx * cs), floor(oy + gy * cs)
                local pw = floor(cs)
                local GP = GC.players[g.A.owner]
                DrawTintIcon(g.A.cav and matCav or matArmy, px + pw * 0.125, py + pw * 0.125, pw * 0.75, pw * 0.75, k, GP and GP.color, uA * k)
            end
        end

        do
            local dt, dir = FrameTime(), GC.cloudDir
            local showClouds = GC.cvClouds:GetBool()
            local shadowA = CLOUD_ALPHA * 0.8 + 255 * 0.05
            draw.NoTexture()
            for _, c in ipairs(GC.clouds) do
                c.x = c.x + dir[1] * CLOUD_SPEED * math.max(1, GCW / 32) * c.sp * dt
                c.y = c.y + dir[2] * CLOUD_SPEED * math.max(1, GCW / 32) * c.sp * dt
                local m = c.s + 2
                if c.x > GCW + m then c.x = -m elseif c.x < -m then c.x = GCW + m end
                if c.y > GCH + m then c.y = -m elseif c.y < -m then c.y = GCH + m end
                local poly = {}
                for k, v in ipairs(c.v) do
                    poly[k] = { x = ox + (c.x + v.x * c.s) * cs, y = oy + (c.y + v.y * c.s) * cs }
                end
                local sp = {}
                for k, v in ipairs(poly) do sp[k] = { x = v.x + cs * 1.4, y = v.y + cs * 1.8 } end
                surface.SetDrawColor(0, 0, 0, shadowA)
                surface.DrawPoly(sp)
                if showClouds then
                    surface.SetDrawColor(255, 255, 255, CLOUD_ALPHA)
                    surface.DrawPoly(poly)
                end
            end

            local mx0, my0 = floor(ox), floor(oy)
            local mx1, my1 = floor(ox + GCW * cs), floor(oy + GCH * cs)
            surface.SetDrawColor(6, 10, 8, 255)
            if mx0 > 0 then surface.DrawRect(0, 0, mx0, h) end
            if mx1 < w then surface.DrawRect(mx1, 0, w - mx1, h) end
            if my0 > 0 then surface.DrawRect(0, 0, w, my0) end
            if my1 < h then surface.DrawRect(0, my1, w, h - my1) end
        end

        do
            local wk = math.Clamp((cs - 18) / 22, 0, 1)
            if wk > 0.01 then
                local bm, t = GC.biome, CurTime()
                local sin = math.sin
                local nFlake = cs >= 40 and 7 or 4
                for y = y0, y1 do
                    local py = floor(oy + y * cs)
                    local ph = floor(oy + (y + 1) * cs) - py
                    for x = x0, x1 do
                        local i = y * GCW + x + 1
                        local b = bm[i]
                        if b == GC.TUNDRA or b == GC.DESERT then
                            local px = floor(ox + x * cs)
                            local pw = floor(ox + (x + 1) * cs) - px
                            local pr, pb = px + pw, py + ph
                            if b == GC.TUNDRA then

                                local wave = 0.5 + 0.5 * sin(t * 0.9 + (x + y * 0.5) * 0.8)
                                surface.SetDrawColor(225, 238, 250, wk * (22 + 30 * wave))
                                surface.DrawRect(px, py, pw, ph)
                                for j = 1, nFlake do
                                    local r1 = (sin(i * 12.9898 + j * 78.233) * 43758.5453) % 1
                                    local r2 = (sin(i * 39.346 + j * 11.135) * 24634.6345) % 1
                                    local fx = (r1 + t * 0.45 * (0.5 + r2) + sin(t * 1.3 + r2 * 6.28) * 0.04) % 1
                                    local fy = (r2 * 7 + t * 0.7 * (0.5 + r1)) % 1
                                    local sx, sy = px + fx * pw, py + fy * ph
                                    local sz = math.max(1, floor(cs * 0.04 * (0.6 + r1)))
                                    surface.SetDrawColor(255, 255, 255, wk * (150 + 90 * r2))
                                    surface.DrawRect(floor(sx), floor(sy), sz, sz)
                                    if j <= 2 then
                                        local ex, ey = math.max(px, sx - cs * 0.3), math.max(py, sy - cs * 0.08)
                                        surface.SetDrawColor(245, 250, 255, wk * 110)
                                        surface.DrawLine(sx, sy, ex, ey)
                                    end
                                end
                            else

                                local wave = 0.5 + 0.5 * sin(t * 1.1 + (x + y * 0.4) * 0.8)
                                surface.SetDrawColor(214, 168, 96, wk * (24 + 40 * wave))
                                surface.DrawRect(px, py, pw, ph)
                                for j = 1, nFlake do
                                    local r1 = (sin(i * 12.9898 + j * 78.233) * 43758.5453) % 1
                                    local r2 = (sin(i * 39.346 + j * 11.135) * 24634.6345) % 1
                                    local fx = (r1 + t * 1.1 * (0.6 + r2)) % 1
                                    local fy = (r2 + sin(t * 0.8 + r1 * 6.28) * 0.06 + r1 * 0.3) % 1
                                    local sx, sy = px + fx * pw, py + fy * ph
                                    if j <= 3 then
                                        local ex = math.max(px, sx - cs * (0.25 + 0.2 * r1))
                                        surface.SetDrawColor(236, 206, 140, wk * (70 + 60 * r2))
                                        surface.DrawLine(sx, sy, ex, sy)
                                    else
                                        local sz = math.max(1, floor(cs * 0.03 * (0.6 + r1)))
                                        surface.SetDrawColor(240, 210, 150, wk * 150)
                                        surface.DrawRect(floor(sx), floor(sy), sz, sz)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        if fog then
            local fa = GC.fogA
            local k = math.min(1, FrameTime() * 5)
            for y = y0, y1 do
                local py = floor(oy + y * cs)
                local ph = floor(oy + (y + 1) * cs) - py
                local rs, ra
                for x = x0, x1 + 1 do
                    local a = 0
                    if x <= x1 then
                        local i = y * GCW + x + 1
                        local tgt = vis[i] and 0 or (known[i] and 150 or 255)
                        a = fa[i]
                        if a == nil then
                            a = tgt
                        else
                            a = a + (tgt - a) * k
                            if math.abs(tgt - a) < 0.6 then a = tgt end
                        end
                        fa[i] = a
                        if a <= 1 then a = 0 end
                    end
                    if rs and a ~= ra then
                        local px = floor(ox + rs * cs)
                        surface.SetDrawColor(8, 10, 16, ra)
                        surface.DrawRect(px, py, floor(ox + x * cs) - px, ph)
                        rs = nil
                    end
                    if not rs and a > 0 then rs, ra = x, a end
                end
            end
        elseif next(GC.fogA) then
            GC.fogA = {}
        end

        local na = GC.nightA
        if na < 0.997 then
            local mx0, my0 = math.max(0, floor(ox)), math.max(0, floor(oy))
            local mx1, my1 = math.min(w, floor(ox + GCW * cs)), math.min(h, floor(oy + GCH * cs))
            surface.SetDrawColor(255, 205, 130, 24 * (1 - na))
            surface.DrawRect(mx0, my0, mx1 - mx0, my1 - my0)
        end
        if na > 0.003 then
            if CurTime() > GC.lightT then UpdateLight(); GC.lightT = CurTime() + 0.5 end
            local light = GC.light
            local dk = 185 * na
            for y = y0, y1 do
                local py = floor(oy + y * cs)
                local ph = floor(oy + (y + 1) * cs) - py
                local x = x0
                while x <= x1 do
                    local i = y * GCW + x + 1
                    local l = light[i]
                    if not l then

                        local xe = x
                        while xe < x1 and not light[y * GCW + xe + 2] do xe = xe + 1 end
                        local px = floor(ox + x * cs)
                        surface.SetDrawColor(6, 12, 40, dk)
                        surface.DrawRect(px, py, floor(ox + (xe + 1) * cs) - px, ph)
                        x = xe + 1
                    else
                        local px = floor(ox + x * cs)
                        local pw = floor(ox + (x + 1) * cs) - px
                        surface.SetDrawColor(6, 12, 40, dk * (1 - l * 0.92))
                        surface.DrawRect(px, py, pw, ph)
                        surface.SetDrawColor(170, 205, 255, 32 * l * na)
                        surface.DrawRect(px, py, pw, ph)
                        x = x + 1
                    end
                end
            end
        end

        for cell, t0 in pairs(GC.flashes) do
            local age = CurTime() - t0
            if age > 0.7 then
                GC.flashes[cell] = nil
            else
                local k = 1 - age / 0.7
                local fx, fy = (cell - 1) % GCW, floor((cell - 1) / GCW)
                local cx, cy = ox + (fx + 0.5) * cs, oy + (fy + 0.5) * cs
                local grow = cs * (1 + (1 - k) * 2)
                surface.SetDrawColor(255, 170, 50, 200 * k)
                surface.DrawRect(floor(cx - grow / 2), floor(cy - grow / 2), floor(grow), floor(grow))
                surface.SetDrawColor(255, 255, 255, 230 * k)
                surface.DrawRect(floor(cx - cs / 2), floor(cy - cs / 2), floor(cs), floor(cs))
            end
        end
        local boomAge = CurTime() - GC.lastBoom
        if boomAge < 0.25 then
            surface.SetDrawColor(255, 240, 200, 90 * (1 - boomAge / 0.25))
            surface.DrawRect(0, 0, w, h)
        end

        for cell, A in pairs(army) do
            if A.id and A.owner == GC.mySlot and GC.sel[A.id] then
                local sx, sy = (cell - 1) % GCW, floor((cell - 1) / GCW)
                local spx, spy = floor(ox + sx * cs), floor(oy + sy * cs)
                surface.SetDrawColor(80, 255, 120, 255)
                surface.DrawOutlinedRect(spx, spy, floor(ox + (sx + 1) * cs) - spx, floor(oy + (sy + 1) * cs) - spy, 2)
            end
        end
        if self.box then
            local b = self.box
            local bx, by = math.min(b.x0, b.x1), math.min(b.y0, b.y1)
            local bw, bh = math.abs(b.x1 - b.x0), math.abs(b.y1 - b.y0)
            surface.SetDrawColor(80, 255, 120, 40)
            surface.DrawRect(bx, by, bw, bh)
            surface.SetDrawColor(80, 255, 120, 220)
            surface.DrawOutlinedRect(bx, by, bw, bh)
        end

        local pk = GC.pick
        if pk then
            surface.SetDrawColor(255, 230, 80, 255)
            local fx, fy = (pk.from - 1) % GCW, floor((pk.from - 1) / GCW)
            local fpx, fpy = floor(ox + fx * cs), floor(oy + fy * cs)
            surface.DrawOutlinedRect(fpx, fpy, floor(ox + (fx + 1) * cs) - fpx, floor(oy + (fy + 1) * cs) - fpy)
            for _, j in ipairs(PickCandidates(pk)) do
                local jx, jy = (j - 1) % GCW, floor((j - 1) / GCW)
                local px, py = floor(ox + jx * cs), floor(oy + jy * cs)
                surface.SetDrawColor(255, 230, 80, 90)
                surface.DrawRect(px, py, floor(ox + (jx + 1) * cs) - px, floor(oy + (jy + 1) * cs) - py)
            end
            draw.SimpleTextOutlined(PICK_HINTS[pk.act] or "", "GCapture.Stat", w / 2, 8, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
        end

        if (self:IsHovered() or self.drag) and not GC.winner then
            local mx, my = self:CursorPos()
            local i = self:CellAt(mx, my)
            if i then
                local x, y = (i - 1) % GCW, floor((i - 1) / GCW)
                local px, py = floor(ox + x * cs), floor(oy + y * cs)

                local hb = GC.build[i]
                if GC.mySlot and GC.owner[i] == GC.mySlot and (hb == GC.B_AIR or hb == GC.B_COAST) then
                    local R = (hb == GC.B_AIR) and GC.AirRange(GC.mySlot) or GC.CoastRange(GC.mySlot)
                    local fr, fg, fb = 255, 170, 60
                    if hb == GC.B_COAST then fr, fg, fb = 80, 200, 255 end
                    for yy = math.max(0, y - R), math.min(GCH - 1, y + R) do
                        local xa, xb
                        for xx = math.max(0, x - R), math.min(GCW - 1, x + R) do
                            if hb == GC.B_AIR or (xx - x) ^ 2 + (yy - y) ^ 2 <= R * R then
                                xa = xa or xx
                                xb = xx
                            end
                        end
                        if xa then
                            local rx = floor(ox + xa * cs)
                            local ry = floor(oy + yy * cs)
                            surface.SetDrawColor(fr, fg, fb, 45)
                            surface.DrawRect(rx, ry, floor(ox + (xb + 1) * cs) - rx, floor(oy + (yy + 1) * cs) - ry)
                        end
                    end
                    surface.SetDrawColor(fr, fg, fb, 230)
                    if hb == GC.B_AIR then
                        local rx0, ry0 = floor(ox + (x - R) * cs), floor(oy + (y - R) * cs)
                        surface.DrawOutlinedRect(rx0, ry0, floor((2 * R + 1) * cs), floor((2 * R + 1) * cs), 2)
                    else
                        local ccx, ccy, rr = ox + (x + 0.5) * cs, oy + (y + 0.5) * cs, (R + 0.5) * cs
                        local px0, py0 = ccx + rr, ccy
                        for k = 1, 48 do
                            local ang = k / 48 * math.pi * 2
                            local nx, ny = ccx + math.cos(ang) * rr, ccy + math.sin(ang) * rr
                            surface.DrawLine(px0, py0, nx, ny)
                            px0, py0 = nx, ny
                        end
                    end
                end

                surface.SetDrawColor(255, 255, 255, 220)
                surface.DrawOutlinedRect(px, py, floor(ox + (x + 1) * cs) - px, floor(oy + (y + 1) * cs) - py)

                local lines
                if not known[i] then
                    lines = { "Unknown" }
                else
                    local seen = (not fog) or vis[i]
                    local b = GC.Biomes[GC.biome[i]] or GC.Biomes[0]
                    lines = { "Biome: " .. b.name }
                    if not b.water then
                        local P = players[owner[i]]
                        lines[#lines + 1] = "Owner: " .. (P and P.name or "Nobody")
                        if GC.HasAccess(GC.mySlot or 0, owner[i]) then lines[#lines + 1] = "Military access: allowed" end
                        if build[i] ~= 0 then lines[#lines + 1] = "Structure: " .. (GC.Build[build[i]] and GC.Build[build[i]].name or "Unknown (missing submod?)") .. (build[i] == GC.B_BARRICADE and (" (Lv " .. (GC.blevel[i] or 1) .. ")") or "") end
                        if GC.biome[i] == GC.DESERT and GC.oilUsed[i] and build[i] ~= GC.B_OIL then lines[#lines + 1] = "Oil: depleted" end
                    elseif seen then
                        local S = players[ship[i]]
                        lines[#lines + 1] = S and ("Ship: " .. S.name) or "No ship"
                    end
                    local A = army[i]
                    if A then
                        local AP = players[A.owner]
                        lines[#lines + 1] = (A.cav and "Cavalry" or "Army") .. (b.water and " aboard: " or ": ") .. (AP and AP.name or "?")
                        lines[#lines + 1] = string.format("Organization: %d/%d   HP: %d/%d", A.org, A.maxOrg, A.hp, A.maxHp)
                        if A.owner == GC.mySlot then lines[#lines + 1] = string.format("Upkeep: %.2f coins/sec", GC.UpkeepPerArmy(A.owner, A.cav)) end
                        if A.trainEnd and now < A.trainEnd then
                            lines[#lines + 1] = string.format("State: Training (%d s)", math.ceil(A.trainEnd - now))
                        elseif A.state == GC.ST_ATTACK then lines[#lines + 1] = "State: Attacking"
                        elseif A.state == GC.ST_DEFENSE then lines[#lines + 1] = "State: Defending"
                        elseif A.state == GC.ST_BORDER then lines[#lines + 1] = "State: Going to border"
                        elseif A.auto then lines[#lines + 1] = "State: Auto Attack" end
                    end
                    if not seen then lines[#lines + 1] = "Out of sight (last known)" end
                end

                surface.SetFont("GCapture.Small")
                local tw = 0
                for _, l in ipairs(lines) do tw = math.max(tw, (surface.GetTextSize(l))) end
                local bw, bh = tw + 14, #lines * 16 + 10
                local tx, ty = math.min(mx + 16, w - bw - 2), math.min(my + 16, h - bh - 2)
                draw.RoundedBox(4, tx, ty, bw, bh, Color(15, 17, 22, 235))
                for k, l in ipairs(lines) do
                    draw.SimpleText(l, "GCapture.Small", tx + 7, ty + 5 + (k - 1) * 16, color_white)
                end
            end
        end

        do
            local ax0, ay0 = math.max(0, floor(ox)), math.max(0, floor(oy))
            local ax1, ay1 = math.min(w, floor(ox + GCW * cs)), math.min(h, floor(oy + GCH * cs))
            for k = 0, 11 do
                local fr = 1 - k / 12
                surface.SetDrawColor(255, 240, 200, 16 * fr * fr)
                surface.DrawRect(ax0, ay0 + k * math.max(1, floor((ay1 - ay0) / 40)), ax1 - ax0, math.max(1, floor((ay1 - ay0) / 40)))
                surface.SetDrawColor(0, 0, 20, 22 * fr * fr)
                surface.DrawRect(ax0, ay1 - (k + 1) * math.max(1, floor((ay1 - ay0) / 40)), ax1 - ax0, math.max(1, floor((ay1 - ay0) / 40)))
            end
            for k = 0, 9 do
                surface.SetDrawColor(0, 0, 0, 70 * (1 - k / 10) ^ 2)
                local d = k * 6
                surface.DrawRect(ax0, ay0 + d, ax1 - ax0, 6)
                surface.DrawRect(ax0, ay1 - d - 6, ax1 - ax0, 6)
                surface.DrawRect(ax0 + d, ay0, 6, ay1 - ay0)
                surface.DrawRect(ax1 - d - 6, ay0, 6, ay1 - ay0)
            end
        end

        if GC.winner then
            surface.SetDrawColor(0, 0, 0, 170)
            surface.DrawRect(0, 0, w, h)
            if GC.winner.none then
                draw.SimpleText("Game over", "GCapture.Huge", w / 2, h / 2 - 20, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText("Winner", "GCapture.Big", w / 2, h / 2 - 50, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText(GC.winner.name, "GCapture.Huge", w / 2, h / 2, GC.winner.color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            draw.SimpleText("Back to the lobby soon...", "GCapture.Stat", w / 2, h / 2 + 50, Color(200, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    function map:PaintOver(w, h)

        if GC.runs then
            local vm = GC.GetVignetteMat()
            if vm then
                surface.SetMaterial(vm)
                surface.SetDrawColor(255, 255, 255, 255)
                surface.DrawTexturedRect(0, 0, w, h)
            end
        end
        local now, shown = CurTime(), {}
        for k = #GC.Msgs, 1, -1 do
            local m = GC.Msgs[k]
            if now - m.t < 8 then shown[#shown + 1] = m end
            if #shown >= 6 then break end
        end
        surface.SetFont("GCapture.Small")
        local y = h - 10
        for _, m in ipairs(shown) do
            local age = now - m.t
            local alpha = age > 6 and math.Clamp(255 * (8 - age) / 2, 0, 255) or 255
            local tw, th = surface.GetTextSize(m.text)
            y = y - th - 8
            draw.RoundedBox(4, 10, y, tw + 16, th + 6, Color(15, 18, 24, alpha * 0.85))
            draw.SimpleText(m.text, "GCapture.Small", 18, y + 3, Color(235, 235, 235, alpha))
        end
                local day = math.floor(GC.CycleNow() / GC.CycleLen) + 1
                local txt = "Day " .. day
                local pen = GC.NightAtk()
                surface.SetFont("GCapture.Stat")
                local tw = surface.GetTextSize(txt)
                draw.RoundedBox(6, w - tw - 24, 8, tw + 16, 28, TH.accentDim)
                draw.RoundedBox(6, w - tw - 23, 9, tw + 14, 26, Color(8, 14, 10, 230))
                draw.SimpleText(txt, "GCapture.Stat", w - tw - 16, 12, pen < -0.005 and Color(150, 170, 255) or TH.text)

        local fl = GC.screenFlash
        if fl then
            local a = 1 - (CurTime() - fl.t) / 1.6
            if a <= 0 then GC.screenFlash = nil
            else
                surface.SetDrawColor(fl.c, fl.c, fl.c, 255 * a)
                surface.DrawRect(0, 0, w, h)
            end
        end

        local eb = GC.eventBanner
        if eb then
            local age = CurTime() - eb.t
            if age > 5 then GC.eventBanner = nil
            else
                local al = age > 4 and (5 - age) or 1
                surface.SetFont("GCapture.Big")
                local tw = surface.GetTextSize(eb.text)
                draw.RoundedBox(8, w / 2 - tw / 2 - 16, 52, tw + 32, 42, Color(TH.accentDim.r, TH.accentDim.g, TH.accentDim.b, 240 * al))
                draw.RoundedBox(8, w / 2 - tw / 2 - 15, 53, tw + 30, 40, Color(8, 12, 10, 235 * al))
                draw.SimpleText(eb.text, "GCapture.Big", w / 2, 59, Color(255, 230, 140, 255 * al), TEXT_ALIGN_CENTER)
            end
        end
        if GC.virusEnd and CurTime() < GC.virusEnd then
            draw.SimpleTextOutlined(string.format("VIRUS (%d s)", math.ceil(GC.virusEnd - CurTime())),
                "GCapture.Stat", w / 2, 100, Color(255, 100, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
        end
        DrawTopTip(w, h)
    end

    return { panel = game, stop = stop, spirits = spBtn, map = map, bar = bar, stats = stBtn, settings = setBtn }
end

local function BuildDeploy(root)
    local p = vgui.Create("DPanel", root)
    p:Dock(FILL)
    p.zoom, p.ox, p.oy = 1, 0, 0
    local ui = { panel = p }
    local TOP_H, PAD = 44, 8

    local function Geo(s)
        local D = GC.deploy
        local w, h = s:GetSize()
        local aw, ah = w - PAD * 2, h - TOP_H - PAD
        local base = math.min(aw / D.w, ah / D.h)
        local cs = base * s.zoom
        local sw, sh = cs * D.w, cs * D.h
        if sw <= aw then s.ox = (aw - sw) / 2 else s.ox = math.Clamp(s.ox, aw - sw, 0) end
        if sh <= ah then s.oy = (ah - sh) / 2 else s.oy = math.Clamp(s.oy, ah - sh, 0) end
        return cs, PAD + s.ox, TOP_H + s.oy, aw, ah
    end
    local function CellAt(s, mx, my)
        local D = GC.deploy
        local cs, ox, oy = Geo(s)
        local cx, cy = math.floor((mx - ox) / cs), math.floor((my - oy) / cs)
        if cx < 0 or cy < 0 or cx >= D.w or cy >= D.h then return end
        return cy * D.w + cx + 1
    end

    function p:OnMouseWheeled(d)
        local D = GC.deploy
        if not D or not D.biome then return end
        local mx, my = self:CursorPos()
        local cs, ox, oy = Geo(self)
        local base = cs / self.zoom
        self.zoom = math.Clamp(self.zoom * (d > 0 and 1.25 or 0.8), 1, math.max(1.5, 48 / base))
        local ncs = base * self.zoom
        self.ox = (mx - PAD) - ((mx - ox) / cs) * ncs
        self.oy = (my - TOP_H) - ((my - oy) / cs) * ncs
    end
    function p:OnMousePressed(code)
        local D = GC.deploy
        if not D or not D.biome then return end
        local mx, my = self:CursorPos()
        if code == MOUSE_LEFT then
            if not D.slot or D.slot == 0 then return end
            local c = CellAt(self, mx, my)
            if not c or GC.Biomes[D.biome[c]].water then return end
            if not D.cruns then D.mine = c end
            net.Start("GCapture_DeployPick")
            net.WriteUInt(c, 20)
            net.SendToServer()
        else
            self.drag = { mx = mx, my = my, ox = self.ox, oy = self.oy }
            self:MouseCapture(true)
        end
    end
    function p:OnCursorMoved(mx, my)
        if self.drag then
            self.ox = self.drag.ox + (mx - self.drag.mx)
            self.oy = self.drag.oy + (my - self.drag.my)
        end
    end
    function p:OnMouseReleased()
        self.drag = nil
        self:MouseCapture(false)
    end

    function p:Paint(w, h)
        local D = GC.deploy
        if not D then return end
        local left = math.max(0, D.endT - CurTime())
        local mineOk = D.slot and D.slot ~= 0
        draw.SimpleText(mineOk and "Pick your starting cell" or "Pick your starting cell",
            "GCapture.Big", PAD + 4, 4, TH.accent)
        draw.SimpleText(string.format("%d s", math.ceil(left)), "GCapture.Big", w - PAD - 4, 4, TH.text, TEXT_ALIGN_RIGHT)
        local fr = math.Clamp(left / D.total, 0, 1)
        draw.RoundedBox(2, PAD, 36, w - PAD * 2, 4, TH.hd)
        draw.RoundedBox(2, PAD, 36, (w - PAD * 2) * fr, 4, TH.accent)

        if not D.runs then
            draw.SimpleText("Loading the map...", "GCapture.Stat", w / 2, h / 2, TH.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return
        end
        local cs, ox, oy, aw, ah = Geo(self)
        local floor = math.floor
        local sx, sy = self:LocalToScreen(PAD, TOP_H)
        render.SetScissorRect(sx, sy, sx + aw, sy + ah, true)
        draw.NoTexture()
        local y0, y1 = math.max(0, floor((TOP_H - oy) / cs)), math.min(D.h - 1, floor((TOP_H + ah - oy) / cs))
        local x0, x1 = math.max(0, floor((PAD - ox) / cs)), math.min(D.w - 1, floor((PAD + aw - ox) / cs))
        for y = y0, y1 do
            local py = floor(oy + y * cs)
            local ph = math.max(1, floor(oy + (y + 1) * cs) - py)
            for _, r in ipairs(D.runs[y]) do
                if r[1] + r[2] - 1 >= x0 and r[1] <= x1 then
                    local px = floor(ox + r[1] * cs)
                    local pw = math.max(1, floor(ox + (r[1] + r[2]) * cs) - px)
                    local c = GC.Biomes[r[3]].color
                    surface.SetDrawColor(c.r, c.g, c.b, 255)
                    surface.DrawRect(px, py, pw, ph)
                end
            end
        end
        if D.cruns then
            for y = y0, y1 do
                local py = floor(oy + y * cs)
                local ph = math.max(1, floor(oy + (y + 1) * cs) - py)
                for _, r in ipairs(D.cruns[y] or {}) do
                    if r[1] + r[2] - 1 >= x0 and r[1] <= x1 then
                        local px = floor(ox + r[1] * cs)
                        local pw = math.max(1, floor(ox + (r[1] + r[2]) * cs) - px)
                        local c = D.ccols[r[3]]
                        surface.SetDrawColor(c.r, c.g, c.b, 110)
                        surface.DrawRect(px, py, pw, ph)
                    end
                end
            end
        end

        local function Mark(cell, col, mine)
            local cx, cy = (cell - 1) % D.w, floor((cell - 1) / D.w)
            local sz = math.max(cs, 7)
            local px, py = ox + (cx + 0.5) * cs - sz / 2, oy + (cy + 0.5) * cs - sz / 2
            draw.NoTexture()
            surface.SetDrawColor(mine and 255 or 0, mine and 255 or 0, mine and 255 or 0, 240)
            surface.DrawRect(px - 2, py - 2, sz + 4, sz + 4)
            surface.SetDrawColor(col.r, col.g, col.b, 255)
            surface.DrawRect(px, py, sz, sz)
            if cs >= 10 then
                surface.SetDrawColor(255, 255, 255, 255)
                surface.SetMaterial(mats[GC.B_CAPITAL])
                surface.DrawTexturedRect(px, py, sz, sz)
            end
        end
        for _, e in ipairs(D.picks) do Mark(e.cell, e.color, e.cell == D.mine) end
        if D.mine then
            local found = false
            for _, e in ipairs(D.picks) do if e.cell == D.mine then found = true break end end
            if not found then Mark(D.mine, D.color, true) end
        end

        local mx, my = self:CursorPos()
        local hc = mineOk and self:IsHovered() and CellAt(self, mx, my)
        if hc and not GC.Biomes[D.biome[hc]].water then
            local cx, cy = (hc - 1) % D.w, floor((hc - 1) / D.w)
            surface.SetDrawColor(255, 255, 255, 230)
            surface.DrawOutlinedRect(floor(ox + cx * cs), floor(oy + cy * cs), math.max(2, floor(cs)), math.max(2, floor(cs)))
        end
        render.SetScissorRect(0, 0, 0, 0, false)
        draw.SimpleTextOutlined(mineOk and "LMB: pick   RMB drag: pan   Wheel: zoom   No pick = random cell"
            or "RMB drag: pan   Wheel: zoom", "GCapture.Small", w - PAD - 4, h - 22, Color(210, 230, 215),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, color_black)
    end
    return ui
end

local matLogo = Material("gcapture/logo.png", "smooth mips")
local matDiscord = Material("gcapture/gc_discord.png", "smooth mips")
GC.DiscordURL = "https://discord.gg/wM3rP88hSp"
GC.Version = "v1.0.1"

local function BuildMenu(root)
    local p = vgui.Create("DPanel", root)
    p:Dock(FILL)
    p.t0 = SysTime()
    local ui = { panel = p }

    local btns = {}
    local function MBtn(text, fn)
        local b = vgui.Create("DButton", p)
        b:SetText(text)
        b:SetFont("GCapture.Big")
        StyleButton(b)
        b.DoClick = fn
        b:SetAlpha(0)
        btns[#btns + 1] = b
        return b
    end
    MBtn("Singleplayer", function() GC.GoLobby(true) end)
    MBtn("Multiplayer", function() GC.GoLobby(false) end)

    local dbtn = vgui.Create("DButton", p)
    dbtn:SetText("")
    dbtn:SetAlpha(0)
    dbtn:SetTooltip("Join our Discord")
    StyleButton(dbtn)
    local dBase = dbtn.Paint
    dbtn.Paint = function(s, w, h)
        dBase(s, w, h)
        local ic = h - 12
        surface.SetMaterial(matDiscord)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(10, (h - ic) / 2, ic, ic)
        draw.SimpleText("Discord", "GCapture.Stat", 10 + ic + 8, h / 2, s:GetTextColor(), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    dbtn.DoClick = function() gui.OpenURL(GC.DiscordURL) end

    function ui.Reset() p.t0 = SysTime() end

    local BW, BH, GAP = 200, 46, 16
    local function Place(s, w, h)
        local x0 = math.floor((w - (BW * 2 + GAP)) / 2)
        for k, b in ipairs(btns) do
            b.baseX, b.baseY = x0 + (k - 1) * (BW + GAP), h - BH - 36
            b:SetSize(BW, BH)
            b:SetPos(b.baseX, b.baseY)
        end
    end
    p.PerformLayout = function(s, w, h)
        Place(s, w, h)
        dbtn:SetSize(130, 36)
        dbtn.baseX, dbtn.baseY = 16, h - 36 - 14
        dbtn:SetPos(dbtn.baseX, dbtn.baseY)
    end

    p.Think = function(s)
        local t = SysTime() - s.t0
        for k, b in ipairs(btns) do
            if b.baseX then
                local kk = math.Clamp((t - 1.0 - (k - 1) * 0.15) / 0.5, 0, 1)
                local e = 1 - (1 - kk) ^ 3
                b:SetAlpha(255 * e)
                b:SetPos(b.baseX, b.baseY + (1 - e) * 18)
                b:SetMouseInputEnabled(kk >= 1)
            end
        end
        if dbtn.baseX then
            local kk = math.Clamp((t - 1.0 - #btns * 0.15) / 0.5, 0, 1)
            local e = 1 - (1 - kk) ^ 3
            dbtn:SetAlpha(255 * e)
            dbtn:SetPos(dbtn.baseX, dbtn.baseY + (1 - e) * 18)
            dbtn:SetMouseInputEnabled(kk >= 1)
        end
    end

    p.Paint = function(s, w, h)
        draw.SimpleText(GC.Version or "", "GCapture.Small", w - 12, h - 8, ColorAlpha(TH.muted, 200), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        local t = SysTime() - s.t0 - 0.25
        if t <= 0 then return end
        local a = math.min(1, t / 0.9)
        local k = math.min(1, t / 1.2)
        local sc = 0.55 + 0.45 * EaseBack(k)
        local float = t > 1.2 and math.sin((t - 1.2) * 1.3) * 4 or 0
        local iw, ih = matLogo:Width(), matLogo:Height()
        if not iw or iw <= 0 or not ih or ih <= 0 then iw, ih = 2, 1 end
        local fit = math.min(w * 0.84 / iw, (h - BH - 76) / ih)
        local dw, dh = iw * fit * sc, ih * fit * sc
        local cx, cy = w / 2, (h - BH - 44) / 2 + 6 + float
        Glow(cx, cy, math.max(dw, dh) * 0.6, TH.accent, 5 * a * (0.8 + 0.2 * math.sin(t * 2)))
        surface.SetMaterial(matLogo)
        surface.SetDrawColor(255, 255, 255, 255 * a)
        surface.DrawTexturedRect(math.floor(cx - dw / 2), math.floor(cy - dh / 2), math.floor(dw), math.floor(dh))
    end
    return ui
end

local function ScreenOf(ui)
    local dm = GC.demoMode
    if dm == "play" or (not dm and GC.playing) then return "game" end
    if dm == "list" then return "demos" end
    if not dm and GC.deploy then return "deploy" end
    return ui.inMenu and "menu" or "lobby"
end

local function ScreenSize(scr)
    if scr == "game" or scr == "deploy" then return 1100, math.min(920, ScrH() - 60) end
    if scr == "menu" then return 820, 540 end
    if scr == "lobby" and GC.single then return 560, 450 end
    return 760, 450
end

local FADE_OUT, FADE_IN = 0.22, 0.34

local function RefreshContent(ui)
    local dm = GC.demoMode
    if GC.playing or dm or GC.deploy then GC.CloseOptWins() end
    ui.game.stats:SetVisible(GC.mySlot == nil)
    ui.game.bar:SetVisible(dm == "play")
    if dm == "play" then
        ui.game.stop:SetVisible(false)
        ui.game.spirits:SetVisible(false)
    elseif dm == "list" then
        ui.demos.Refresh()
    elseif GC.deploy and not GC.playing then

    elseif GC.playing then
        ui.game.stop:SetVisible(GC.isHost)
        ui.game.spirits:SetVisible(GC.mySlot ~= nil)
        GC.FillSpirits()
    else
        ui.lobby.Refresh()
        if IsValid(ui.spirits) then ui.spirits:Remove() end
        if IsValid(GC.choiceFrame) then GC.choiceFrame:Remove() end
    end
end

local function ApplyScreen(ui, scr)
    ui.screen = scr
    ui.menu.panel:SetVisible(scr == "menu")
    ui.lobby.panel:SetVisible(scr == "lobby")
    ui.game.panel:SetVisible(scr == "game")
    ui.demos.panel:SetVisible(scr == "demos")
    ui.deploy.panel:SetVisible(scr == "deploy")
    ui.lobby.SetSingle(GC.single == true)
    if scr == "menu" then ui.menu.Reset() end
    local tw, th = ScreenSize(scr)
    ui.window:SetSize(tw, th)
    ui.window:SetPos(ScrW() / 2 - tw / 2, ScrH() / 2 - th / 2)
    RefreshContent(ui)
end

function GC.RefreshUI()
    local ui = GC.UI
    if not ui or not IsValid(ui.window) then return end
    local want = ScreenOf(ui)
    if ui.screen == nil then
        ApplyScreen(ui, want)
        return
    end
    if want ~= ui.screen then
        if ui.fadeBusy then ui.fadePending = true return end
        ui.fadeBusy = true
        local fd = ui.fade
        fd.phase, fd.t0, fd.a = 1, SysTime(), 0
        fd:SetVisible(true)
        fd:MoveToFront()
        fd.mid = function()
            if GC.UI ~= ui or not IsValid(ui.window) then return end
            ApplyScreen(ui, ScreenOf(ui))
        end
        return
    end
    RefreshContent(ui)
end

function GC.GoMenu()
    local ui = GC.UI
    if not ui or not IsValid(ui.window) then return end
    GC.CloseOptWins()
    ui.inMenu = true
    GC.RefreshUI()
end

function GC.GoLobby(single)
    local ui = GC.UI
    if not ui or not IsValid(ui.window) then return end
    GC.single = single == true
    ui.inMenu = false
    GC.RefreshUI()
end

local function BuildFade(window, ui)
    local fd = vgui.Create("DPanel", window)
    fd:SetZPos(32767)
    fd.a = 1
    fd.Paint = function(s, w, h)
        if s.a > 0 then draw.RoundedBox(6, 0, 0, w, h, Color(0, 0, 0, 255 * s.a)) end
    end
    fd.Think = function(s)
        if IsValid(window) then
            local w, h = window:GetSize()
            if s:GetWide() ~= w or s:GetTall() ~= h then s:SetSize(w, h) end
            s:SetPos(0, 0)
        end
        if not s.phase then return end
        local t = SysTime() - s.t0
        if s.phase == 1 then
            s.a = math.min(1, t / FADE_OUT)
            if s.a >= 1 then
                s.phase, s.t0 = 2, SysTime()
                local m = s.mid
                s.mid = nil
                if m then m() end
            end
        else
            s.a = 1 - math.min(1, t / FADE_IN)
            if s.a <= 0 then
                s.phase, s.a = nil, 0
                s:SetVisible(false)
                ui.fadeBusy = false
                if ui.fadePending then
                    ui.fadePending = false
                    GC.RefreshUI()
                end
            end
        end
    end
    return fd
end

local function BuildWindow(window)
    window:SetTitle("GCapture")
    local root = vgui.Create("DPanel", window)
    root:Dock(FILL)
    root.Paint = nil

    local ui = { window = window, inMenu = not GC.playing and not GC.demoMode and not GC.deploy }
    GC.UI = ui
    ui.menu = BuildMenu(root)
    ui.lobby = BuildLobby(root)
    ui.game = BuildGame(root)
    ui.demos = BuildDemos(root)
    ui.deploy = BuildDeploy(root)
    ui.fade = BuildFade(window, ui)

    window.OnRemove = function()
        GC.CloseOptWins()
        if GC.UI and IsValid(GC.UI.spirits) then GC.UI.spirits:Remove() end
        if IsValid(GC.settingsFrame) then GC.settingsFrame:Remove() end
        if IsValid(GC.statsFrame) then GC.statsFrame:Remove() end
        if IsValid(GC.infoFrame) then GC.infoFrame:Remove() end
        if GC.demoMode then GC.playing, GC.gameId = false, nil end
        GC.demoMode, GC.demo = nil, nil
        GC.UI = nil
        net.Start("GCapture_View")
        net.WriteBool(false)
        net.SendToServer()
    end

    GC.RefreshUI()

    ui.fadeBusy = true
    ui.fade.phase, ui.fade.t0, ui.fade.a = 2, SysTime(), 1
    net.Start("GCapture_View")
    net.WriteBool(true)
    net.SendToServer()
    GC.SendRec(GetConVar("cl_gc_record"):GetBool())
end

CreateClientConVar("cl_gc_music", "1", true, false, "GCapture: dynamic music (1 = on, 0 = off)", 0, 1)
local cvMusic = GetConVar("cl_gc_music")

local MUS_FILES = { calm = "sound/gcapture/gcapture_calm.mp3", combat = "sound/gcapture/gcapture_combat.mp3" }
local MUS_CALM_DELAY = 30
local MUS_FADE_IN = 3
local MUS_FADE_OUT = 6

local M = { mix = 0, gf = 0, lastCombat = -1000, gen = 0, loading = false, started = false, nextSync = 0 }
GC.Music = M

local function StopMusic()
    M.gen = M.gen + 1
    for _, k in ipairs({ "calm", "combat" }) do
        local ch = M[k]
        if ch and ch:IsValid() then ch:Stop() end
        M[k] = nil
    end
    M.loading, M.started, M.mix, M.gf = false, false, 0, 0
end

local function InCombat()
    local slot = GC.mySlot
    if not slot then return false end
    for _, A in pairs(GC.army) do
        if A.owner == slot then
            if A.state == GC.ST_DEFENSE then return true end
            if A.state == GC.ST_ATTACK and A.target ~= 0 then
                local D = GC.army[A.target]
                if D and D.owner ~= slot then return true end
            end
        end
    end
    return false
end

local function LoadMusic()
    M.loading = true
    local gen = M.gen
    local got, failed = {}, false
    local function Done(k, ch)
        if gen ~= M.gen then
            if ch and ch:IsValid() then ch:Stop() end
            return
        end
        if not ch or not ch:IsValid() then failed = true else got[k] = ch end
        if failed then
            M.loading = false
            for _, c in pairs(got) do if c:IsValid() then c:Stop() end end
            GC.musicRetry = CurTime() + 10
            return
        end
        if got.calm and got.combat then
            for _, c in pairs(got) do c:EnableLooping(true) end
            M.calm, M.combat, M.loading = got.calm, got.combat, false
        end
    end
    for k, path in pairs(MUS_FILES) do
        sound.PlayFile(path, "noplay noblock", function(ch) Done(k, ch) end)
    end
end

hook.Add("Think", "GCapture_Music", function()
    local want = cvMusic:GetBool() and GC.playing and GC.UI and IsValid(GC.UI.window)
    if not want then
        if M.calm or M.combat or M.loading then StopMusic() end
        return
    end

    if not (M.calm and M.combat) then
        if not M.loading and CurTime() >= (GC.musicRetry or 0) then LoadMusic() end
        return
    end
    if not M.calm:IsValid() or not M.combat:IsValid() then StopMusic() return end

    local now = CurTime()
    if not M.started then
        M.calm:SetTime(0)
        M.combat:SetTime(0)
        M.calm:Play()
        M.combat:Play()
        M.started, M.nextSync = true, now + 2
    end

    for _, ch in ipairs({ M.calm, M.combat }) do
        if ch:GetState() == GMOD_CHANNEL_STOPPED then
            ch:SetTime(0)
            ch:Play()
        end
    end

    if now >= M.nextSync then
        M.nextSync = now + 2
        local t = M.calm:GetTime()
        if math.abs(M.combat:GetTime() - t) > 0.15 then M.combat:SetTime(t) end
    end

    if InCombat() then M.lastCombat = now end
    local fighting = (now - M.lastCombat) < MUS_CALM_DELAY
    local dt = FrameTime()
    if fighting then
        M.mix = math.min(1, M.mix + dt / MUS_FADE_IN)
    else
        M.mix = math.max(0, M.mix - dt / MUS_FADE_OUT)
    end
    M.gf = math.min(1, M.gf + dt / 2)
    local mv = GC.cvMusVol:GetFloat() * M.gf
    M.calm:SetVolume(mv * (1 - M.mix))
    M.combat:SetVolume(mv * M.mix)
end)

local THEME_FILE = "sound/gcapture/gcapture_theme.mp3"
local T = { vol = 0, gen = 0, loading = false }
GC.Theme = T

local function StopTheme()
    T.gen = T.gen + 1
    if T.ch and T.ch:IsValid() then T.ch:Stop() end
    T.ch, T.loading, T.vol = nil, false, 0
end

hook.Add("Think", "GCapture_Theme", function()
    local ui = GC.UI
    local want = cvMusic:GetBool() and ui and IsValid(ui.window) and ui.screen ~= "game"
    local dt = FrameTime()
    if want then
        if not (T.ch and T.ch:IsValid()) then
            if not T.loading and CurTime() >= (GC.themeRetry or 0) then
                T.loading = true
                local gen = T.gen
                sound.PlayFile(THEME_FILE, "noplay noblock", function(ch)
                    if gen ~= T.gen then
                        if ch and ch:IsValid() then ch:Stop() end
                        return
                    end
                    T.loading = false
                    if not ch or not ch:IsValid() then
                        GC.themeRetry = CurTime() + 10
                        return
                    end
                    ch:EnableLooping(true)
                    ch:SetVolume(0)
                    ch:Play()
                    T.ch = ch
                end)
            end
            return
        end
        T.vol = math.min(1, T.vol + dt / 1.5)
    else
        if not (T.ch or T.loading) then return end
        T.vol = math.max(0, T.vol - dt / 0.7)
        if T.vol <= 0 then StopTheme() return end
    end
    if not (T.ch and T.ch:IsValid()) then return end
    if T.ch:GetState() == GMOD_CHANNEL_STOPPED then
        T.ch:SetTime(0)
        T.ch:Play()
    end
    T.ch:SetVolume(GC.cvMusVol:GetFloat() * T.vol)
end)
hook.Add("ShutDown", "GCapture_ThemeStop", StopTheme)

hook.Add("ShutDown", "GCapture_MusicStop", StopMusic)

list.Set("DesktopWindows", "GCapture", {
    title = "GCapture",
    icon = "gcapture/gc_icon.png",
    width = 820,
    height = math.min(920, ScrH() - 60),
    onewindow = true,
    init = function(icon, window)

        window:Remove()

        if GC.UI and IsValid(GC.UI.window) then
            GC.UI.window:MakePopup()
            GC.UI.window:MoveToFront()
            return
        end

        local frame = vgui.Create("DFrame")
        frame:SetSize(1100, math.min(920, ScrH() - 60))
        frame:Center()
        frame:MakePopup()
        StyleFrame(frame)
        BuildWindow(frame)
    end,
})
