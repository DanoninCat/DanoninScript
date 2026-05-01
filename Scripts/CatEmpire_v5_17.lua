-- ============================================================
--  CAT EMPIRE | v5.17 | CODED FOR DANONIN
--  UI: Fluent Library
--  Fixes: getNearestEnemy usa atributo ID real, Fighter scan usa Name como UID, mundos corretos
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
-- PLAYERDATA — populado via OnClientEvent do Bridge
-- Servidor manda: "Architect","Data","Receiver", {tabela completa}
-- ============================================================
local playerData = nil  -- FIX: declarado aqui para ser visível em todo o arquivo

task.spawn(function()
    local bridge = getBridge()
    -- Aguarda até 10s pelo Bridge caso ainda não exista
    local t = 0
    while not bridge and t < 10 do
        task.wait(0.5)
        t += 0.5
        bridge = getBridge()
    end
    if not bridge then return end

    bridge.OnClientEvent:Connect(function(...)
        local args = {...}
        if args[1] == "Architect" and args[2] == "Data" and args[3] == "Receiver" then
            if type(args[4]) == "table" then
                playerData = args[4]
            end
        end
    end)
end)

-- ============================================================
-- HELPERS
-- ============================================================
-- DEBUG confirmou:
--   Fighters ficam em Workspace.Client.Fighters.[UserId]
--                  e Workspace.Server.Fighters.[UserId]
--   UID=nil nos atributos — o UID é uma string interna do fighter
--   que o jogo usa. Precisamos pegar via UtopiaSpy manualmente.
--   Esta função retorna o nome dos filhos da pasta do player
--   como fallback enquanto o UID manual não é definido.
local function getEquippedFighterUIDs()
    local uids = {}
    pcall(function()
        -- DEBUG confirmou: Workspace.Server.Fighters.[UserId]
        -- O NAME de cada filho É o UID do fighter (ex: "b9-71e8-4b0f-927c-2c6f78f5d2fa")
        -- ATTR: Enabled, Level, Trait, Player — sem atributo UID
        local userId = tostring(player.UserId)
        local serverFighters = WS:FindFirstChild("Server") and WS.Server:FindFirstChild("Fighters")
        if not serverFighters then return end
        local myFolder = serverFighters:FindFirstChild(userId)
        if not myFolder then return end
        for _, fighter in ipairs(myFolder:GetChildren()) do
            -- Só adiciona fighters habilitados (Enabled = true)
            local enabled = fighter:GetAttribute("Enabled")
            if enabled == true or enabled == nil then
                table.insert(uids, fighter.Name)
            end
        end
    end)
    return uids
end

-- DEBUG confirmou:
--   APENAS Server.Enemies tem inimigos reais com atributo "ID"
--   Client.Enemies tem só dummies de animação — IGNORAR
--   Subpastas = nome do mundo (ex: "Leaf Village", "Dragon Town")
--   Atributo do inimigo = "ID" (não UID/uid/Id)
-- Retorna: enemy (model), worldName (string), enemyID (string)
-- Retorna a posição de um inimigo (que pode ser Part, Model, qualquer coisa)
local function getEnemyPosition(enemy)
    if enemy:IsA("BasePart") then
        return enemy.Position
    elseif enemy:IsA("Model") then
        if enemy.PrimaryPart then return enemy.PrimaryPart.Position end
        local p = enemy:FindFirstChildWhichIsA("BasePart", true)
        if p then return p.Position end
    end
    return nil
end

local function getCurrentWorld()
    if playerData and playerData.World and playerData.World ~= "" then
        return playerData.World
    end
    local char = player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local serverEnemies = WS:FindFirstChild("Server") and WS.Server:FindFirstChild("Enemies")
    if not serverEnemies then return nil end
    local bestWorld, bestDist = nil, math.huge
    for _, worldFolder in ipairs(serverEnemies:GetChildren()) do
        if worldFolder.Name == "Lobby" then continue end
        for _, enemy in ipairs(worldFolder:GetChildren()) do
            local pos = getEnemyPosition(enemy)
            if pos then
                local d = (hrp.Position - pos).Magnitude
                if d < bestDist then bestDist = d bestWorld = worldFolder.Name end
            end
        end
    end
    return bestWorld
end

local function getNearestEnemy()
    local char = player.Character
    if not char then return nil, nil, nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil, nil end

    local serverEnemies = WS:FindFirstChild("Server") and WS.Server:FindFirstChild("Enemies")
    if not serverEnemies then return nil, nil, nil end

    local currentWorld = getCurrentWorld()
    if not currentWorld then return nil, nil, nil end

    local worldFolder = serverEnemies:FindFirstChild(currentWorld)
    if not worldFolder then return nil, nil, nil end

    local nearest, nearestDist, nearestID = nil, math.huge, nil

    for _, enemy in ipairs(worldFolder:GetChildren()) do
        local enemyID = enemy:GetAttribute("ID")
        if not enemyID then continue end
        local health = enemy:GetAttribute("Health")
        if not health or health <= 0 or health ~= health or health == math.huge then continue end
        local pos = getEnemyPosition(enemy)
        if not pos then continue end
        local dist = (hrp.Position - pos).Magnitude
        if dist < nearestDist then
            nearest     = enemy
            nearestDist = dist
            nearestID   = tostring(enemyID)
        end
    end

    return nearest, currentWorld, nearestID
end

-- ============================================================
-- CONSTANTES
-- ============================================================
-- Nomes EXATOS confirmados via require(Achievements) no debug
local KNOWN_ACHIEVEMENTS = {
    -- EnemiesDefeated
    "Defeat I","Defeat II","Defeat III","Defeat IV","Defeat V",
    "Defeat VI","Defeat VII","Defeat VIII","Defeat IX","Defeat X",
    "Defeat XI","Defeat XII","Defeat XIII","Defeat XVI",
    -- Playtime (Name = Luck X no ModuleScript)
    "Luck I","Luck II","Luck III","Luck IV","Luck V",
    "Luck VI","Luck VII","Luck VIII","Luck IX","Luck X",
    -- StarsOpenned
    "Stars I","Stars II","Stars III","Stars IV","Stars V",
    "Stars VI","Stars VII","Stars VIII","Stars IX","Stars X","Stars XI",
    -- Inventory
    "Inventory I","Inventory II","Inventory III","Inventory IV",
    -- EasyTrial
    "Easy Trial I","Easy Trial II","Easy Trial III","Easy Trial IV","Easy Trial V",
    "Easy Trial VI","Easy Trial VII","Easy Trial VIII","Easy Trial IX","Easy Trial X",
}

-- Mundos confirmados no debug: Workspace.Server.Enemies[worldName]
local WORLDS = {
    "Leaf Village","Dragon Town","Slayer Village",
    "Pirate Island","Solo City","Z City","Hollow Island","Lobby"
}
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
-- ROLLBACK SYSTEM
-- Mecânica real: jogos Roblox salvam dados a cada ~60-120s.
-- 1. Ativa toggle → captura snapshot (estado "antes")
-- 2. Faz o que quiser (gasta chips, abre estrelas, etc.)
-- 3. Executa Rollback → para loops e faz rejoin IMEDIATO
-- 4. Servidor carrega último save = estado do snapshot
-- IMPORTANTE: use dentro de ~60s após ativar
-- ============================================================
local rollbackActive    = false
local rollbackSnapshot  = nil
local rollbackConn      = nil
local rollbackTime      = nil
local rollbackSaveTimer = 0

local function deepCopy(original)
    if type(original) ~= "table" then return original end
    local copy = {}
    for k, v in pairs(original) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function startRollbackCapture()
    rollbackSnapshot  = nil
    rollbackTime      = nil
    rollbackSaveTimer = 0

    local bridge = getBridge()
    if not bridge then
        Fluent:Notify({ Title="Rollback", Content="Bridge não encontrado!", Duration=3 })
        return
    end

    rollbackConn = bridge.OnClientEvent:Connect(function(...)
        local args = {...}
        if args[1] == "Architect" and args[2] == "Data" and args[3] == "Receiver" then
            if rollbackSnapshot == nil and type(args[4]) == "table" then
                rollbackSnapshot  = deepCopy(args[4])
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
                    Content = "Estado salvo às " .. rollbackTime .. "!\nVocê tem ~60s antes do próximo save.",
                    Duration = 4,
                })
            end
        end
    end)
end

local function stopRollbackCapture()
    if rollbackConn then
        rollbackConn:Disconnect()
        rollbackConn = nil
    end
end

local function executeRollback()
    if not rollbackSnapshot then
        Fluent:Notify({
            Title    = "Rollback",
            Content  = "Nenhum snapshot! Ative o toggle primeiro.",
            Duration = 3,
        })
        return
    end

    if rollbackSaveTimer >= 90 then
        Fluent:Notify({
            Title    = "Rollback — AVISO",
            Content  = rollbackSaveTimer .. "s desde o snapshot. Servidor pode já ter salvo.",
            Duration = 4,
        })
        task.wait(2)
    end

    -- Para TODOS os loops imediatamente — nenhum remote pode ser disparado
    for key, handle in pairs(loopHandles) do
        if handle then task.cancel(handle) end
        loopHandles[key] = nil
    end
    stopRollbackCapture()
    rollbackActive = false

    Fluent:Notify({
        Title   = "Rollback",
        Content = "Fazendo rejoin agora...\nServidor vai carregar estado de " .. (rollbackTime or "?"),
        Duration = 3,
    })

    task.wait(0.5)
    pcall(function() TeleportService:Teleport(placeId) end)
end

-- ============================================================
-- FLUENT WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Cat Empire",
    SubTitle    = "v5.17 | by Danonin",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(720, 480),
    Acrylic     = true,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

-- Botão flutuante TOGGLE — estilo da imagem (TextButton arrastável)
-- FIX: usa VirtualInputManager pra simular RightControl (método nativo do Fluent)
local windowVisible = true

local minSG = Instance.new("ScreenGui")
minSG.Name            = "CatEmpireMinGui"
minSG.ResetOnSpawn    = false
minSG.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
minSG.DisplayOrder    = 999
local minOk = pcall(function() minSG.Parent = game:GetService("CoreGui") end)
if not minOk then minSG.Parent = player:WaitForChild("PlayerGui") end

-- Frame container (imagem + label "Toggle")
local minFrame = Instance.new("Frame", minSG)
minFrame.Size             = UDim2.fromOffset(60, 60)
minFrame.Position         = UDim2.new(0, 8, 0.5, -30)
minFrame.BackgroundColor3 = Color3.fromRGB(0, 80, 190)
minFrame.BackgroundTransparency = 0.08
minFrame.ZIndex           = 50
Instance.new("UICorner", minFrame).CornerRadius = UDim.new(0, 12)
Instance.new("UIStroke", minFrame).Color = Color3.fromRGB(60, 140, 255)

local minImg = Instance.new("ImageLabel", minFrame)
minImg.Size             = UDim2.fromOffset(36, 36)
minImg.Position         = UDim2.new(0.5, -18, 0, 4)
minImg.Image            = "rbxassetid://128797153413520"
minImg.BackgroundTransparency = 1
minImg.ZIndex           = 51

local minLbl = Instance.new("TextLabel", minFrame)
minLbl.Size             = UDim2.new(1, 0, 0, 18)
minLbl.Position         = UDim2.new(0, 0, 1, -19)
minLbl.BackgroundTransparency = 1
minLbl.Text             = "Toggle"
minLbl.TextColor3       = Color3.new(1, 1, 1)
minLbl.Font             = Enum.Font.GothamBold
minLbl.TextSize         = 11
minLbl.ZIndex           = 51

-- Botão invisível sobre o frame para capturar input
local minHit = Instance.new("TextButton", minFrame)
minHit.Size             = UDim2.fromScale(1, 1)
minHit.BackgroundTransparency = 1
minHit.Text             = ""
minHit.ZIndex           = 52

local fbDragging  = false
local fbDragStart = nil
local fbStartPos  = nil
local fbMoved     = false
local UIS2        = game:GetService("UserInputService")

-- Busca TODOS os frames raiz do Fluent para esconder completamente
-- O Fluent cria layers separados (backdrop, janela, blur) — precisa esconder todos
local fluentLayers = {}  -- lista de todos os frames/layers do Fluent

task.delay(1.5, function()
    local function collectFluentLayers(parent)
        for _, sg in ipairs(parent:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Name ~= "CatEmpireMinGui" then
                -- Guarda o ScreenGui inteiro E todos os seus filhos Frame
                table.insert(fluentLayers, sg)
            end
        end
    end
    collectFluentLayers(game:GetService("CoreGui"))
    collectFluentLayers(player:WaitForChild("PlayerGui"))
end)

local function simulateMinimize()
    windowVisible = not windowVisible

    if #fluentLayers > 0 then
        -- Esconde/mostra TODOS os layers do Fluent
        for _, layer in ipairs(fluentLayers) do
            pcall(function()
                if layer:IsA("ScreenGui") then
                    -- Esconde todos os filhos Frame individualmente (resolve a "sombra")
                    for _, child in ipairs(layer:GetChildren()) do
                        if child:IsA("Frame") or child:IsA("ImageLabel") or child:IsA("TextLabel") then
                            child.Visible = windowVisible
                        end
                    end
                    layer.Enabled = windowVisible
                end
            end)
        end
    else
        -- Fallback em runtime se ainda não carregou
        pcall(function()
            for _, sg in ipairs(game:GetService("CoreGui"):GetChildren()) do
                if sg:IsA("ScreenGui") and sg.Name ~= "CatEmpireMinGui" then
                    for _, child in ipairs(sg:GetChildren()) do
                        if child:IsA("Frame") or child:IsA("ImageLabel") then
                            child.Visible = windowVisible
                        end
                    end
                    sg.Enabled = windowVisible
                end
            end
        end)
    end

    minFrame.BackgroundColor3 = windowVisible
        and Color3.fromRGB(0, 80, 190)
        or  Color3.fromRGB(140, 30, 30)
    minLbl.Text = windowVisible and "Toggle" or "Abrir"
end

minHit.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        fbDragging  = true
        fbMoved     = false
        fbDragStart = Vector2.new(i.Position.X, i.Position.Y)
        fbStartPos  = minFrame.Position
    end
end)

UIS2.InputChanged:Connect(function(i)
    if not fbDragging then return end
    if i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch then
        local dx = i.Position.X - fbDragStart.X
        local dy = i.Position.Y - fbDragStart.Y
        if math.abs(dx) > 5 or math.abs(dy) > 5 then
            fbMoved = true
            minFrame.Position = UDim2.new(
                fbStartPos.X.Scale, fbStartPos.X.Offset + dx,
                fbStartPos.Y.Scale, fbStartPos.Y.Offset + dy
            )
        end
    end
end)

UIS2.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        -- SÓ age se o input COMEÇOU no botão (fbDragging foi setado no InputBegan do botão)
        if not fbDragging then return end
        fbDragging = false
        if not fbMoved then simulateMinimize() end
        fbMoved = false
    end
end)

-- ============================================================
-- TABS
-- ============================================================
local Tabs = {
    Main     = Window:AddTab({ Title = "Main",     Icon = "sword" }),
    Rewards  = Window:AddTab({ Title = "Rewards",  Icon = "gift" }),
    Fighters = Window:AddTab({ Title = "Fighters", Icon = "user" }),
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "map-pin" }),
    Rollback = Window:AddTab({ Title = "Rollback", Icon = "rotate-ccw" }),
    Debug    = Window:AddTab({ Title = "Debug",    Icon = "terminal" }),
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
    -- "Click" confirmado no debug: [TESTE Auto Attack - Fighters,Attack,Click] → OK
    toggleLoop("AutoAttack", v, 0.1, function()
        fire("Fighters","Attack","Click")
    end)
end)

Tabs.Main:AddToggle("AutoFarm", { Title = "Auto Farm", Default = false })
Options.AutoFarm:OnChanged(function(v)
    toggleLoop("AutoFarm", v, 0.4, function()
        local enemy, world = getNearestEnemy()
        if not enemy or not world then return end

        -- Teleporta perto do inimigo se necessário
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local enemyPos = getEnemyPosition(enemy)
            if enemyPos and (hrp.Position - enemyPos).Magnitude > 20 then
                hrp.CFrame = CFrame.new(enemyPos + Vector3.new(0, 0, 6))
            end
        end

        -- Confirmado UtopiaSpy: Attack_All com inimigo real (instance) do workspace
        fire("Fighters","Attack","Attack_All","World", enemy)
        task.wait(0.05)

        -- Do_Damage para cada fighter: UID = Name do filho em Server.Fighters.[UserId]
        local uids = getEquippedFighterUIDs()
        for _, uid in ipairs(uids) do
            fire("Fighters","Attack","Do_Damage", uid)
            task.wait(0.02)
        end
    end)
end)

-- NPC alvo
local targetNPCName = "Any"
local npcListCache  = { "Any" }

local npcDropdown = Tabs.Main:AddDropdown("TargetNPC", {
    Title   = "Target NPC",
    Values  = npcListCache,
    Default = "Any",
})
npcDropdown:OnChanged(function(v) targetNPCName = v end)

-- Sobrescreve getNearestEnemy para filtrar por NPC selecionado
local _baseGetNearest = getNearestEnemy
getNearestEnemy = function()
    if targetNPCName == "Any" then
        return _baseGetNearest()
    end
    local char = player.Character
    if not char then return nil, nil, nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil, nil end
    local currentWorld = getCurrentWorld()
    if not currentWorld then return nil, nil, nil end
    local worldFolder = WS:FindFirstChild("Server")
        and WS.Server:FindFirstChild("Enemies")
        and WS.Server.Enemies:FindFirstChild(currentWorld)
    if not worldFolder then return nil, nil, nil end
    local nearest, nearestDist, nearestID = nil, math.huge, nil
    for _, enemy in ipairs(worldFolder:GetChildren()) do
        if enemy.Name ~= targetNPCName then continue end
        local enemyID = enemy:GetAttribute("ID")
        if not enemyID then continue end
        local health = enemy:GetAttribute("Health")
        if not health or health <= 0 or health ~= health or health == math.huge then continue end
        local pos = getEnemyPosition(enemy)
        if not pos then continue end
        local dist = (hrp.Position - pos).Magnitude
        if dist < nearestDist then
            nearest     = enemy
            nearestDist = dist
            nearestID   = tostring(enemyID)
        end
    end
    return nearest, currentWorld, nearestID
end

local function refreshNPCList()
    local currentWorld = getCurrentWorld()
    local names = { "Any" }
    local seen  = {}
    if currentWorld then
        local worldFolder = WS:FindFirstChild("Server")
            and WS.Server:FindFirstChild("Enemies")
            and WS.Server.Enemies:FindFirstChild(currentWorld)
        if worldFolder then
            for _, enemy in ipairs(worldFolder:GetChildren()) do
                local hp = enemy:GetAttribute("Health")
                if hp and hp > 0 and hp ~= math.huge and not seen[enemy.Name] then
                    seen[enemy.Name] = true
                    table.insert(names, enemy.Name)
                end
            end
        end
    end
    npcListCache = names
    npcDropdown:SetValues(names)
    npcDropdown:SetValue("Any")
    targetNPCName = "Any"
    Fluent:Notify({
        Title   = "NPCs",
        Content = (#names - 1) .. " NPC(s) in " .. (currentWorld or "?"),
        Duration = 3,
    })
end

Tabs.Main:AddButton({
    Title    = "Refresh NPCs",
    Callback = refreshNPCList,
})

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

-- Daily Rewards: tenta claim no dia atual do servidor via OnClientEvent
-- Fallback: tenta dias 1-7, servidor rejeita os já coletados silenciosamente
Tabs.Rewards:AddToggle("DailyRewards", { Title = "Daily Rewards", Default = false })
Options.DailyRewards:OnChanged(function(v)
    toggleLoop("DailyRewards", v, 180, function()
        -- Tenta pegar o dia atual via atributo do PlayerData
        local currentDay = nil
        pcall(function()
            local data = RS:FindFirstChild("Data") or RS:FindFirstChild("PlayerData")
            if data then
                local pd = data:FindFirstChild(tostring(player.UserId)) or data:FindFirstChild(player.Name)
                if pd then
                    local dailyFolder = pd:FindFirstChild("DailyRewards") or pd:FindFirstChild("Daily")
                    if dailyFolder then
                        local dayVal = dailyFolder:FindFirstChild("Day") or dailyFolder:FindFirstChild("Current")
                        if dayVal then currentDay = dayVal.Value end
                    end
                end
            end
        end)
        -- Se achou o dia, clama só ele; senão tenta os 7
        if currentDay and type(currentDay) == "number" then
            fire("General","DailyRewards","Claim", currentDay)
        else
            for day = 1, 7 do
                fire("General","DailyRewards","Claim", day)
                task.wait(0.5)
            end
        end
    end)
end)

Tabs.Rewards:AddButton({
    Title    = "Claim Daily (Agora)",
    Callback = function()
        for day = 1, 7 do
            fire("General","DailyRewards","Claim", day)
            task.wait(0.4)
        end
        Fluent:Notify({ Title="Daily", Content="Claim enviado para todos os dias", Duration=2 })
    end,
})

Tabs.Rewards:AddToggle("TimeRewards", { Title = "Time Rewards", Default = false })
Options.TimeRewards:OnChanged(function(v)
    -- Confirmado no debug: General, TimeRewards, Claim, 1
    -- Arg é sempre 1, não um loop de 1-5
    toggleLoop("TimeRewards", v, 30, function()
        fire("General","TimeRewards","Claim", 1)
    end)
end)

Tabs.Rewards:AddButton({
    Title    = "Claim Time (Agora)",
    Callback = function()
        fire("General","TimeRewards","Claim", 1)
        Fluent:Notify({ Title="Time Reward", Content="Claim enviado", Duration=2 })
    end,
})

Tabs.Rewards:AddToggle("AutoRankUp", { Title = "Auto Rank Up", Default = false })
Options.AutoRankUp:OnChanged(function(v)
    toggleLoop("AutoRankUp", v, 10, function()
        fire("General","RankUp","Up")
    end)
end)

-- Achievements: dispara cada nome com delay curto
-- toggleLoop já roda em task.spawn, então task.wait interno é seguro
local function claimAllAchievements()
    for _, name in ipairs(KNOWN_ACHIEVEMENTS) do
        fire("General","Achievements","Claim", name)
        task.wait(0.2)
    end
end

Tabs.Rewards:AddToggle("AutoAchiev", { Title = "Auto Claim Achievements", Default = false })
Options.AutoAchiev:OnChanged(function(v)
    -- Intervalo longo: roda 1x a cada 2min (achievements têm cooldown)
    toggleLoop("AutoAchiev", v, 120, claimAllAchievements)
end)

Tabs.Rewards:AddButton({
    Title    = "Claim Achievements (Agora)",
    Callback = function()
        task.spawn(claimAllAchievements)
        Fluent:Notify({ Title="Achievements", Content="Claim iniciado...", Duration=2 })
    end,
})

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

        -- DEBUG confirmou: WS.Server.Fighters[UserId]
        -- O NAME de cada filho É o UID — sem atributo UID
        -- Atributos disponíveis: Trait, Level, Enabled, Player
        pcall(function()
            local sf = WS:FindFirstChild("Server") and WS.Server:FindFirstChild("Fighters")
            if sf then
                -- Tenta por UserId primeiro, depois por Name
                local myF = sf:FindFirstChild(tostring(player.UserId))
                         or sf:FindFirstChild(player.Name)
                if myF then
                    for _, f in ipairs(myF:GetChildren()) do
                        -- f.Name = UID do fighter
                        local uid   = f.Name
                        local trait = f:GetAttribute("Trait") or "?"
                        local level = f:GetAttribute("Level") or "?"
                        local label = tostring(trait) .. "  Lv." .. tostring(level)
                        table.insert(found, { Name=label, UID=uid })
                    end
                end
            end
        end)

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

-- Trait Reroll LIVRE: tabela vazia = reroll sem filtro, aceita qualquer trait
-- Trait Reroll FILTRADO: mantém apenas traits boas definidas em DESIRED_TRAITS
-- IMPORTANTE: o servidor interpreta "false" como "descarta essa trait se sair"
-- Usar {} (vazio) = reroll livre, sem restrição — MAIS EFICIENTE para farmar

Tabs.Fighters:AddToggle("AutoTraitsLivre", { Title = "Auto Trait Reroll (Livre)", Default = false })
Options.AutoTraitsLivre:OnChanged(function(v)
    toggleLoop("AutoTraitsLivre", v, 0.8, function()
        if selectedFighterUID == "" then return end
        -- Tabela vazia = reroll sem filtro
        fire("General","Traits","Reroll", selectedFighterUID, {})
    end)
end)

Tabs.Fighters:AddToggle("AutoTraits", { Title = "Auto Trait Reroll (Filtrado)", Default = false })
Options.AutoTraits:OnChanged(function(v)
    toggleLoop("AutoTraits", v, 0.8, function()
        if selectedFighterUID == "" then return end
        fire("General","Traits","Reroll", selectedFighterUID, DESIRED_TRAITS)
    end)
end)

Tabs.Fighters:AddButton({
    Title    = "Trait Reroll Livre (1x)",
    Callback = function()
        if selectedFighterUID == "" then
            Fluent:Notify({ Title="Erro", Content="Selecione um fighter primeiro!", Duration=2 })
            return
        end
        fire("General","Traits","Reroll", selectedFighterUID, {})
        Fluent:Notify({ Title="Traits", Content="Reroll livre enviado", Duration=2 })
    end,
})

Tabs.Fighters:AddButton({
    Title    = "Trait Reroll Filtrado (1x)",
    Callback = function()
        if selectedFighterUID == "" then
            Fluent:Notify({ Title="Erro", Content="Selecione um fighter primeiro!", Duration=2 })
            return
        end
        fire("General","Traits","Reroll", selectedFighterUID, DESIRED_TRAITS)
        Fluent:Notify({ Title="Traits", Content="Reroll filtrado enviado", Duration=2 })
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
    Content = "1. Ative o toggle ANTES de fazer qualquer coisa\n2. Faca o que quiser no jogo (gacha, reroll, etc)\n3. Clique Executar Rollback ANTES de 60s\n4. O servidor carrega o save anterior — tudo volta ao normal\n\nSe passar de 60s, o servidor ja pode ter salvo os novos dados.",
})

local rollbackStatusParagraph = Tabs.Rollback:AddParagraph({
    Title   = "Status",
    Content = "Inativo — nenhum snapshot salvo",
})

-- Atualiza o timer em tempo real enquanto rollback está ativo
task.spawn(function()
    while true do
        task.wait(1)
        if rollbackActive and rollbackSnapshot then
            local cor = rollbackSaveTimer < 45 and "SEGURO" or rollbackSaveTimer < 75 and "ATENCAO" or "RISCO"
            rollbackStatusParagraph:SetDesc(
                "Snapshot: " .. (rollbackTime or "?") ..
                "\nTempo: " .. rollbackSaveTimer .. "s — " .. cor
            )
        end
    end
end)

Tabs.Rollback:AddToggle("RollbackCapture", { Title = "Ativar Captura de Estado", Default = false })
Options.RollbackCapture:OnChanged(function(v)
    rollbackActive = v
    if v then
        rollbackSnapshot  = nil
        rollbackSaveTimer = 0
        startRollbackCapture()
        rollbackStatusParagraph:SetDesc("Aguardando pacote do servidor...")
    else
        stopRollbackCapture()
        if rollbackSnapshot then
            rollbackStatusParagraph:SetDesc("Pausado — snapshot de " .. (rollbackTime or "?") .. " disponivel")
        else
            rollbackStatusParagraph:SetDesc("Desativado — nenhum snapshot capturado")
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
-- TAB: DEBUG — acesso restrito por chave Admin10
-- ============================================================
Tabs.Debug:AddSection("Acesso Restrito")

local debugUnlocked = false

local debugLockParagraph = Tabs.Debug:AddParagraph({
    Title   = "Autenticacao",
    Content = "Esta aba e restrita. Insira a chave de acesso.",
})

Tabs.Debug:AddInput("AdminKey", {
    Title       = "Chave de Acesso",
    Placeholder = "Digite a chave...",
    Numeric     = false,
})

Tabs.Debug:AddButton({
    Title    = "Validar Chave",
    Callback = function()
        local key = Options.AdminKey.Value or ""
        if key ~= "Admin10" then
            Fluent:Notify({ Title="Acesso Negado", Content="Chave incorreta.", Duration=3 })
            return
        end
        if debugUnlocked then
            Fluent:Notify({ Title="Debug", Content="Ja desbloqueado.", Duration=2 })
            return
        end
        debugUnlocked = true
        debugLockParagraph:SetDesc("Desbloqueado.")

        -- Carrega conteúdo do debug só após validação
        local snifferActive   = false
        local snifferConn     = nil
        local capturedRemotes = {}
        local snifferCount    = 0

        local snifferStatus = Tabs.Debug:AddParagraph({
            Title   = "Sniffer",
            Content = "Inativo",
        })

        Tabs.Debug:AddToggle("SnifferToggle", { Title = "Ativar Sniffer", Default = false })
        Options.SnifferToggle:OnChanged(function(v)
            snifferActive = v
            if v then
                capturedRemotes = {}
                snifferCount    = 0
                snifferStatus:SetDesc("Ativo — aguardando remotes...")
                local bridge = getBridge()
                if not bridge then snifferStatus:SetDesc("ERRO: Bridge nao encontrado!") return end

                snifferConn = bridge.OnClientEvent:Connect(function(...)
                    local args = {...}
                    snifferCount += 1
                    local parts = {}
                    for i, a in ipairs(args) do
                        local t = type(a)
                        if t == "string" or t == "number" or t == "boolean" then
                            table.insert(parts, tostring(a))
                        elseif t == "table" then
                            table.insert(parts, "{table}")
                        else
                            table.insert(parts, t)
                        end
                        if i >= 6 then table.insert(parts, "...") break end
                    end
                    local line = "[CLIENT] " .. table.concat(parts, ", ")
                    table.insert(capturedRemotes, line)
                    warn("[DEBUG] " .. line)
                    snifferStatus:SetDesc("#" .. snifferCount .. ": " .. line)
                    local raw = table.concat(parts, " "):lower()
                    if raw:find("trial") or raw:find("gacha") or raw:find("star") or raw:find("spin") then
                        Fluent:Notify({ Title="Trial/Gacha", Content=line, Duration=8 })
                    end
                end)
                Fluent:Notify({ Title="Sniffer", Content="Ativo!", Duration=2 })
            else
                if snifferConn then snifferConn:Disconnect() snifferConn = nil end
                snifferStatus:SetDesc("Inativo. " .. snifferCount .. " capturados.")
            end
        end)

        Tabs.Debug:AddButton({
            Title    = "Ver no Output",
            Callback = function()
                warn("=== REMOTES (" .. #capturedRemotes .. ") ===")
                for i, l in ipairs(capturedRemotes) do warn(i..": "..l) end
                warn("=== FIM ===")
                Fluent:Notify({ Title="Debug", Content=#capturedRemotes.." no output.", Duration=2 })
            end,
        })

        Tabs.Debug:AddButton({
            Title = "Limpar", Callback = function()
                capturedRemotes = {} snifferCount = 0
                snifferStatus:SetDesc("Limpo.")
            end,
        })

        Tabs.Debug:AddSection("Testes Manuais")
        local TRIAL_TESTS = {
            { Label="Star Open x1",   Args={"General","Star","Open",1} },
            { Label="Star Open x10",  Args={"General","Star","Open",10} },
            { Label="Trial Start",    Args={"General","Trial","Start"} },
            { Label="Trial Claim",    Args={"General","Trial","Claim"} },
            { Label="Gacha Spin x1",  Args={"General","Gacha","Spin",1} },
            { Label="Gacha Spin x10", Args={"General","Gacha","Spin",10} },
            { Label="Gacha Open x1",  Args={"General","Gacha","Open",1} },
            { Label="Lucky Spin x1",  Args={"General","LuckySpin","Spin",1} },
        }
        for _, t in ipairs(TRIAL_TESTS) do
            local tt = t
            Tabs.Debug:AddButton({
                Title    = tt.Label,
                Callback = function()
                    fire(table.unpack(tt.Args))
                    warn("[TESTE] " .. tt.Label)
                    Fluent:Notify({ Title="Teste", Content=tt.Label.." enviado.", Duration=3 })
                end,
            })
        end

        Fluent:Notify({ Title="Debug", Content="Aba desbloqueada!", Duration=3 })
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
    Title   = "Desenvolvido por",
    Content = "Danonin",
})

Tabs.Info:AddParagraph({
    Title   = "Discord",
    Content = "discord.gg/qDeZ9sEdGY\nSugestoes e suporte",
})

Tabs.Info:AddButton({
    Title    = "Copiar Discord",
    Callback = function()
        setclipboard("https://discord.gg/qDeZ9sEdGY")
        Fluent:Notify({ Title="Copiado!", Content="Link copiado.", Duration=2 })
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
    Title    = "Cat Empire v5.16",
    Content  = "Carregado com sucesso!",
    Duration = 4,
})
