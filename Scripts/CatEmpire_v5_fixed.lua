-- ============================================================
--  CAT EMPIRE | v5.1 | CODED FOR DANONIN
--  UI: Fluent Library
--  Fixes: toggles funcionando, sem descriptions, rollback via toggle
-- ============================================================

-- SERVICES
local Players         = game:GetService("Players")
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
local Fluent          = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager     = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager= loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

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
-- LOOP CONTROL
-- ============================================================
local loopHandles = {}

local function toggleLoop(key, enabled, interval, fn)
    if loopHandles[key] then
        task.cancel(loopHandles[key])
        loopHandles[key] = nil
    end
    if enabled then
        loopHandles[key] = task.spawn(function()
            while true do
                task.wait(interval)
                pcall(function() fn() end)  -- FIX: wrapper correto
            end
        end)
    end
end

-- ============================================================
-- ROLLBACK SYSTEM (via Toggle + OnClientEvent interceptor)
-- ============================================================
local rollbackActive    = false
local rollbackSnapshot  = {}   -- { remoteName = { args... } } capturado no momento da ativação
local rollbackConn      = nil  -- conexão do OnClientEvent
local rollbackFiredLog  = {}   -- log de fires enquanto ativo (para replay inverso)

-- Captura o estado atual interceptando o Bridge OnClientEvent
-- O servidor manda updates via "Architect","Data","Receiver" (visto no console)
local function startRollbackCapture()
    rollbackSnapshot  = {}
    rollbackFiredLog  = {}

    -- Intercepta fires que o cliente faz (espelha o que enviamos)
    -- Guarda snapshot do estado do PlayerData no momento da ativação
    pcall(function()
        local data = RS:FindFirstChild("Data") or RS:FindFirstChild("PlayerData")
        if data then
            local pd = data:FindFirstChild(tostring(player.UserId)) or data:FindFirstChild(player.Name)
            if pd then
                for _, v in ipairs(pd:GetDescendants()) do
                    if v:IsA("IntValue") or v:IsA("NumberValue") or v:IsA("StringValue") or v:IsA("BoolValue") then
                        rollbackSnapshot[v:GetFullName()] = v.Value
                    end
                end
            end
        end
    end)

    -- Intercepta eventos do servidor (Architect/Data/Receiver) para log
    pcall(function()
        local remotes = RS:FindFirstChild("Remotes")
        if remotes then
            local bridge = remotes:FindFirstChild("Bridge")
            if bridge then
                rollbackConn = bridge.OnClientEvent:Connect(function(...)
                    if not rollbackActive then return end
                    table.insert(rollbackFiredLog, { tick(), {...} })
                end)
            end
        end
    end)

    Fluent:Notify({
        Title   = "Rollback",
        Content = "Capturando estado... Snapshot salvo!",
        Duration = 3,
    })
end

local function stopRollbackCapture()
    if rollbackConn then
        rollbackConn:Disconnect()
        rollbackConn = nil
    end
end

local function executeRollback()
    if not rollbackActive then
        Fluent:Notify({
            Title   = "Rollback",
            Content = "Ative o Rollback primeiro para capturar o estado!",
            Duration = 3,
        })
        return
    end

    Fluent:Notify({
        Title   = "Rollback",
        Content = "Executando rejoin... voltando ao estado salvo!",
        Duration = 2,
    })

    task.wait(0.5)
    -- Rejoin via TeleportService antes do servidor salvar novos dados
    TeleportService:Teleport(placeId, player)
end

-- ============================================================
-- FLUENT WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Cat Empire",
    SubTitle    = "v5.1 | by Danonin",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(720, 480),
    Acrylic     = true,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

-- ============================================================
-- TABS
-- ============================================================
local Tabs = {
    Main     = Window:AddTab({ Title = "Main",     Icon = "sword" }),
    Rewards  = Window:AddTab({ Title = "Rewards",  Icon = "gift" }),
    Fighters = Window:AddTab({ Title = "Fighters", Icon = "user" }),
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "map-pin" }),
    Rollback = Window:AddTab({ Title = "Rollback", Icon = "rotate-ccw" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
    Info     = Window:AddTab({ Title = "Info",     Icon = "info" }),
}

-- ============================================================
-- OPTIONS — só existe após CreateWindow()
-- ============================================================
local Options = Fluent.Options

-- ============================================================
-- TAB: MAIN
-- ============================================================
Tabs.Main:AddSection("Combate")

Tabs.Main:AddToggle("AutoAttack", { Title = "Auto Attack", Default = false })
Options.AutoAttack:OnChanged(function(v)
    toggleLoop("AutoAttack", v, 0.05, function()
        fire("Fighters","Attack","Click")
    end)
end)

Tabs.Main:AddToggle("AutoFarm", { Title = "Auto Farm", Default = false })
Options.AutoFarm:OnChanged(function(v)
    toggleLoop("AutoFarm", v, 0.35, function()
        local enemy, world = getNearestEnemy()
        if not enemy or not world then
            -- Sem inimigo próximo, mantém click básico
            fire("Fighters","Attack","Click")
            return
        end
        local uid = tostring(enemy):gsub("[^%w%-]","")
        -- Remote correto capturado: Fighters > Attack > Attack > world > enemy > uid
        fire("Fighters","Attack","Attack", world, enemy, uid)
        task.wait(0.05)
        -- Confirma dano em cada fighter equipado
        for _, fighterUid in ipairs(getEquippedFighterUIDs()) do
            fire("Fighters","Attack","Do_Damage", fighterUid)
            task.wait(0.02)
        end
    end)
end)

Tabs.Main:AddToggle("AutoRetreat", { Title = "Auto Retreat", Default = false })
Options.AutoRetreat:OnChanged(function(v)
    toggleLoop("AutoRetreat", v, 20, function()
        fire("Fighters","Attack","Retreat_All")
    end)
end)

Tabs.Main:AddSection("Utilitarios")

Tabs.Main:AddToggle("AutoEquip", { Title = "Auto Equip Best", Default = false })
Options.AutoEquip:OnChanged(function(v)
    toggleLoop("AutoEquip", v, 3, function()
        fire("General","Fighters","Equip_Best")
    end)
end)

Tabs.Main:AddToggle("AutoQuest", { Title = "Auto Quest", Default = false })
Options.AutoQuest:OnChanged(function(v)
    toggleLoop("AutoQuest", v, 15, function()
        fire("General","World_Quest","accept", selectedWorld)
    end)
end)

Tabs.Main:AddToggle("AutoStar", { Title = "Auto Star Open", Default = false })
Options.AutoStar:OnChanged(function(v)
    toggleLoop("AutoStar", v, 1.5, function()
        fire("General","Star","Open",1)
    end)
end)

Tabs.Main:AddToggle("AntiAFK", { Title = "Anti-AFK", Default = false })
Options.AntiAFK:OnChanged(function(v)
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

Tabs.Main:AddDropdown("WorldSelect", {
    Title   = "Mundo do Auto Quest",
    Values  = WORLDS,
    Default = "Leaf Village",
})
Options.WorldSelect:OnChanged(function(v)
    selectedWorld = v
end)

-- ============================================================
-- TAB: REWARDS
-- ============================================================
Tabs.Rewards:AddSection("Recompensas")

Tabs.Rewards:AddToggle("DailyRewards", { Title = "Daily Rewards", Default = false })
Options.DailyRewards:OnChanged(function(v)
    toggleLoop("DailyRewards", v, 60, function()
        for day = 1, 7 do
            fire("General","DailyRewards","Claim",day)
            task.wait(0.3)
        end
    end)
end)

Tabs.Rewards:AddToggle("TimeRewards", { Title = "Time Rewards", Default = false })
Options.TimeRewards:OnChanged(function(v)
    toggleLoop("TimeRewards", v, 300, function()
        fire("General","TimeRewards","Claim",1)
    end)
end)

Tabs.Rewards:AddToggle("AutoRankUp", { Title = "Auto Rank Up", Default = false })
Options.AutoRankUp:OnChanged(function(v)
    toggleLoop("AutoRankUp", v, 10, function()
        fire("General","RankUp","Up")
    end)
end)

Tabs.Rewards:AddToggle("AutoAchiev", { Title = "Auto Claim Achievements", Default = false })
Options.AutoAchiev:OnChanged(function(v)
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
Tabs.Fighters:AddSection("Fighter Selecionado")

local fighterParagraph = Tabs.Fighters:AddParagraph({
    Title   = "Selecionado",
    Content = "Nenhum",
})

local function updateFighterLabel()
    fighterParagraph:SetDesc(
        selectedFighterName .. "  |  " ..
        (selectedFighterUID ~= "" and selectedFighterUID or "sem UID")
    )
end

Tabs.Fighters:AddButton({
    Title    = "Escanear Fighters",
    Callback = function()
        local found = {}

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
            selectedFighterUID  = found[1].UID
            selectedFighterName = found[1].Name
            updateFighterLabel()
            Fluent:Notify({ Title="Fighters", Content=#found.." encontrado(s). Selecionado: "..found[1].Name, Duration=4 })
        else
            Fluent:Notify({ Title="Fighters", Content="Nenhum detectado. Use UID manual.", Duration=3 })
        end
    end,
})

Tabs.Fighters:AddInput("ManualUID", {
    Title       = "UID Manual",
    Placeholder = "Cole o UID aqui...",
    Numeric     = false,
})

Tabs.Fighters:AddButton({
    Title    = "Usar UID Manual",
    Callback = function()
        local uid = Options.ManualUID.Value:gsub("%s+","")
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

-- Traits desejadas — manter = true, descartar = false
-- Baseado na captura do UtopiaSpy (imagem 2)
local DESIRED_TRAITS = {
    ["Strongest"]   = true,
    ["Monarch"]     = true,
    ["Clover III"]  = true,
    ["Scholar"]     = true,
    ["Clover II"]   = true,
    ["Fortune III"] = false,
    ["Vigor"]       = false,
    ["Swift"]       = false,
    ["Swift III"]   = false,
    ["Vigor II"]    = false,
    ["Clover I"]    = false,
}

-- Stats desejados — manter = true
local DESIRED_STATS = {
    ["S+"] = true,
    ["A+"] = true,
    ["A"]  = true,
    ["S-"] = true,
    ["C+"] = false,
    ["B+"] = false,
    ["D+"] = false,
    ["D"]  = false,
    ["C-"] = false,
    ["D-"] = false,
}

Tabs.Fighters:AddSection("Traits Reroll")

Tabs.Fighters:AddToggle("AutoTraits", { Title = "Auto Traits Reroll", Default = false })
Options.AutoTraits:OnChanged(function(v)
    toggleLoop("AutoTraits", v, 1.5, function()
        if selectedFighterUID == "" then return end
        fire("General","Traits","Reroll", selectedFighterUID, DESIRED_TRAITS)
    end)
end)

Tabs.Fighters:AddButton({
    Title    = "Traits Reroll (1x)",
    Callback = function()
        if selectedFighterUID == "" then
            Fluent:Notify({ Title="Erro", Content="Selecione um fighter primeiro!", Duration=2 })
            return
        end
        fire("General","Traits","Reroll", selectedFighterUID, DESIRED_TRAITS)
        Fluent:Notify({ Title="Traits", Content="Reroll enviado", Duration=2 })
    end,
})

Tabs.Fighters:AddSection("Stats Reroll")

Tabs.Fighters:AddToggle("AutoStats", { Title = "Auto Stats Reroll", Default = false })
Options.AutoStats:OnChanged(function(v)
    toggleLoop("AutoStats", v, 1.5, function()
        if selectedFighterUID == "" then return end
        fire("General","StatsReroll","Reroll", selectedFighterUID, DESIRED_STATS)
    end)
end)

Tabs.Fighters:AddButton({
    Title    = "Stats Reroll (1x)",
    Callback = function()
        if selectedFighterUID == "" then
            Fluent:Notify({ Title="Erro", Content="Selecione um fighter primeiro!", Duration=2 })
            return
        end
        fire("General","StatsReroll","Reroll", selectedFighterUID, DESIRED_STATS)
        Fluent:Notify({ Title="Stats", Content="Reroll enviado", Duration=2 })
    end,
})

Tabs.Fighters:AddSection("Lock Stat")

Tabs.Fighters:AddDropdown("LockStatDrop", {
    Title   = "Stat para Lockear",
    Values  = {"Attack","Defense","Health","Speed"},
    Default = "Attack",
})
Options.LockStatDrop:OnChanged(function(v)
    selectedStat = v
end)

Tabs.Fighters:AddButton({
    Title    = "Aplicar Lock",
    Callback = function()
        if selectedFighterUID == "" then
            Fluent:Notify({ Title="Erro", Content="Selecione um fighter primeiro!", Duration=2 })
            return
        end
        fire("General","StatsReroll","Lock",selectedFighterUID,selectedStat)
        Fluent:Notify({ Title="Lock", Content=selectedStat.." lockado", Duration=2 })
    end,
})

-- ============================================================
-- TAB: TELEPORT
-- ============================================================
Tabs.Teleport:AddSection("Mundos")

for _, world in ipairs(WORLDS) do
    local w = world
    Tabs.Teleport:AddButton({
        Title    = w,
        Callback = function()
            fire("General","Teleport","Teleport", w)
            Fluent:Notify({ Title="Teleporte", Content="Indo para "..w.."...", Duration=3 })
        end,
    })
end

-- ============================================================
-- TAB: ROLLBACK
-- ============================================================
Tabs.Rollback:AddSection("Rollback")

Tabs.Rollback:AddParagraph({
    Title   = "Como funciona",
    Content = "Ative o toggle para começar a capturar o estado.\nQuando executar Rollback, o jogo faz rejoin voltando exatamente ao momento que você ativou.",
})

local rollbackStatusParagraph = Tabs.Rollback:AddParagraph({
    Title   = "Status",
    Content = "Inativo",
})

Tabs.Rollback:AddToggle("RollbackCapture", { Title = "Capturar Estado (Rollback)", Default = false })
Options.RollbackCapture:OnChanged(function(v)
    rollbackActive = v
    if v then
        startRollbackCapture()
        rollbackStatusParagraph:SetDesc("Ativo — capturando desde " .. os.date("%H:%M:%S"))
    else
        stopRollbackCapture()
        rollbackStatusParagraph:SetDesc("Captura pausada")
        Fluent:Notify({ Title="Rollback", Content="Captura pausada.", Duration=2 })
    end
end)

Tabs.Rollback:AddButton({
    Title    = "Executar Rollback (Rejoin)",
    Callback = function()
        executeRollback()
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
Tabs.Info:AddSection("Cat Empire")

Tabs.Info:AddParagraph({
    Title   = "Sobre",
    Content = "Cat Empire v5.1\nDesenvolvido por Danonin",
})

Tabs.Info:AddParagraph({
    Title   = "Discord",
    Content = "https://discord.gg/qDeZ9sEdGY",
})

Tabs.Info:AddButton({
    Title    = "Copiar Discord",
    Callback = function()
        setclipboard("https://discord.gg/qDeZ9sEdGY")
        Fluent:Notify({ Title="Copiado!", Content="Link do Discord copiado.", Duration=2 })
    end,
})

Tabs.Info:AddParagraph({
    Title   = "Keybind",
    Content = "RightControl — Mostrar / Ocultar GUI",
})

-- ============================================================
-- INIT
-- ============================================================
SaveManager:LoadAutoloadConfig()
Window:SelectTab(1)

Fluent:Notify({
    Title    = "Cat Empire v5.1",
    Content  = "Carregado com sucesso!",
    Duration = 4,
})
