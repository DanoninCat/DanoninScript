-- ============================================================
--  CAT EMPIRE | v5.8 | CODED FOR DANONIN
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
-- Funciona interceptando "Architect","Data","Receiver" do OnClientEvent
-- O servidor manda a tabela COMPLETA do player a cada update
-- Ao executar rollback: restaura a tabela via bridge + rejoin
-- ============================================================
local rollbackActive   = false
local rollbackSnapshot = nil  -- tabela completa capturada no momento da ativação
local rollbackConn     = nil  -- conexão OnClientEvent
local rollbackTime     = nil  -- horário do snapshot

local function deepCopy(original)
    if type(original) ~= "table" then return original end
    local copy = {}
    for k, v in pairs(original) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function startRollbackCapture()
    rollbackSnapshot = nil
    rollbackTime     = nil

    local bridge = getBridge()
    if not bridge then
        Fluent:Notify({ Title="Rollback", Content="Bridge não encontrado!", Duration=3 })
        return
    end

    -- Aguarda o próximo Architect,Data,Receiver e salva a tabela completa
    rollbackConn = bridge.OnClientEvent:Connect(function(...)
        local args = {...}
        if args[1] == "Architect" and args[2] == "Data" and args[3] == "Receiver" then
            if rollbackSnapshot == nil then
                -- Primeira tabela recebida após ativar = estado no momento da ativação
                rollbackSnapshot = deepCopy(args[4])
                rollbackTime     = os.date("%H:%M:%S")
                Fluent:Notify({
                    Title   = "Rollback",
                    Content = "Estado salvo às " .. rollbackTime .. "!",
                    Duration = 3,
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
            Title   = "Rollback",
            Content = "Nenhum snapshot salvo! Ative o toggle primeiro.",
            Duration = 3,
        })
        return
    end

    Fluent:Notify({
        Title   = "Rollback",
        Content = "Restaurando estado de " .. (rollbackTime or "?") .. "...",
        Duration = 2,
    })

    -- Restaura a tabela no servidor via bridge
    -- O servidor aceita Architect,Data,Receiver de volta para atualizar os dados
    pcall(function()
        fire("Architect","Data","Receiver", rollbackSnapshot)
    end)

    task.wait(0.8)

    -- Rejoin para garantir que o servidor salve o estado restaurado
    pcall(function()
        TeleportService:Teleport(placeId)
    end)
end

-- ============================================================
-- FLUENT WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Cat Empire",
    SubTitle    = "v5.8 | by Danonin",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(720, 480),
    Acrylic     = true,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

-- Botão minimizar flutuante
local minSG = Instance.new("ScreenGui")
minSG.Name            = "CatEmpireMinGui"
minSG.ResetOnSpawn    = false
minSG.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
minSG.DisplayOrder    = 999
local minOk = pcall(function() minSG.Parent = game:GetService("CoreGui") end)
if not minOk then minSG.Parent = player:WaitForChild("PlayerGui") end

local minFloatBtn = Instance.new("ImageButton", minSG)
minFloatBtn.Name             = "CatEmpireMinBtn"
minFloatBtn.Size             = UDim2.fromOffset(44, 44)
minFloatBtn.Position         = UDim2.new(0, 12, 0.5, -22)
minFloatBtn.Image            = "rbxassetid://128797153413520"
minFloatBtn.BackgroundColor3 = Color3.fromRGB(0, 90, 200)
minFloatBtn.BackgroundTransparency = 0.1
minFloatBtn.ZIndex           = 50
minFloatBtn.Active           = true
minFloatBtn.Selectable       = true
Instance.new("UICorner", minFloatBtn).CornerRadius = UDim.new(0, 10)

-- Drag do botão flutuante — corrigido: distingue drag de click
local fbDragging  = false
local fbDragStart = nil
local fbStartPos  = nil
local fbMoved     = false  -- detecta se houve movimento real

minFloatBtn.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        fbDragging  = true
        fbMoved     = false
        fbDragStart = Vector2.new(i.Position.X, i.Position.Y)
        fbStartPos  = minFloatBtn.Position
    end
end)

game:GetService("UserInputService").InputChanged:Connect(function(i)
    if not fbDragging then return end
    if i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch then
        local dx = i.Position.X - fbDragStart.X
        local dy = i.Position.Y - fbDragStart.Y
        -- Só move se arrastou mais de 4px (evita sumir no tap)
        if math.abs(dx) > 4 or math.abs(dy) > 4 then
            fbMoved = true
            minFloatBtn.Position = UDim2.new(
                fbStartPos.X.Scale, fbStartPos.X.Offset + dx,
                fbStartPos.Y.Scale, fbStartPos.Y.Offset + dy
            )
        end
    end
end)

game:GetService("UserInputService").InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        fbDragging = false
        -- Se não moveu, trata como click (toggle janela)
        if not fbMoved then
            windowVisible = not windowVisible
            -- Tenta esconder o frame principal do Fluent
            if fluentFrame then
                fluentFrame.Visible = windowVisible
            elseif fluentRoot then
                fluentRoot.Enabled = windowVisible
            end
            minFloatBtn.BackgroundColor3 = windowVisible
                and Color3.fromRGB(0, 90, 200)
                or  Color3.fromRGB(120, 30, 30)
        end
        fbMoved = false
    end
end)

local windowVisible = true
local fluentRoot    = nil
local fluentFrame   = nil  -- frame principal do Fluent

task.delay(0.8, function()
    -- Busca o ScreenGui do Fluent
    local function findFluent(parent)
        for _, sg in ipairs(parent:GetChildren()) do
            if sg:IsA("ScreenGui") then
                -- Pega o primeiro Frame filho (janela principal do Fluent)
                for _, ch in ipairs(sg:GetChildren()) do
                    if ch:IsA("Frame") then
                        fluentFrame = ch
                        fluentRoot  = sg
                        return true
                    end
                end
            end
        end
        return false
    end
    if not findFluent(game:GetService("CoreGui")) then
        findFluent(player.PlayerGui)
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
    -- 20min de intervalo — reward de tempo geralmente tem cooldown
    toggleLoop("TimeRewards", v, 1200, function()
        for i = 1, 5 do
            fire("General","TimeRewards","Claim", i)
            task.wait(0.3)
        end
    end)
end)

Tabs.Rewards:AddButton({
    Title    = "Claim Time (Agora)",
    Callback = function()
        for i = 1, 5 do
            fire("General","TimeRewards","Claim", i)
            task.wait(0.3)
        end
        Fluent:Notify({ Title="Time Reward", Content="Claim enviado", Duration=2 })
    end,
})

Tabs.Rewards:AddToggle("AutoRankUp", { Title = "Auto Rank Up", Default = false })
Options.AutoRankUp:OnChanged(function(v)
    toggleLoop("AutoRankUp", v, 10, function()
        fire("General","RankUp","Up")
    end)
end)

-- Bridge confirmado: "General","Achievements","Claim", nome
-- Servidor responde: "Not ready to be claimed" se não completou ainda — normal
local function claimAllAchievements()
    for _, name in ipairs(KNOWN_ACHIEVEMENTS) do
        fire("General","Achievements","Claim", name)
        task.wait(0.5)
    end
end

Tabs.Rewards:AddToggle("AutoAchiev", { Title = "Auto Claim Achievements", Default = false })
Options.AutoAchiev:OnChanged(function(v)
    toggleLoop("AutoAchiev", v, 60, claimAllAchievements)
end)

Tabs.Rewards:AddButton({
    Title    = "Claim Achievements (Agora)",
    Callback = function()
        claimAllAchievements()
        Fluent:Notify({ Title="Achievements", Content="Claim enviado", Duration=2 })
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
    Content = "Ative o toggle — o script salva automaticamente o primeiro pacote de dados que o servidor mandar.\nAo executar Rollback, restaura os dados e faz rejoin.",
})

local rollbackStatusParagraph = Tabs.Rollback:AddParagraph({
    Title   = "Status",
    Content = "Inativo — nenhum snapshot salvo",
})

Tabs.Rollback:AddToggle("RollbackCapture", { Title = "Ativar Captura de Estado", Default = false })
Options.RollbackCapture:OnChanged(function(v)
    rollbackActive = v
    if v then
        rollbackSnapshot = nil  -- reseta para capturar novo snapshot
        startRollbackCapture()
        rollbackStatusParagraph:SetDesc("Aguardando pacote do servidor...")
    else
        stopRollbackCapture()
        if rollbackSnapshot then
            rollbackStatusParagraph:SetDesc("Snapshot salvo às " .. (rollbackTime or "?") .. " — pronto para rollback")
        else
            rollbackStatusParagraph:SetDesc("Desativado — nenhum snapshot capturado")
        end
        Fluent:Notify({ Title="Rollback", Content="Captura encerrada.", Duration=2 })
    end
end)

Tabs.Rollback:AddButton({
    Title    = "Executar Rollback",
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
    Content = "Cat Empire v5.8\nDesenvolvido por Danonin",
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
    Title    = "Cat Empire v5.8",
    Content  = "Carregado com sucesso!",
    Duration = 4,
})
