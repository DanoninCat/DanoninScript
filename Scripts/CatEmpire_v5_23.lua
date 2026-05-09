-- ============================================================
--  CAT EMPIRE | v5.23 | CODED FOR DANONIN
--  GAME: Anime Warriors 3
--  FIX v5.23: UI não abre no executor Codex
--    1. Fluent carrega com retry (Codex às vezes bloqueia HttpGet)
--    2. fluentSG buscado com WaitForChild + loop robusto
--    3. minSG vai direto para PlayerGui (CoreGui bloqueado no Codex)
--    4. Safety:Loop corrigido (thread não iniciava corretamente)
--    5. Window criado ANTES do botão flutuante
-- ============================================================

-- SERVICES
local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local RS              = game:GetService("ReplicatedStorage")
local WS              = game:GetService("Workspace")
local UIS             = game:GetService("UserInputService")

local player  = Players.LocalPlayer
local placeId = game.PlaceId

-- ============================================================
-- FIX #1: FLUENT LOAD COM RETRY
-- Codex pode falhar na primeira tentativa de HttpGet
-- ============================================================
local Fluent, SaveManager, InterfaceManager

local function tryLoad(url, attempts)
    for i = 1, (attempts or 3) do
        local ok, result = pcall(function()
            return loadstring(game:HttpGet(url, true))()
        end)
        if ok then return result end
        warn("[CatEmpire] Tentativa " .. i .. " falhou para: " .. url)
        task.wait(1.5)
    end
    error("[CatEmpire] Falha ao carregar: " .. url)
end

Fluent           = tryLoad("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua")
SaveManager      = tryLoad("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua")
InterfaceManager = tryLoad("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua")

-- ============================================================
-- FIRE MANAGER
-- ============================================================
local FireManager = {}
FireManager._cache = {}

function FireManager:_find(path)
    if self._cache[path] then return self._cache[path] end
    local parts = string.split(path, ".")
    local obj = RS
    for _, part in ipairs(parts) do
        if not obj then obj = nil break end
        obj = obj:FindFirstChild(part)
            or obj:FindFirstChild(part:sub(1,1):upper() .. part:sub(2))
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
    local result = search(RS, 0)
    if result then self._cache[path] = result end
    return result
end

function FireManager:Fire(path, ...)
    local r = self:_find(path)
    if r and r:IsA("RemoteEvent") then
        pcall(function() r:FireServer(...) end)
    else
        warn("[FireManager] RemoteEvent não encontrado: " .. path)
    end
end

function FireManager:Invoke(path, ...)
    local r = self:_find(path)
    if r and r:IsA("RemoteFunction") then
        local ok, result = pcall(function() return r:InvokeServer(...) end)
        if ok then return result end
        warn("[FireManager] InvokeServer falhou: " .. path)
    else
        warn("[FireManager] RemoteFunction não encontrado: " .. path)
    end
    return nil
end

-- ============================================================
-- FIX #4: SAFETY MANAGER — loop corrigido
-- thread era registrado DEPOIS do spawn, causando loop morto
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
    for key in pairs(self._threads) do self:Kill(key) end
end

function Safety:IsActive(key)
    return self._active[key] == true
end

function Safety:Loop(key, interval, fn)
    self:Kill(key)
    self._active[key] = true
    -- FIX: registra a flag ANTES do spawn para o while ver
    local t
    t = task.spawn(function()
        while self._active[key] do
            task.wait(interval > 0 and interval or 0.1)
            if self._active[key] then
                pcall(fn)
            end
        end
        self._threads[key] = nil
    end)
    self._threads[key] = t
end

function Safety:Toggle(key, enabled, interval, fn)
    if enabled then
        self:Loop(key, interval, fn)
    else
        self:Kill(key)
    end
end

-- ============================================================
-- FIGHTERS SYSTEM
-- ============================================================
local selectedFighterUID  = ""
local selectedFighterName = "Nenhum"
local fighterDropdownRef  = nil

local function scanFighters()
    local list = {}
    local seen = {}
    pcall(function()
        local roots = {}
        local client = WS:FindFirstChild("Client")
        local server = WS:FindFirstChild("Server")
        if client then
            local f = client:FindFirstChild("Fighters") or client:FindFirstChild("Warriors")
            if f then table.insert(roots, f) end
        end
        if server then
            local f = server:FindFirstChild("Fighters") or server:FindFirstChild("Warriors")
            if f then table.insert(roots, f) end
        end
        for _, root in ipairs(roots) do
            local myF = root:FindFirstChild(tostring(player.UserId))
                     or root:FindFirstChild(player.Name)
            if not myF then continue end
            for _, fighter in ipairs(myF:GetChildren()) do
                local uid = fighter.Name
                if seen[uid] then continue end
                seen[uid] = true
                local name   = fighter:GetAttribute("Name")
                            or fighter:GetAttribute("CharacterName")
                            or fighter:GetAttribute("WarriorName")
                            or "Unknown"
                local rarity  = fighter:GetAttribute("Rarity") or ""
                local level   = fighter:GetAttribute("Level")   or 1
                local equipped = fighter:GetAttribute("Equipped")
                              or fighter:GetAttribute("Enabled")
                table.insert(list, {
                    UID      = uid,
                    Name     = tostring(name),
                    Rarity   = tostring(rarity),
                    Level    = level,
                    Equipped = (equipped == true),
                    Display  = tostring(name) .. " [" .. tostring(rarity) .. "] Lv." .. tostring(level),
                })
            end
        end
    end)
    return list
end

-- ============================================================
-- ENEMIES SYSTEM
-- ============================================================
local enemyCache       = {}
local selectedEnemyUID = ""

local function scanEnemies()
    local list = {}
    pcall(function()
        local server = WS:FindFirstChild("Server")
        if not server then return end
        local enemies = server:FindFirstChild("Enemies")
        if not enemies then return end
        for _, worldFolder in ipairs(enemies:GetChildren()) do
            if worldFolder.Name == "Lobby" then continue end
            for _, enemy in ipairs(worldFolder:GetChildren()) do
                local uid = enemy:GetAttribute("ID")
                          or enemy:GetAttribute("UID")
                          or enemy:GetAttribute("Id")
                if not uid then continue end
                local hp = enemy:GetAttribute("Health") or enemy:GetAttribute("HP") or 0
                if hp ~= hp or hp == math.huge or hp <= 0 then continue end
                local name = enemy.Name
                table.insert(list, {
                    UID      = tostring(uid),
                    Name     = name,
                    World    = worldFolder.Name,
                    Instance = enemy,
                })
            end
        end
    end)
    return list
end

local function getNearestEnemyUID()
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local server = WS:FindFirstChild("Server")
    if not server then return nil end
    local enemies = server:FindFirstChild("Enemies")
    if not enemies then return nil end
    local nearest, nearestDist = nil, math.huge
    for _, worldFolder in ipairs(enemies:GetChildren()) do
        if worldFolder.Name == "Lobby" then continue end
        for _, enemy in ipairs(worldFolder:GetChildren()) do
            local uid = enemy:GetAttribute("ID") or enemy:GetAttribute("UID") or enemy:GetAttribute("Id")
            if not uid then continue end
            local hp = enemy:GetAttribute("Health") or enemy:GetAttribute("HP") or 0
            if hp ~= hp or hp == math.huge or hp <= 0 then continue end
            local part = enemy:IsA("BasePart") and enemy
                      or enemy:FindFirstChildWhichIsA("BasePart", true)
            if not part then continue end
            local dist = (hrp.Position - part.Position).Magnitude
            if dist < nearestDist then
                nearestDist = dist
                nearest     = tostring(uid)
            end
        end
    end
    return nearest
end

local function getEquippedFighterUIDs()
    local uids = {}
    pcall(function()
        local server = WS:FindFirstChild("Server")
        if not server then return end
        local fighters = server:FindFirstChild("Fighters") or server:FindFirstChild("Warriors")
        if not fighters then return end
        local myF = fighters:FindFirstChild(tostring(player.UserId))
                 or fighters:FindFirstChild(player.Name)
        if not myF then return end
        for _, f in ipairs(myF:GetChildren()) do
            local equipped = f:GetAttribute("Equipped") or f:GetAttribute("Enabled")
            if equipped == true then
                table.insert(uids, f.Name)
            end
        end
    end)
    return uids
end

-- ============================================================
-- ROLLBACK SYSTEM
-- ============================================================
local rollbackActive    = false
local rollbackSnapshot  = nil
local rollbackConnList  = {}   -- FIX: lista completa de conexões
local rollbackTime      = nil
local rollbackSaveTimer = 0
local rollbackJobId     = nil

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = deepCopy(v) end
    return c
end

local function startRollbackCapture()
    rollbackSnapshot  = nil
    rollbackTime      = nil
    rollbackSaveTimer = 0
    rollbackJobId     = game.JobId
    rollbackConnList  = {}

    local function tryCapture(args)
        for _, arg in ipairs(args) do
            if type(arg) == "table" and (arg.Fighters or arg.Warriors or arg.Coins or arg.Inventory) then
                if rollbackSnapshot == nil then
                    rollbackSnapshot  = deepCopy(arg)
                    rollbackTime      = os.date("%H:%M:%S")
                    rollbackSaveTimer = 0
                    task.spawn(function()
                        while rollbackActive do
                            task.wait(1)
                            rollbackSaveTimer += 1
                        end
                    end)
                    Fluent:Notify({
                        Title   = "Rollback",
                        Content = "Estado capturado às " .. rollbackTime .. "!\n~90s antes do próximo save.",
                        Duration = 4,
                    })
                    return true
                end
            end
        end
        return false
    end

    pcall(function()
        for _, obj in ipairs(RS:GetDescendants()) do
            if obj:IsA("RemoteEvent") then
                local conn = obj.OnClientEvent:Connect(function(...)
                    if not rollbackActive then return end
                    tryCapture({...})
                end)
                table.insert(rollbackConnList, conn)
            end
        end
    end)

    Fluent:Notify({
        Title   = "Rollback",
        Content = "Captura ativada. Aguardando sync de dados...",
        Duration = 3,
    })
end

local function stopRollbackCapture()
    for _, conn in ipairs(rollbackConnList) do
        pcall(function() conn:Disconnect() end)
    end
    rollbackConnList = {}
end

local function executeRollback()
    if not rollbackSnapshot then
        Fluent:Notify({
            Title    = "Rollback",
            Content  = "Nenhum estado capturado! Ative o toggle primeiro.",
            Duration = 3,
        })
        return
    end
    if rollbackSaveTimer >= 90 then
        Fluent:Notify({
            Title    = "Rollback — RISCO",
            Content  = rollbackSaveTimer .. "s passados. Servidor pode ter salvado.",
            Duration = 4,
        })
        task.wait(1.5)
    end
    Safety:KillAll()
    stopRollbackCapture()
    rollbackActive = false
    Fluent:Notify({
        Title   = "Rollback",
        Content = "Executando rejoin...\nServidor novo vai carregar estado de " .. (rollbackTime or "?"),
        Duration = 3,
    })
    task.wait(0.5)
    local ok = pcall(function()
        TeleportService:TeleportAsync(placeId, {player})
    end)
    if not ok then
        pcall(function() TeleportService:Teleport(placeId) end)
    end
end

-- ============================================================
-- FIX #5: FLUENT WINDOW — criado ANTES do botão flutuante
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
-- FIX #2 + #3: BOTÃO FLUTUANTE
-- - Vai DIRETO para PlayerGui (sem tentar CoreGui — bloqueado no Codex)
-- - fluentSG buscado com loop robusto após window criar
-- ============================================================
local windowVisible = true
local pg = player:WaitForChild("PlayerGui", 10)

local minSG = Instance.new("ScreenGui")
minSG.Name           = "CatEmpireMinGui"
minSG.ResetOnSpawn   = false
minSG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
minSG.DisplayOrder   = 999
-- FIX #3: PlayerGui direto — Codex não tem CoreGui
minSG.Parent = pg

local minFrame = Instance.new("Frame", minSG)
minFrame.Size             = UDim2.fromOffset(60, 60)
minFrame.Position         = UDim2.new(0, 8, 0.5, -30)
minFrame.BackgroundColor3 = Color3.fromRGB(0, 80, 190)
minFrame.BackgroundTransparency = 0.08
minFrame.ZIndex           = 50
Instance.new("UICorner", minFrame).CornerRadius = UDim.new(0, 12)
Instance.new("UIStroke", minFrame).Color        = Color3.fromRGB(60, 140, 255)

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

-- FIX #2: busca fluentSG com loop robusto, tenta por até 10s
local fluentSG = nil
task.spawn(function()
    for _ = 1, 20 do
        task.wait(0.5)
        -- Tenta nome exato "Fluent"
        local found = pg:FindFirstChild("Fluent")
        if found and found:IsA("ScreenGui") then
            fluentSG = found
            break
        end
        -- Fallback: qualquer ScreenGui com Frame + UICorner (estrutura Fluent)
        for _, sg in ipairs(pg:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Name ~= "CatEmpireMinGui" then
                for _, ch in ipairs(sg:GetChildren()) do
                    if ch:IsA("Frame") and ch:FindFirstChildOfClass("UICorner") then
                        fluentSG = sg
                        break
                    end
                end
                if fluentSG then break end
            end
        end
        if fluentSG then break end
    end
    if not fluentSG then
        warn("[CatEmpire] fluentSG não encontrado — botão CE usará KeyCode fallback")
    end
end)

local function doMinimize()
    windowVisible = not windowVisible
    if fluentSG then
        pcall(function() fluentSG.Enabled = windowVisible end)
    else
        -- Fallback: simula RightControl
        pcall(function()
            local VIM = game:GetService("VirtualInputManager")
            VIM:SendKeyEvent(true,  Enum.KeyCode.RightControl, false, game)
            task.wait(0.05)
            VIM:SendKeyEvent(false, Enum.KeyCode.RightControl, false, game)
        end)
        windowVisible = not windowVisible
    end
    minFrame.BackgroundColor3 = windowVisible
        and Color3.fromRGB(0, 80, 190)
        or  Color3.fromRGB(140, 30, 30)
    minLbl.Text = windowVisible and "CE" or "▶"
end

-- Drag logic
local _dragging, _moved, _dragStart, _startPos = false, false, nil, nil

minHit.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        _dragging  = true
        _moved     = false
        _dragStart = Vector2.new(i.Position.X, i.Position.Y)
        _startPos  = minFrame.Position
    end
end)

UIS.InputChanged:Connect(function(i)
    if not _dragging then return end
    if i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch then
        local dx = i.Position.X - _dragStart.X
        local dy = i.Position.Y - _dragStart.Y
        if math.abs(dx) > 5 or math.abs(dy) > 5 then
            _moved = true
            minFrame.Position = UDim2.new(
                _startPos.X.Scale, _startPos.X.Offset + dx,
                _startPos.Y.Scale, _startPos.Y.Offset + dy
            )
        end
    end
end)

UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        if not _dragging then return end
        _dragging = false
        if not _moved then doMinimize() end
        _moved = false
    end
end)

-- ============================================================
-- TABS
-- ============================================================
local Tabs = {
    Main      = Window:AddTab({ Title = "Main",      Icon = "sword" }),
    Combat    = Window:AddTab({ Title = "Combat",    Icon = "zap" }),
    Fighters  = Window:AddTab({ Title = "Fighters",  Icon = "user" }),
    Inventory = Window:AddTab({ Title = "Inventory", Icon = "package" }),
    Summon    = Window:AddTab({ Title = "Summon",    Icon = "star" }),
    Rollback  = Window:AddTab({ Title = "Rollback",  Icon = "rotate-ccw" }),
    Teleport  = Window:AddTab({ Title = "Teleport",  Icon = "map-pin" }),
    Settings  = Window:AddTab({ Title = "Settings",  Icon = "settings" }),
    Info      = Window:AddTab({ Title = "Info",      Icon = "info" }),
}

local Options = Fluent.Options

-- ============================================================
-- TAB: MAIN
-- ============================================================
Tabs.Main:AddSection("Automatizacoes Gerais")

Tabs.Main:AddToggle("AutoEquip", { Title = "Auto Equip Best", Default = false })
Options.AutoEquip:OnChanged(function(v)
    Safety:Toggle("AutoEquip", v, 5, function()
        FireManager:Fire("warriors.equipBest")
    end)
end)

Tabs.Main:AddButton({
    Title    = "Equip Best (1x)",
    Callback = function()
        FireManager:Fire("warriors.equipBest")
        Fluent:Notify({ Title="Inventory", Content="Equip Best enviado", Duration=2 })
    end,
})

Tabs.Main:AddToggle("AutoStream", { Title = "Auto Stream Retrieve", Default = false })
Options.AutoStream:OnChanged(function(v)
    Safety:Toggle("AutoStream", v, 30, function()
        FireManager:Fire("stream.retrieve")
    end)
end)

-- ============================================================
-- TAB: COMBAT
-- ============================================================
Tabs.Combat:AddSection("Auto Combat")

local combatEnemyUID  = ""
local combatEnemyList = { "Nearest" }
local combatDropdown  = Tabs.Combat:AddDropdown("CombatEnemy", {
    Title   = "Inimigo Alvo",
    Values  = combatEnemyList,
    Default = "Nearest",
})
combatDropdown:OnChanged(function(v)
    combatEnemyUID = (v == "Nearest") and "" or v
end)

Tabs.Combat:AddButton({
    Title    = "Escanear Inimigos",
    Callback = function()
        local list = scanEnemies()
        local values = { "Nearest" }
        for _, e in ipairs(list) do
            table.insert(values, e.Name .. " [" .. e.World .. "] " .. e.UID)
        end
        combatDropdown:SetValues(values)
        combatDropdown:SetValue("Nearest")
        combatEnemyUID = ""
        Fluent:Notify({
            Title   = "Combat",
            Content = #list .. " inimigo(s) encontrado(s)",
            Duration = 3,
        })
    end,
})

Tabs.Combat:AddToggle("AutoCombat", { Title = "Auto Combat", Default = false })
Options.AutoCombat:OnChanged(function(v)
    Safety:Toggle("AutoCombat", v, 0.5, function()
        local uid = combatEnemyUID ~= "" and combatEnemyUID or getNearestEnemyUID()
        if not uid then return end
        local fighters = getEquippedFighterUIDs()
        if #fighters == 0 then return end
        FireManager:Fire("enemies.sendAndRetreat", uid, fighters)
    end)
end)

Tabs.Combat:AddSection("Manual")

Tabs.Combat:AddButton({
    Title    = "Atacar Mais Proximo (1x)",
    Callback = function()
        local uid = getNearestEnemyUID()
        if not uid then
            Fluent:Notify({ Title="Combat", Content="Nenhum inimigo encontrado!", Duration=2 })
            return
        end
        local fighters = getEquippedFighterUIDs()
        if #fighters == 0 then
            Fluent:Notify({ Title="Combat", Content="Nenhum fighter equipado!", Duration=2 })
            return
        end
        FireManager:Fire("enemies.sendAndRetreat", uid, fighters)
        Fluent:Notify({ Title="Combat", Content="Ataque enviado → " .. uid, Duration=2 })
    end,
})

-- ============================================================
-- TAB: FIGHTERS
-- ============================================================
Tabs.Fighters:AddSection("Selecao de Fighter")

local fighterParagraph = Tabs.Fighters:AddParagraph({
    Title   = "Selecionado",
    Content = "Nenhum — clique em Escanear",
})

local function updateFighterParagraph()
    fighterParagraph:SetDesc(selectedFighterName .. "\nUID: " .. selectedFighterUID)
end

local fighterDropdownValues = { "Nenhum" }
fighterDropdownRef = Tabs.Fighters:AddDropdown("FighterSelect", {
    Title   = "Fighter",
    Values  = fighterDropdownValues,
    Default = "Nenhum",
})
fighterDropdownRef:OnChanged(function(v)
    if v == "Nenhum" then return end
    local uid = v:match("| (.+)$")
    if uid then
        selectedFighterUID  = uid
        selectedFighterName = v:match("^(.+) |") or v
        updateFighterParagraph()
    end
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
        for _, f in ipairs(list) do
            table.insert(values, f.Display .. " | " .. f.UID)
        end
        fighterDropdownRef:SetValues(values)
        fighterDropdownRef:SetValue("Nenhum")
        selectedFighterUID  = list[1].UID
        selectedFighterName = list[1].Display
        updateFighterParagraph()
        Fluent:Notify({
            Title   = "Fighters",
            Content = #list .. " fighter(s) encontrado(s).",
            Duration = 3,
        })
    end,
})

Tabs.Fighters:AddSection("Trait Reroll")

local traitTarget = ""
local TRAIT_LIST = {
    "Livre",
    "Fortune", "Swift", "Fortune II", "Swift II",
    "Legendary", "Mythic", "Secret",
    "God", "Divine", "Ultimate",
}

local traitDropdown = Tabs.Fighters:AddDropdown("TraitTarget", {
    Title   = "Trait Desejado",
    Values  = TRAIT_LIST,
    Default = "Livre",
})
traitDropdown:OnChanged(function(v)
    traitTarget = (v == "Livre") and "" or v
end)

local traitCounter = 0
local traitCountParagraph = Tabs.Fighters:AddParagraph({
    Title   = "Rerolls",
    Content = "0 rerolls realizados",
})

local function doTraitReroll()
    if selectedFighterUID == "" then return end
    local result = FireManager:Invoke("traits.reroll", selectedFighterUID, traitTarget, false)
    traitCounter += 1
    traitCountParagraph:SetDesc(traitCounter .. " rerolls realizados")
    if traitTarget ~= "" and type(result) == "string" and result:find(traitTarget) then
        Safety:Kill("AutoTraitReroll")
        Options.AutoTraitReroll:SetValue(false)
        Fluent:Notify({
            Title   = "Trait Reroll",
            Content = "Trait '" .. traitTarget .. "' obtido! Parado.",
            Duration = 5,
        })
    end
end

Tabs.Fighters:AddToggle("AutoTraitReroll", { Title = "Auto Trait Reroll", Default = false })
Options.AutoTraitReroll:OnChanged(function(v)
    if v and selectedFighterUID == "" then
        Fluent:Notify({ Title="Fighters", Content="Selecione um fighter primeiro!", Duration=3 })
        Options.AutoTraitReroll:SetValue(false)
        return
    end
    if v then traitCounter = 0 end
    Safety:Toggle("AutoTraitReroll", v, 0.5, doTraitReroll)
end)

Tabs.Fighters:AddButton({
    Title    = "Trait Reroll (1x)",
    Callback = function()
        if selectedFighterUID == "" then
            Fluent:Notify({ Title="Fighters", Content="Selecione um fighter primeiro!", Duration=2 })
            return
        end
        doTraitReroll()
        Fluent:Notify({ Title="Traits", Content="Reroll enviado", Duration=2 })
    end,
})

-- ============================================================
-- TAB: INVENTORY
-- ============================================================
Tabs.Inventory:AddSection("Equip")

Tabs.Inventory:AddToggle("AutoEquipInv", { Title = "Auto Equip Best", Default = false })
Options.AutoEquipInv:OnChanged(function(v)
    Safety:Toggle("AutoEquipInv", v, 5, function()
        FireManager:Fire("warriors.equipBest")
    end)
end)

Tabs.Inventory:AddButton({
    Title    = "Equip Best (1x)",
    Callback = function()
        FireManager:Fire("warriors.equipBest")
        Fluent:Notify({ Title="Inventory", Content="Equip Best enviado", Duration=2 })
    end,
})

Tabs.Inventory:AddSection("Dismantle")

Tabs.Inventory:AddParagraph({
    Title   = "Como usar",
    Content = "Escaneie os fighters, marque os que quer desmantelar na lista, e clique em Dismantle Selecionados.",
})

local dismantleRarities = {}
local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

Tabs.Inventory:AddDropdown("DismantleRarity", {
    Title   = "Raridade Maxima para Desmantelar",
    Values  = RARITIES,
    Default = "Rare",
})

Tabs.Inventory:AddButton({
    Title    = "Dismantle por Raridade",
    Callback = function()
        local maxRarity  = Options.DismantleRarity.Value or "Rare"
        local rarityRank = {}
        for i, r in ipairs(RARITIES) do rarityRank[r] = i end
        local maxRank = rarityRank[maxRarity] or 3
        local list = scanFighters()
        local toDismantle = {}
        for _, f in ipairs(list) do
            local rank = rarityRank[f.Rarity] or 0
            if rank <= maxRank and not f.Equipped then
                table.insert(toDismantle, f.UID)
            end
        end
        if #toDismantle == 0 then
            Fluent:Notify({ Title="Dismantle", Content="Nenhum fighter para desmantelar.", Duration=3 })
            return
        end
        local result = FireManager:Invoke("warriors.dismantle", toDismantle)
        Fluent:Notify({
            Title   = "Dismantle",
            Content = #toDismantle .. " fighter(s) desmantados.",
            Duration = 3,
        })
    end,
})

-- ============================================================
-- TAB: SUMMON
-- ============================================================
Tabs.Summon:AddSection("Auto Summon")

local summonEggType = "Ninja"
local EGG_TYPES = { "Ninja", "Dragon", "Slayer", "Pirate", "Hero", "World1", "World2", "World3" }

Tabs.Summon:AddDropdown("SummonEgg", {
    Title   = "Tipo de Ovo",
    Values  = EGG_TYPES,
    Default = "Ninja",
})
Options.SummonEgg:OnChanged(function(v)
    summonEggType = v
    if Safety:IsActive("AutoSummonKeep") then
        FireManager:Fire("eggs.setAuto", summonEggType, true)
    end
end)

Tabs.Summon:AddToggle("AutoSummon", { Title = "Auto Summon", Default = false })
Options.AutoSummon:OnChanged(function(v)
    if v then
        FireManager:Fire("eggs.setAuto", summonEggType, true)
        Safety:Loop("AutoSummonKeep", 3, function()
            FireManager:Fire("eggs.setAuto", summonEggType, true)
        end)
    else
        Safety:Kill("AutoSummonKeep")
        FireManager:Fire("eggs.setAuto", summonEggType, false)
        Fluent:Notify({ Title="Summon", Content="Auto summon desativado.", Duration=2 })
    end
end)

Tabs.Summon:AddButton({
    Title    = "Summon Manual (1x)",
    Callback = function()
        FireManager:Fire("eggs.setAuto", summonEggType, true)
        task.wait(0.3)
        FireManager:Fire("eggs.setAuto", summonEggType, false)
        Fluent:Notify({ Title="Summon", Content="Summon enviado: " .. summonEggType, Duration=2 })
    end,
})

-- ============================================================
-- TAB: ROLLBACK
-- ============================================================
Tabs.Rollback:AddSection("Rollback")

Tabs.Rollback:AddParagraph({
    Title   = "Como funciona",
    Content = "1. Ative ANTES de fazer qualquer acao\n2. Faca gacha, reroll, etc\n3. Se nao gostar: clique Executar Rollback\n4. Rejoin em servidor novo — carrega datasave anterior\n\nUse dentro de ~90s para garantir que o servidor nao salvou.",
})

local rollbackStatus = Tabs.Rollback:AddParagraph({
    Title   = "Status",
    Content = "Inativo",
})

task.spawn(function()
    while true do
        task.wait(3)
        if rollbackActive and rollbackSnapshot then
            local label = rollbackSaveTimer < 45 and "SEGURO"
                       or rollbackSaveTimer < 75 and "ATENCAO"
                       or "RISCO"
            rollbackStatus:SetDesc(
                "Snapshot: " .. (rollbackTime or "?") ..
                "\nTempo: " .. rollbackSaveTimer .. "s — " .. label
            )
        elseif rollbackActive then
            rollbackStatus:SetDesc("Aguardando sync de dados...")
        end
    end
end)

Tabs.Rollback:AddToggle("RollbackActive", { Title = "Ativar Captura de Estado", Default = false })
Options.RollbackActive:OnChanged(function(v)
    rollbackActive = v
    if v then
        rollbackSnapshot  = nil
        rollbackSaveTimer = 0
        startRollbackCapture()
        rollbackStatus:SetDesc("Captura ativa...")
    else
        stopRollbackCapture()
        if rollbackSnapshot then
            rollbackStatus:SetDesc("Pausado — snapshot de " .. (rollbackTime or "?") .. " disponivel")
        else
            rollbackStatus:SetDesc("Desativado")
        end
    end
end)

Tabs.Rollback:AddButton({
    Title    = "Executar Rollback (Rejoin)",
    Callback = function()
        executeRollback()
    end,
})

-- ============================================================
-- TAB: TELEPORT
-- ============================================================
Tabs.Teleport:AddSection("Mundos")

local WORLDS = {
    "Leaf Village", "Dragon Town", "Slayer Village",
    "Pirate Island", "Solo City", "Z City", "Hollow Island",
}

for _, world in ipairs(WORLDS) do
    local w = world
    Tabs.Teleport:AddButton({
        Title    = w,
        Callback = function()
            local char = player.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            local server = WS:FindFirstChild("Server")
            local enemies = server and server:FindFirstChild("Enemies")
            local worldFolder = enemies and enemies:FindFirstChild(w)
            if hrp and worldFolder then
                local firstEnemy = worldFolder:GetChildren()[1]
                if firstEnemy then
                    local part = firstEnemy:IsA("BasePart") and firstEnemy
                              or firstEnemy:FindFirstChildWhichIsA("BasePart", true)
                    if part then
                        hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 5, 10))
                        Fluent:Notify({ Title="Teleporte", Content="Indo para " .. w, Duration=2 })
                        return
                    end
                end
            end
            Fluent:Notify({ Title="Teleporte", Content="Mundo nao encontrado: " .. w, Duration=3 })
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

Tabs.Info:AddParagraph({ Title = "Jogo",    Content = "Anime Warriors 3" })
Tabs.Info:AddParagraph({ Title = "Desenvolvido por", Content = "Danonin" })
Tabs.Info:AddParagraph({ Title = "Discord", Content = "discord.gg/qDeZ9sEdGY" })

Tabs.Info:AddButton({
    Title    = "Copiar Discord",
    Callback = function()
        setclipboard("https://discord.gg/qDeZ9sEdGY")
        Fluent:Notify({ Title="Copiado!", Content="Link do Discord copiado.", Duration=2 })
    end,
})

Tabs.Info:AddParagraph({
    Title   = "Remotes Confirmados",
    Content = "warriors.equipBest\neggs.setAuto\ntraits.reroll\nenemies.sendAndRetreat\nstream.retrieve\nwarriors.dismantle",
})

Tabs.Info:AddParagraph({
    Title   = "Keybind",
    Content = "RightControl — Mostrar/Ocultar GUI\nBotao CE — Toggle/Arrastar",
})

Tabs.Info:AddParagraph({
    Title   = "Changelog v5.23",
    Content = "- Fix: UI abre corretamente no Codex\n- Fix: CoreGui bloqueado → usa PlayerGui\n- Fix: Fluent carrega com retry\n- Fix: fluentSG busca robusta (loop 10s)\n- Fix: Safety loops não morrem mais\n- Fix: rollbackConnList completa",
})

-- ============================================================
-- INIT
-- ============================================================
SaveManager:LoadAutoloadConfig()
Window:SelectTab(1)

Fluent:Notify({
    Title    = "Cat Empire v5.23",
    Content  = "Anime Warriors 3 — Codex fix aplicado!",
    Duration = 4,
})
