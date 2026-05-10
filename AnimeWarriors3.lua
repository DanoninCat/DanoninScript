-- ============================================================
--  CAT EMPIRE | v5.23 | Anime Warriors 3
--  Coded for Danonin
-- ============================================================

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local RS              = game:GetService("ReplicatedStorage")
local WS              = game:GetService("Workspace")
local UIS             = game:GetService("UserInputService")
local player          = Players.LocalPlayer
local placeId         = game.PlaceId

repeat task.wait() until player:FindFirstChild("PlayerGui")

-- ============================================================
-- FLUENT
-- ============================================================
local ok1, Fluent = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/main.lua", true))()
end)
if not ok1 then
    -- Fallback: URL alternativa
    local ok1b
    ok1b, Fluent = pcall(function()
        return loadstring(game:HttpGet("https://cdn.jsdelivr.net/gh/dawid-scripts/Fluent@master/main.lua", true))()
    end)
    if not ok1b then warn("[CE] Fluent falhou: " .. tostring(Fluent)) return end
end

local ok2, SaveManager = pcall(function()
    return loadstring(game:HttpGet("https://cdn.jsdelivr.net/gh/dawid-scripts/Fluent@master/Addons/SaveManager.lua", true))()
end)
if not ok2 then warn("[CE] SaveManager falhou: " .. tostring(SaveManager)) return end

local ok3, InterfaceManager = pcall(function()
    return loadstring(game:HttpGet("https://cdn.jsdelivr.net/gh/dawid-scripts/Fluent@master/Addons/InterfaceManager.lua", true))()
end)
if not ok3 then warn("[CE] InterfaceManager falhou: " .. tostring(InterfaceManager)) return end

-- ============================================================
-- FIRE MANAGER — busca remotes por nome recursivamente
-- ============================================================
local FM = {}
FM._cache = {}

function FM:_find(path)
    if self._cache[path] then return self._cache[path] end
    local parts = string.split(path, ".")
    local obj   = RS
    for _, p in ipairs(parts) do
        if not obj then break end
        obj = obj:FindFirstChild(p) or obj:FindFirstChild(p:sub(1,1):upper()..p:sub(2))
    end
    if obj and (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) then
        self._cache[path] = obj
        return obj
    end
    local last = parts[#parts]
    local function search(parent, depth)
        if depth > 6 then return nil end
        for _, child in ipairs(parent:GetChildren()) do
            if (child.Name == last or child.Name:lower() == last:lower())
            and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
                self._cache[path] = child
                return child
            end
            local found = search(child, depth + 1)
            if found then return found end
        end
    end
    local r = search(RS, 0)
    if r then self._cache[path] = r end
    return r
end

function FM:Fire(path, ...)
    local args = { ... }
    local r    = self:_find(path)
    if r and r:IsA("RemoteEvent") then
        pcall(function() r:FireServer(table.unpack(args)) end)
    else
        warn("[FM] RemoteEvent não encontrado: " .. path)
    end
end

function FM:Invoke(path, ...)
    local args = { ... }
    local r    = self:_find(path)
    if r and r:IsA("RemoteFunction") then
        local ok, res = pcall(function() return r:InvokeServer(table.unpack(args)) end)
        if ok then return res end
    end
    return nil
end

-- ============================================================
-- SAFETY MANAGER
-- ============================================================
local Safety = {}
Safety._threads = {}
Safety._active  = {}

function Safety:Kill(key)
    self._active[key] = false
    if self._threads[key] then
        pcall(function() task.cancel(self._threads[key]) end)
        self._threads[key] = nil
    end
end

function Safety:KillAll()
    for k in pairs(self._threads) do self:Kill(k) end
end

function Safety:IsActive(key)
    return self._active[key] == true
end

function Safety:Loop(key, interval, fn)
    self:Kill(key)
    self._active[key] = true
    local t = task.spawn(function()
        while self._active[key] do
            task.wait(interval > 0 and interval or 0.1)
            if self._active[key] then pcall(fn) end
        end
        self._threads[key] = nil
    end)
    self._threads[key] = t
end

function Safety:Toggle(key, enabled, interval, fn)
    if enabled then self:Loop(key, interval, fn) else self:Kill(key) end
end

-- ============================================================
-- SCAN FIGHTERS
-- ============================================================
local selUID  = ""
local selName = "Nenhum"
local fighterDD = nil

local function scanFighters()
    local list, seen = {}, {}
    pcall(function()
        local roots = {}
        local cl = WS:FindFirstChild("Client")
        local sv = WS:FindFirstChild("Server")
        if cl then
            local f = cl:FindFirstChild("Fighters") or cl:FindFirstChild("Warriors")
            if f then table.insert(roots, f) end
        end
        if sv then
            local f = sv:FindFirstChild("Fighters") or sv:FindFirstChild("Warriors")
            if f then table.insert(roots, f) end
        end
        for _, root in ipairs(roots) do
            local myF = root:FindFirstChild(tostring(player.UserId)) or root:FindFirstChild(player.Name)
            if not myF then continue end
            for _, fighter in ipairs(myF:GetChildren()) do
                local uid = fighter.Name
                if seen[uid] then continue end
                seen[uid] = true
                local name   = fighter:GetAttribute("Name") or fighter:GetAttribute("CharacterName") or fighter:GetAttribute("WarriorName") or "Unknown"
                local rarity = fighter:GetAttribute("Rarity") or ""
                local level  = fighter:GetAttribute("Level") or 1
                local eq     = fighter:GetAttribute("Equipped") or fighter:GetAttribute("Enabled")
                table.insert(list, {
                    UID      = uid,
                    Name     = tostring(name),
                    Rarity   = tostring(rarity),
                    Level    = level,
                    Equipped = (eq == true),
                    Display  = tostring(name).." ["..tostring(rarity).."] Lv."..tostring(level)
                })
            end
        end
    end)
    return list
end

-- ============================================================
-- SCAN ENEMIES
-- ============================================================
local function scanEnemies()
    local list = {}
    pcall(function()
        local sv = WS:FindFirstChild("Server") if not sv then return end
        local en = sv:FindFirstChild("Enemies") if not en then return end
        for _, wf in ipairs(en:GetChildren()) do
            if wf.Name == "Lobby" then continue end
            for _, e in ipairs(wf:GetChildren()) do
                local uid = e:GetAttribute("ID") or e:GetAttribute("UID") or e:GetAttribute("Id")
                if not uid then continue end
                local hp = e:GetAttribute("Health") or e:GetAttribute("HP") or 0
                if hp ~= hp or hp == math.huge or hp <= 0 then continue end
                table.insert(list, { UID = tostring(uid), Name = e.Name, World = wf.Name })
            end
        end
    end)
    return list
end

local function getNearestUID()
    local char = player.Character if not char then return nil end
    local hrp  = char:FindFirstChild("HumanoidRootPart") if not hrp then return nil end
    local sv   = WS:FindFirstChild("Server") if not sv then return nil end
    local en   = sv:FindFirstChild("Enemies") if not en then return nil end
    local near, nearD = nil, math.huge
    for _, wf in ipairs(en:GetChildren()) do
        if wf.Name == "Lobby" then continue end
        for _, e in ipairs(wf:GetChildren()) do
            local uid = e:GetAttribute("ID") or e:GetAttribute("UID") or e:GetAttribute("Id")
            if not uid then continue end
            local hp = e:GetAttribute("Health") or e:GetAttribute("HP") or 0
            if hp ~= hp or hp == math.huge or hp <= 0 then continue end
            local part = e:IsA("BasePart") and e or e:FindFirstChildWhichIsA("BasePart", true)
            if not part then continue end
            local d = (hrp.Position - part.Position).Magnitude
            if d < nearD then nearD = d near = tostring(uid) end
        end
    end
    return near
end

local function getEquippedUIDs()
    local uids = {}
    pcall(function()
        local sv  = WS:FindFirstChild("Server") if not sv then return end
        local fi  = sv:FindFirstChild("Fighters") or sv:FindFirstChild("Warriors") if not fi then return end
        local myF = fi:FindFirstChild(tostring(player.UserId)) or fi:FindFirstChild(player.Name) if not myF then return end
        for _, f in ipairs(myF:GetChildren()) do
            local eq = f:GetAttribute("Equipped") or f:GetAttribute("Enabled")
            if eq == true then table.insert(uids, f.Name) end
        end
    end)
    return uids
end

-- ============================================================
-- ROLLBACK
-- ============================================================
local rbActive = false
local rbSnap   = nil
local rbConns  = {}
local rbTime   = nil
local rbTimer  = 0

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = deepCopy(v) end
    return c
end

local function startRB()
    rbSnap = nil rbTime = nil rbTimer = 0 rbConns = {}
    local function tryCapture(args)
        for _, arg in ipairs(args) do
            if type(arg) == "table" and (arg.Fighters or arg.Warriors or arg.Coins or arg.Inventory) then
                if rbSnap == nil then
                    rbSnap  = deepCopy(arg)
                    rbTime  = os.date("%H:%M:%S")
                    rbTimer = 0
                    task.spawn(function()
                        while rbActive do task.wait(1) rbTimer += 1 end
                    end)
                    Fluent:Notify({ Title="Rollback", Content="Capturado às "..rbTime, Duration=4 })
                    return true
                end
            end
        end
        return false
    end
    pcall(function()
        for _, obj in ipairs(RS:GetDescendants()) do
            if obj:IsA("RemoteEvent") then
                local c = obj.OnClientEvent:Connect(function(...)
                    if rbActive then tryCapture({...}) end
                end)
                table.insert(rbConns, c)
            end
        end
    end)
    Fluent:Notify({ Title="Rollback", Content="Captura ativada.", Duration=3 })
end

local function stopRB()
    for _, c in ipairs(rbConns) do pcall(function() c:Disconnect() end) end
    rbConns = {}
end

local function execRB()
    if not rbSnap then
        Fluent:Notify({ Title="Rollback", Content="Nenhum estado capturado!", Duration=3 })
        return
    end
    if rbTimer >= 90 then
        Fluent:Notify({ Title="Rollback RISCO", Content=rbTimer.."s passados.", Duration=4 })
        task.wait(1.5)
    end
    Safety:KillAll() stopRB() rbActive = false
    Fluent:Notify({ Title="Rollback", Content="Executando rejoin...", Duration=3 })
    task.wait(0.5)
    local ok = pcall(function() TeleportService:TeleportAsync(placeId, {player}) end)
    if not ok then pcall(function() TeleportService:Teleport(placeId) end) end
end

-- ============================================================
-- FLUENT WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Cat Empire",
    SubTitle    = "v5.23 | by Danonin",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(720, 480),
    Acrylic     = true,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

-- ============================================================
-- BOTÃO FLUTUANTE
-- ============================================================
local winVis = true
local pg     = player:WaitForChild("PlayerGui", 10)

local minSG = Instance.new("ScreenGui")
minSG.Name           = "CatEmpireMinGui"
minSG.ResetOnSpawn   = false
minSG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
minSG.DisplayOrder   = 999
minSG.Parent         = pg

local minFrame = Instance.new("Frame", minSG)
minFrame.Size             = UDim2.fromOffset(60, 60)
minFrame.Position         = UDim2.new(0, 8, 0.5, -30)
minFrame.BackgroundColor3 = Color3.fromRGB(0, 80, 190)
minFrame.BackgroundTransparency = 0.08
minFrame.ZIndex           = 50
Instance.new("UICorner", minFrame).CornerRadius = UDim.new(0, 12)
Instance.new("UIStroke", minFrame).Color = Color3.fromRGB(60, 140, 255)

local minLbl = Instance.new("TextLabel", minFrame)
minLbl.Size             = UDim2.fromScale(1, 1)
minLbl.BackgroundTransparency = 1
minLbl.Text             = "CE"
minLbl.TextColor3       = Color3.new(1, 1, 1)
minLbl.Font             = Enum.Font.GothamBold
minLbl.TextSize         = 14
minLbl.ZIndex           = 51

local minHit = Instance.new("TextButton", minFrame)
minHit.Size             = UDim2.fromScale(1, 1)
minHit.BackgroundTransparency = 1
minHit.Text             = ""
minHit.ZIndex           = 52

local fluentSG = nil
task.spawn(function()
    for _ = 1, 20 do
        task.wait(0.5)
        local f = pg:FindFirstChild("Fluent")
        if f and f:IsA("ScreenGui") then fluentSG = f break end
        for _, sg in ipairs(pg:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Name ~= "CatEmpireMinGui" then
                for _, ch in ipairs(sg:GetChildren()) do
                    if ch:IsA("Frame") and ch:FindFirstChildOfClass("UICorner") then
                        fluentSG = sg break
                    end
                end
                if fluentSG then break end
            end
        end
        if fluentSG then break end
    end
end)

local function doMin()
    winVis = not winVis
    if fluentSG then
        pcall(function() fluentSG.Enabled = winVis end)
    else
        pcall(function()
            local VIM = game:GetService("VirtualInputManager")
            VIM:SendKeyEvent(true, Enum.KeyCode.RightControl, false, game)
            task.wait(0.05)
            VIM:SendKeyEvent(false, Enum.KeyCode.RightControl, false, game)
        end)
        winVis = not winVis
    end
    minFrame.BackgroundColor3 = winVis and Color3.fromRGB(0,80,190) or Color3.fromRGB(140,30,30)
    minLbl.Text = winVis and "CE" or ">"
end

local drag, moved, dStart, sPos = false, false, nil, nil
minHit.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        drag = true moved = false
        dStart = Vector2.new(i.Position.X, i.Position.Y)
        sPos   = minFrame.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if not drag then return end
    if i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch then
        local dx = i.Position.X - dStart.X
        local dy = i.Position.Y - dStart.Y
        if math.abs(dx) > 5 or math.abs(dy) > 5 then
            moved = true
            minFrame.Position = UDim2.new(sPos.X.Scale, sPos.X.Offset+dx, sPos.Y.Scale, sPos.Y.Offset+dy)
        end
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        if not drag then return end
        drag = false
        if not moved then doMin() end
        moved = false
    end
end)

-- ============================================================
-- TABS
-- ============================================================
local Tabs = {
    Main      = Window:AddTab({ Title = "Main",      Icon = "sword"      }),
    Combat    = Window:AddTab({ Title = "Combat",    Icon = "zap"        }),
    Fighters  = Window:AddTab({ Title = "Fighters",  Icon = "user"       }),
    Inventory = Window:AddTab({ Title = "Inventory", Icon = "package"    }),
    Summon    = Window:AddTab({ Title = "Summon",    Icon = "star"       }),
    Rollback  = Window:AddTab({ Title = "Rollback",  Icon = "rotate-ccw" }),
    Teleport  = Window:AddTab({ Title = "Teleport",  Icon = "map-pin"    }),
    Settings  = Window:AddTab({ Title = "Settings",  Icon = "settings"   }),
    Info      = Window:AddTab({ Title = "Info",      Icon = "info"       }),
}
local Options = Fluent.Options

-- ============================================================
-- TAB: MAIN
-- ============================================================
Tabs.Main:AddSection("Automatizacoes Gerais")

Tabs.Main:AddToggle("AutoEquip", { Title = "Auto Equip Best", Default = false })
Options.AutoEquip:OnChanged(function(v)
    Safety:Toggle("AutoEquip", v, 5, function() FM:Fire("warriors.equipBest") end)
end)

Tabs.Main:AddButton({
    Title    = "Equip Best (1x)",
    Callback = function()
        FM:Fire("warriors.equipBest")
        Fluent:Notify({ Title="Inventory", Content="Equip Best enviado", Duration=2 })
    end,
})

Tabs.Main:AddToggle("AutoStream", { Title = "Auto Stream Retrieve", Default = false })
Options.AutoStream:OnChanged(function(v)
    Safety:Toggle("AutoStream", v, 30, function() FM:Fire("stream.retrieve") end)
end)

-- ============================================================
-- TAB: COMBAT
-- ============================================================
Tabs.Combat:AddSection("Auto Combat")

local combatUID = ""
local combatDD  = Tabs.Combat:AddDropdown("CombatEnemy", {
    Title   = "Inimigo Alvo",
    Values  = { "Nearest" },
    Default = "Nearest",
})
combatDD:OnChanged(function(v)
    combatUID = (v == "Nearest") and "" or v
end)

Tabs.Combat:AddButton({
    Title    = "Escanear Inimigos",
    Callback = function()
        local list   = scanEnemies()
        local values = { "Nearest" }
        for _, e in ipairs(list) do
            table.insert(values, e.Name.." ["..e.World.."] "..e.UID)
        end
        combatDD:SetValues(values)
        combatDD:SetValue("Nearest")
        combatUID = ""
        Fluent:Notify({ Title="Combat", Content=#list.." inimigo(s)", Duration=3 })
    end,
})

Tabs.Combat:AddToggle("AutoCombat", { Title = "Auto Combat", Default = false })
Options.AutoCombat:OnChanged(function(v)
    Safety:Toggle("AutoCombat", v, 0.5, function()
        local uid = combatUID ~= "" and combatUID or getNearestUID()
        if not uid then return end
        local fi = getEquippedUIDs()
        if #fi == 0 then return end
        FM:Fire("enemies.sendAndRetreat", uid, fi)
    end)
end)

Tabs.Combat:AddSection("Manual")

Tabs.Combat:AddButton({
    Title    = "Atacar Mais Proximo (1x)",
    Callback = function()
        local uid = getNearestUID()
        if not uid then
            Fluent:Notify({ Title="Combat", Content="Nenhum inimigo!", Duration=2 })
            return
        end
        local fi = getEquippedUIDs()
        if #fi == 0 then
            Fluent:Notify({ Title="Combat", Content="Nenhum fighter equipado!", Duration=2 })
            return
        end
        FM:Fire("enemies.sendAndRetreat", uid, fi)
        Fluent:Notify({ Title="Combat", Content="Ataque enviado", Duration=2 })
    end,
})

-- ============================================================
-- TAB: FIGHTERS
-- ============================================================
Tabs.Fighters:AddSection("Selecao de Fighter")

local fighterPara = Tabs.Fighters:AddParagraph({ Title="Selecionado", Content="Nenhum — clique em Escanear" })
local function updFP() fighterPara:SetDesc(selName.."\nUID: "..selUID) end

fighterDD = Tabs.Fighters:AddDropdown("FighterSelect", {
    Title   = "Fighter",
    Values  = { "Nenhum" },
    Default = "Nenhum",
})
fighterDD:OnChanged(function(v)
    if v == "Nenhum" then return end
    local uid  = v:match("| (.+)$")
    local name = v:match("^(.+) |") or v
    if uid then selUID = uid selName = name updFP() end
end)

Tabs.Fighters:AddButton({
    Title    = "Escanear Fighters",
    Callback = function()
        local list = scanFighters()
        if #list == 0 then
            Fluent:Notify({ Title="Fighters", Content="Nenhum fighter encontrado.", Duration=3 })
            return
        end
        local values = { "Nenhum" }
        for _, f in ipairs(list) do table.insert(values, f.Display.." | "..f.UID) end
        fighterDD:SetValues(values)
        fighterDD:SetValue("Nenhum")
        selUID  = list[1].UID
        selName = list[1].Display
        updFP()
        Fluent:Notify({ Title="Fighters", Content=#list.." fighter(s).", Duration=3 })
    end,
})

-- Trait Reroll
Tabs.Fighters:AddSection("Trait Reroll")

local traitTarget = ""
local TRAITS      = { "Livre","Fortune","Swift","Fortune II","Swift II","Legendary","Mythic","Secret","God","Divine","Ultimate" }
local traitDD     = Tabs.Fighters:AddDropdown("TraitTarget", { Title="Trait Desejado", Values=TRAITS, Default="Livre" })
traitDD:OnChanged(function(v) traitTarget = (v == "Livre") and "" or v end)

local traitCount = 0
local traitPara  = Tabs.Fighters:AddParagraph({ Title="Rerolls", Content="0 rerolls realizados" })

local function doReroll()
    if selUID == "" then return end
    local res = FM:Invoke("traits.reroll", selUID, traitTarget, false)
    traitCount += 1
    traitPara:SetDesc(traitCount.." rerolls realizados")
    if traitTarget ~= "" and type(res) == "string" and res:find(traitTarget) then
        Safety:Kill("AutoTraitReroll")
        Options.AutoTraitReroll:SetValue(false)
        Fluent:Notify({ Title="Trait", Content="Trait '"..traitTarget.."' obtido!", Duration=5 })
    end
end

Tabs.Fighters:AddToggle("AutoTraitReroll", { Title = "Auto Trait Reroll", Default = false })
Options.AutoTraitReroll:OnChanged(function(v)
    if v and selUID == "" then
        Fluent:Notify({ Title="Fighters", Content="Selecione um fighter!", Duration=3 })
        Options.AutoTraitReroll:SetValue(false)
        return
    end
    if v then traitCount = 0 end
    Safety:Toggle("AutoTraitReroll", v, 0.5, doReroll)
end)

Tabs.Fighters:AddButton({
    Title    = "Trait Reroll (1x)",
    Callback = function()
        if selUID == "" then
            Fluent:Notify({ Title="Fighters", Content="Selecione um fighter!", Duration=2 })
            return
        end
        doReroll()
        Fluent:Notify({ Title="Traits", Content="Reroll enviado", Duration=2 })
    end,
})

-- ============================================================
-- TAB: INVENTORY
-- ============================================================
Tabs.Inventory:AddSection("Equip")

Tabs.Inventory:AddToggle("AutoEquipInv", { Title = "Auto Equip Best", Default = false })
Options.AutoEquipInv:OnChanged(function(v)
    Safety:Toggle("AutoEquipInv", v, 5, function() FM:Fire("warriors.equipBest") end)
end)

Tabs.Inventory:AddButton({
    Title    = "Equip Best (1x)",
    Callback = function()
        FM:Fire("warriors.equipBest")
        Fluent:Notify({ Title="Inventory", Content="Equip Best enviado", Duration=2 })
    end,
})

Tabs.Inventory:AddSection("Dismantle")

local RARITIES = { "Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret" }
Tabs.Inventory:AddDropdown("DismantleRarity", { Title="Raridade Maxima", Values=RARITIES, Default="Rare" })

Tabs.Inventory:AddButton({
    Title    = "Dismantle por Raridade",
    Callback = function()
        local maxR    = Options.DismantleRarity.Value or "Rare"
        local rank    = {}
        for i, r in ipairs(RARITIES) do rank[r] = i end
        local maxRank = rank[maxR] or 3
        local list    = scanFighters()
        local toDis   = {}
        for _, f in ipairs(list) do
            if (rank[f.Rarity] or 0) <= maxRank and not f.Equipped then
                table.insert(toDis, f.UID)
            end
        end
        if #toDis == 0 then
            Fluent:Notify({ Title="Dismantle", Content="Nenhum para desmantelar.", Duration=3 })
            return
        end
        FM:Invoke("warriors.dismantle", toDis)
        Fluent:Notify({ Title="Dismantle", Content=#toDis.." desmantados.", Duration=3 })
    end,
})

-- ============================================================
-- TAB: SUMMON
-- ============================================================
Tabs.Summon:AddSection("Auto Summon")

local eggType = "Ninja"
local EGGS    = { "Ninja","Dragon","Slayer","Pirate","Hero","World1","World2","World3" }

Tabs.Summon:AddDropdown("SummonEgg", { Title="Tipo de Ovo", Values=EGGS, Default="Ninja" })
Options.SummonEgg:OnChanged(function(v)
    eggType = v
    if Safety:IsActive("AutoSummonKeep") then FM:Fire("eggs.setAuto", eggType, true) end
end)

Tabs.Summon:AddToggle("AutoSummon", { Title = "Auto Summon", Default = false })
Options.AutoSummon:OnChanged(function(v)
    if v then
        FM:Fire("eggs.setAuto", eggType, true)
        Safety:Loop("AutoSummonKeep", 3, function() FM:Fire("eggs.setAuto", eggType, true) end)
    else
        Safety:Kill("AutoSummonKeep")
        FM:Fire("eggs.setAuto", eggType, false)
        Fluent:Notify({ Title="Summon", Content="Desativado.", Duration=2 })
    end
end)

Tabs.Summon:AddButton({
    Title    = "Summon Manual (1x)",
    Callback = function()
        FM:Fire("eggs.setAuto", eggType, true)
        task.wait(0.3)
        FM:Fire("eggs.setAuto", eggType, false)
        Fluent:Notify({ Title="Summon", Content="Summon: "..eggType, Duration=2 })
    end,
})

-- ============================================================
-- TAB: ROLLBACK
-- ============================================================
Tabs.Rollback:AddSection("Rollback")

Tabs.Rollback:AddParagraph({
    Title   = "Como funciona",
    Content = "1. Ative ANTES de qualquer acao\n2. Faca gacha/reroll\n3. Clique Executar Rollback\n4. Rejoin carrega save anterior\n\nUse dentro de ~90s.",
})

local rbStatus = Tabs.Rollback:AddParagraph({ Title="Status", Content="Inativo" })

task.spawn(function()
    while true do
        task.wait(3)
        if rbActive and rbSnap then
            local label = rbTimer < 45 and "SEGURO" or rbTimer < 75 and "ATENCAO" or "RISCO"
            rbStatus:SetDesc("Snapshot: "..(rbTime or "?").."\nTempo: "..rbTimer.."s - "..label)
        elseif rbActive then
            rbStatus:SetDesc("Aguardando sync...")
        end
    end
end)

Tabs.Rollback:AddToggle("RollbackActive", { Title = "Ativar Captura", Default = false })
Options.RollbackActive:OnChanged(function(v)
    rbActive = v
    if v then
        rbSnap  = nil
        rbTimer = 0
        startRB()
        rbStatus:SetDesc("Captura ativa...")
    else
        stopRB()
        rbStatus:SetDesc(rbSnap
            and "Pausado - snapshot de "..(rbTime or "?")
            or  "Desativado")
    end
end)

Tabs.Rollback:AddButton({
    Title    = "Executar Rollback (Rejoin)",
    Callback = function() execRB() end,
})

-- ============================================================
-- TAB: TELEPORT
-- ============================================================
Tabs.Teleport:AddSection("Mundos")

local WORLDS = { "Leaf Village","Dragon Town","Slayer Village","Pirate Island","Solo City","Z City","Hollow Island" }

for _, world in ipairs(WORLDS) do
    local w = world
    Tabs.Teleport:AddButton({
        Title    = w,
        Callback = function()
            local char = player.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            local sv   = WS:FindFirstChild("Server")
            local en   = sv and sv:FindFirstChild("Enemies")
            local wf   = en and en:FindFirstChild(w)
            if hrp and wf then
                local fe = wf:GetChildren()[1]
                if fe then
                    local part = fe:IsA("BasePart") and fe or fe:FindFirstChildWhichIsA("BasePart", true)
                    if part then
                        hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 5, 10))
                        Fluent:Notify({ Title="Teleporte", Content="Indo para "..w, Duration=2 })
                        return
                    end
                end
            end
            Fluent:Notify({ Title="Teleporte", Content="Mundo nao encontrado: "..w, Duration=3 })
        end,
    })
end

-- ============================================================
-- TAB: SETTINGS
-- ============================================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("CatEmpire/AnimeWarriors3")
SaveManager:SetFolder("CatEmpire/AnimeWarriors3/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

-- ============================================================
-- TAB: INFO
-- ============================================================
Tabs.Info:AddSection("Cat Empire v5.23")
Tabs.Info:AddParagraph({ Title="Jogo",    Content="Anime Warriors 3"         })
Tabs.Info:AddParagraph({ Title="Dev",     Content="Danonin"                   })
Tabs.Info:AddParagraph({ Title="Discord", Content="discord.gg/qDeZ9sEdGY"    })
Tabs.Info:AddButton({
    Title    = "Copiar Discord",
    Callback = function()
        setclipboard("https://discord.gg/qDeZ9sEdGY")
        Fluent:Notify({ Title="Copiado!", Content="Link copiado.", Duration=2 })
    end,
})
Tabs.Info:AddParagraph({ Title="Keybind", Content="RightControl - Mostrar/Ocultar\nBotao CE - Toggle/Arrastar" })

-- ============================================================
-- INIT
-- ============================================================
SaveManager:LoadAutoloadConfig()
Window:SelectTab(1)
Fluent:Notify({ Title="Cat Empire v5.23", Content="Carregado com sucesso!", Duration=4 })
