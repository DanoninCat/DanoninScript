-- ============================================================
--  CAT EMPIRE | v5.0 | CODED FOR DANONIN
--  UI: Fluent Library
-- ============================================================

-- SERVICES
local Players         = game:GetService("Players")
local TweenService    = game:GetService("TweenService")
local RunService      = game:GetService("RunService")
local Stats           = game:GetService("Stats")
local WS              = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local RS              = game:GetService("ReplicatedStorage")

local player  = Players.LocalPlayer
local placeId = game.PlaceId

-- ============================================================
-- FLUENT LOAD
-- ============================================================
local Fluent     = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- ============================================================
-- BRIDGE
-- ============================================================
local Bridge

local function getBridge()
    if Bridge then return Bridge end
    local remotes = RS:FindFirstChild("Remotes")
    if remotes then Bridge = remotes:FindFirstChild("Bridge") end
    return Bridge
end

local function fire(...)
    local b = getBridge()
    if b then b:FireServer(table.unpack({...})) end
end

-- ============================================================
-- HELPERS
-- ============================================================
local function getEquippedFighterUIDs()
    local uids = {}
    pcall(function()
        local serverFighters = WS:FindFirstChild("Server") and WS.Server:FindFirstChild("Fighters")
        if not serverFighters then return end
        local myFolder = serverFighters:FindFirstChild(player.Name)
                      or serverFighters:FindFirstChild(tostring(player.UserId))
        if not myFolder then return end
        for _, fighter in ipairs(myFolder:GetChildren()) do
            local uid = fighter:GetAttribute("UID")
                     or fighter:GetAttribute("Id")
                     or fighter:GetAttribute("uid")
            if uid then table.insert(uids, tostring(uid)) end
        end
    end)
    return uids
end

local function getNearestEnemy()
    local char = player.Character
    if not char then return nil, nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil end
    local serverEnemies = WS:FindFirstChild("Server") and WS.Server:FindFirstChild("Enemies")
    if not serverEnemies then return nil, nil end
    local nearest, nearestDist, nearestWorld = nil, math.huge, nil
    for _, worldFolder in pairs(serverEnemies:GetChildren()) do
        for _, enemy in ipairs(worldFolder:GetChildren()) do
            local enemyHRP = enemy:FindFirstChild("HumanoidRootPart")
            local hum      = enemy:FindFirstChildOfClass("Humanoid")
            if enemyHRP and hum and hum.Health > 0 then
                local dist = (hrp.Position - enemyHRP.Position).Magnitude
                if dist < nearestDist then
                    nearest      = enemy
                    nearestDist  = dist
                    nearestWorld = worldFolder.Name
                end
            end
        end
    end
    return nearest, nearestWorld
end

-- ============================================================
-- CONSTANTES
-- ============================================================
local KNOWN_ACHIEVEMENTS = {
    "Defeat I","Defeat II","Defeat III","Defeat IV","Defeat V",
    "Luck I","Luck II","Luck III","Inventory I","Inventory II",
}

local WORLDS = {"Lobby","Leaf Village","Dragon World","Sand Village"}
local selectedWorld       = "Leaf Village"
local selectedFighterUID  = ""
local selectedFighterName = "Nenhum"
local selectedStat        = "Attack"

-- ============================================================
-- ROLLBACK
-- ============================================================
local rollbackSnapshot = nil

local function captureSnapshot()
    local snap = { time = os.time(), items = {} }
    pcall(function()
        local data = RS:FindFirstChild("Data") or RS:FindFirstChild("PlayerData")
        if data then
            local pd = data:FindFirstChild(tostring(player.UserId)) or data:FindFirstChild(player.Name)
            if pd then
                for _, v in ipairs(pd:GetDescendants()) do
                    if v:IsA("IntValue") or v:IsA("NumberValue") or v:IsA("StringValue") then
                        snap.items[v:GetFullName()] = v.Value
                    end
                end
            end
        end
    end)
    return snap
end

local function doRollback()
    TeleportService:Teleport(placeId, player)
end

-- ============================================================
-- LOOP CONTROL
-- ============================================================
local loops = {}

local function makeLoop(interval, fn)
    local t = task.spawn(function()
        while true do
            task.wait(interval)
            pcall(fn)
        end
    end)
    table.insert(loops, t)
    return t
end

local loopHandles = {}

local function toggleLoop(key, enabled, interval, fn)
    if loopHandles[key] then
        task.cancel(loopHandles[key])
        loopHandles[key] = nil
    end
    if enabled then
        loopHandles[key] = makeLoop(interval, fn)
    end
end

-- ============================================================
-- FLUENT WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title          = "Cat Empire",
    SubTitle       = "v5.0 | by Danonin",
    TabWidth       = 160,
    Size           = UDim2.fromOffset(720, 480),
    Acrylic        = true,
    Theme          = "Dark",
    MinimizeKey    = Enum.KeyCode.RightControl,
})

-- ============================================================
-- TABS
-- ============================================================
local Tabs = {
    Main      = Window:AddTab({ Title = "Main",      Icon = "sword" }),
    Rewards   = Window:AddTab({ Title = "Rewards",   Icon = "gift" }),
    Fighters  = Window:AddTab({ Title = "Fighters",  Icon = "user" }),
    Teleport  = Window:AddTab({ Title = "Teleport",  Icon = "map-pin" }),
    Rollback  = Window:AddTab({ Title = "Rollback",  Icon = "rotate-ccw" }),
    Settings  = Window:AddTab({ Title = "Settings",  Icon = "settings" }),
    Info      = Window:AddTab({ Title = "Info",      Icon = "info" }),
}

-- ============================================================
-- TAB: MAIN
-- ============================================================
local TabMain = Tabs.Main

TabMain:AddSection("Combate")

TabMain:AddToggle("AutoAttack", {
    Title   = "Auto Attack",
    Description = "Envia Click automaticamente",
    Default = false,
}):OnChanged(function(v)
    toggleLoop("AutoAttack", v, 0.05, function()
        fire("Fighters","Attack","Click")
    end)
end)

TabMain:AddToggle("AutoFarm", {
    Title   = "Auto Farm",
    Description = "Attack_All + Do_Damage em todos fighters equipados",
    Default = false,
}):OnChanged(function(v)
    toggleLoop("AutoFarm", v, 0.35, function()
        local enemy, world = getNearestEnemy()
        if not enemy or not world then return end
        fire("Fighters","Attack","Retreat_All")
        task.wait(0.05)
        fire("Fighters","Attack","Attack_All","World",enemy)
        task.wait(0.05)
        for _, uid in ipairs(getEquippedFighterUIDs()) do
            fire("Fighters","Attack","Do_Damage", uid)
            task.wait(0.02)
        end
    end)
end)

TabMain:AddToggle("AutoRetreat", {
    Title   = "Auto Retreat",
    Description = "Retreat_All periodico",
    Default = false,
}):OnChanged(function(v)
    toggleLoop("AutoRetreat", v, 20, function()
        fire("Fighters","Attack","Retreat_All")
    end)
end)

TabMain:AddSection("Utilitarios")

TabMain:AddToggle("AutoEquip", {
    Title   = "Auto Equip Best",
    Description = "Equipa os melhores fighters automaticamente",
    Default = false,
}):OnChanged(function(v)
    toggleLoop("AutoEquip", v, 3, function()
        fire("General","Fighters","Equip_Best")
    end)
end)

TabMain:AddToggle("AutoQuest", {
    Title   = "Auto Quest",
    Description = "Aceita quest do mundo selecionado",
    Default = false,
}):OnChanged(function(v)
    toggleLoop("AutoQuest", v, 15, function()
        fire("General","World_Quest","accept", selectedWorld)
    end)
end)

TabMain:AddToggle("AutoStar", {
    Title   = "Auto Star Open",
    Description = "Abre estrelas automaticamente",
    Default = false,
}):OnChanged(function(v)
    toggleLoop("AutoStar", v, 1.5, function()
        fire("General","Star","Open",1)
    end)
end)

TabMain:AddToggle("AntiAFK", {
    Title   = "Anti-AFK",
    Description = "Previne kick por inatividade",
    Default = false,
}):OnChanged(function(v)
    toggleLoop("AntiAFK", v, 30, function()
        fire("General","AntiAfk","Auto_Click",true)
        fire("General","AntiAfk","Auto_Attack",true)
    end)
    if not v then
        pcall(function()
            fire("General","AntiAfk","Auto_Click",false)
            fire("General","AntiAfk","Auto_Attack",false)
        end)
    end
end)

TabMain:AddDropdown("WorldSelect", {
    Title   = "Mundo do Auto Quest",
    Values  = WORLDS,
    Default = "Leaf Village",
}):OnChanged(function(v)
    selectedWorld = v
end)

-- ============================================================
-- TAB: REWARDS
-- ============================================================
local TabRewards = Tabs.Rewards

TabRewards:AddSection("Recompensas")

TabRewards:AddToggle("DailyRewards", {
    Title   = "Daily Rewards",
    Description = "Coleta recompensas diarias (dias 1-7)",
    Default = false,
}):OnChanged(function(v)
    toggleLoop("DailyRewards", v, 60, function()
        for day = 1, 7 do
            fire("General","DailyRewards","Claim",day)
            task.wait(0.3)
        end
    end)
end)

TabRewards:AddToggle("TimeRewards", {
    Title   = "Time Rewards",
    Description = "Coleta recompensas por tempo",
    Default = false,
}):OnChanged(function(v)
    toggleLoop("TimeRewards", v, 300, function()
        fire("General","TimeRewards","Claim",1)
    end)
end)

TabRewards:AddToggle("AutoRankUp", {
    Title   = "Auto Rank Up",
    Description = "Sobe de rank automaticamente",
    Default = false,
}):OnChanged(function(v)
    toggleLoop("AutoRankUp", v, 10, function()
        fire("General","RankUp","Up")
    end)
end)

TabRewards:AddToggle("AutoAchiev", {
    Title   = "Auto Claim Achievements",
    Description = "Coleta achievements conhecidos",
    Default = false,
}):OnChanged(function(v)
    toggleLoop("AutoAchiev", v, 5, function()
        for _, name in ipairs(KNOWN_ACHIEVEMENTS) do
            fire("General","Achievements","Claim",name)
            task.wait(0.2)
        end
    end)
end)

-- ============================================================
-- TAB: FIGHTERS
-- ============================================================
local TabFighters = Tabs.Fighters

TabFighters:AddSection("Fighter Selecionado")

local fighterLabel = TabFighters:AddParagraph({
    Title = "Selecionado",
    Content = "Nenhum — use Escanear ou UID manual",
})

local function updateFighterLabel()
    fighterLabel:SetDesc(selectedFighterName .. "  |  " .. (selectedFighterUID ~= "" and selectedFighterUID or "sem UID"))
end

TabFighters:AddButton({
    Title = "Escanear Fighters",
    Description = "Busca fighters no Workspace.Server.Fighters",
    Callback = function()
        local found = {}

        -- Workspace (prioridade)
        pcall(function()
            local sf = WS:FindFirstChild("Server") and WS.Server:FindFirstChild("Fighters")
            if sf then
                local myF = sf:FindFirstChild(player.Name) or sf:FindFirstChild(tostring(player.UserId))
                if myF then
                    for _, f in ipairs(myF:GetChildren()) do
                        local uid  = f:GetAttribute("UID") or f:GetAttribute("Id") or f:GetAttribute("uid")
                        local name = f:GetAttribute("FighterName") or f:GetAttribute("Name") or f:GetAttribute("Type") or f.Name
                        if uid then table.insert(found,{Name=tostring(name),UID=tostring(uid)}) end
                    end
                end
            end
        end)

        -- Fallback PlayerGui
        if #found == 0 then
            pcall(function()
                for _, d in ipairs(player.PlayerGui:GetDescendants()) do
                    local uid = d:GetAttribute("UID") or d:GetAttribute("FighterUID") or d:GetAttribute("Id")
                    if uid then
                        table.insert(found,{
                            Name = d:GetAttribute("FighterName") or d:GetAttribute("Name") or d.Name,
                            UID  = tostring(uid)
                        })
                    end
                end
            end)
        end

        if #found > 0 then
            -- Seleciona o primeiro automaticamente e mostra no label
            selectedFighterUID  = found[1].UID
            selectedFighterName = found[1].Name
            updateFighterLabel()
            Fluent:Notify({
                Title   = "Fighters Detectados",
                Content = #found .. " fighter(s) encontrado(s). Primeiro selecionado: " .. found[1].Name,
                Duration = 4,
            })
        else
            Fluent:Notify({
                Title   = "Scan",
                Content = "Nenhum fighter detectado. Use UID manual.",
                Duration = 3,
            })
        end
    end,
})

TabFighters:AddInput("ManualUID", {
    Title       = "UID Manual",
    Description = "Cole o UID do fighter aqui",
    Placeholder = "ex: b9-e9ba-4c74-a867-91a391c84db0",
    Numeric     = false,
}):OnChanged(function(v)
    -- confirma ao pressionar enter / perder foco — capturado no botão abaixo
end)

TabFighters:AddButton({
    Title = "Usar UID Manual",
    Callback = function()
        local uid = Fluent.Options.ManualUID and Fluent.Options.ManualUID.Value or ""
        uid = uid:gsub("%s+","")
        if uid == "" then
            Fluent:Notify({ Title="Erro", Content="UID vazio!", Duration=2 })
            return
        end
        selectedFighterUID  = uid
        selectedFighterName = "Manual"
        updateFighterLabel()
        Fluent:Notify({ Title="UID Definido", Content=uid, Duration=3 })
    end,
})

TabFighters:AddSection("Traits Reroll")

TabFighters:AddToggle("AutoTraits", {
    Title   = "Auto Traits Reroll",
    Default = false,
}):OnChanged(function(v)
    toggleLoop("AutoTraits", v, 1.5, function()
        if selectedFighterUID == "" then return end
        fire("General","Traits","Reroll",selectedFighterUID,{})
    end)
end)

TabFighters:AddButton({
    Title = "Traits Reroll (1x)",
    Callback = function()
        if selectedFighterUID == "" then
            Fluent:Notify({ Title="Erro", Content="Selecione um fighter primeiro!", Duration=2 })
            return
        end
        fire("General","Traits","Reroll",selectedFighterUID,{})
        Fluent:Notify({ Title="Traits", Content="Reroll enviado", Duration=2 })
    end,
})

TabFighters:AddSection("Stats Reroll")

TabFighters:AddToggle("AutoStats", {
    Title   = "Auto Stats Reroll",
    Default = false,
}):OnChanged(function(v)
    toggleLoop("AutoStats", v, 1.5, function()
        if selectedFighterUID == "" then return end
        fire("General","StatsReroll","Reroll",selectedFighterUID,{})
    end)
end)

TabFighters:AddButton({
    Title = "Stats Reroll (1x)",
    Callback = function()
        if selectedFighterUID == "" then
            Fluent:Notify({ Title="Erro", Content="Selecione um fighter primeiro!", Duration=2 })
            return
        end
        fire("General","StatsReroll","Reroll",selectedFighterUID,{})
        Fluent:Notify({ Title="Stats", Content="Reroll enviado", Duration=2 })
    end,
})

TabFighters:AddSection("Lock Stat")

TabFighters:AddDropdown("LockStatDrop", {
    Title   = "Stat para Lockear",
    Values  = {"Attack","Defense","Health","Speed"},
    Default = "Attack",
}):OnChanged(function(v)
    selectedStat = v
end)

TabFighters:AddButton({
    Title = "Aplicar Lock",
    Callback = function()
        if selectedFighterUID == "" then
            Fluent:Notify({ Title="Erro", Content="Selecione um fighter primeiro!", Duration=2 })
            return
        end
        fire("General","StatsReroll","Lock",selectedFighterUID,selectedStat)
        Fluent:Notify({ Title="Lock", Content=selectedStat .. " lockado", Duration=2 })
    end,
})

-- ============================================================
-- TAB: TELEPORT
-- ============================================================
local TabTeleport = Tabs.Teleport

TabTeleport:AddSection("Mundos")

for _, world in ipairs(WORLDS) do
    TabTeleport:AddButton({
        Title       = world,
        Description = "Teleportar para " .. world,
        Callback    = function()
            fire("General","Teleport","Teleport", world)
            Fluent:Notify({ Title="Teleporte", Content="Indo para " .. world .. "...", Duration=3 })
        end,
    })
end

-- ============================================================
-- TAB: ROLLBACK
-- ============================================================
local TabRollback = Tabs.Rollback

TabRollback:AddSection("Sistema de Rollback")

TabRollback:AddParagraph({
    Title   = "Como funciona",
    Content = "Salve um snapshot do seu estado atual. Se algo der errado, execute o Rollback — o script faz um rejoin via TeleportService antes do servidor salvar os novos dados.",
})

local snapLabel = TabRollback:AddParagraph({
    Title   = "Snapshot",
    Content = "Nenhum snapshot salvo",
})

TabRollback:AddButton({
    Title = "Salvar Snapshot",
    Description = "Registra o estado atual",
    Callback = function()
        rollbackSnapshot = captureSnapshot()
        local t = os.date("%H:%M:%S", rollbackSnapshot.time)
        snapLabel:SetDesc("Salvo as " .. t)
        Fluent:Notify({ Title="Snapshot", Content="Salvo as " .. t, Duration=3 })
    end,
})

TabRollback:AddButton({
    Title = "Executar Rollback",
    Description = "Rejoin rapido para voltar ao snapshot",
    Callback = function()
        if not rollbackSnapshot then
            Fluent:Notify({ Title="Erro", Content="Salve um snapshot primeiro!", Duration=3 })
            return
        end
        Fluent:Notify({ Title="Rollback", Content="Executando rejoin...", Duration=2 })
        task.wait(0.5)
        doRollback()
    end,
})

-- ============================================================
-- TAB: SETTINGS
-- ============================================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("CatEmpire")
SaveManager:SetFolder("CatEmpire/configs")

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

-- ============================================================
-- TAB: INFO
-- ============================================================
local TabInfo = Tabs.Info

TabInfo:AddSection("Cat Empire")

TabInfo:AddParagraph({
    Title   = "Sobre",
    Content = "Cat Empire v5.0\nDesenvolvido por Danonin\nUI: Fluent Library",
})

TabInfo:AddParagraph({
    Title   = "Discord",
    Content = "https://discord.gg/qDeZ9sEdGY",
})

TabInfo:AddButton({
    Title = "Copiar Discord",
    Callback = function()
        setclipboard("https://discord.gg/qDeZ9sEdGY")
        Fluent:Notify({ Title="Copiado!", Content="Link do Discord copiado.", Duration=2 })
    end,
})

TabInfo:AddParagraph({
    Title   = "Keybind",
    Content = "RightControl — Mostrar / Ocultar GUI",
})

-- ============================================================
-- INIT
-- ============================================================
SaveManager:LoadAutoloadConfig()
Window:SelectTab(1)

Fluent:Notify({
    Title    = "Cat Empire v5.0",
    Content  = "Carregado com sucesso!",
    Duration = 4,
})
