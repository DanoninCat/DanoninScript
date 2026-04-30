-- ============================================================
--  CAT EMPIRE | v5.3 | CODED FOR DANONIN
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
        local userId = tostring(player.UserId)

        -- Tenta Client.Fighters primeiro (mais atualizado no cliente)
        local roots = {
            WS:FindFirstChild("Client") and WS.Client:FindFirstChild("Fighters"),
            WS:FindFirstChild("Server") and WS.Server:FindFirstChild("Fighters"),
        }

        for _, root in ipairs(roots) do
            if root then
                local myFolder = root:FindFirstChild(userId)
                              or root:FindFirstChild(player.Name)
                if myFolder then
                    for _, fighter in ipairs(myFolder:GetChildren()) do
                        -- Tenta todos os atributos conhecidos
                        local uid = fighter:GetAttribute("UID")
                                 or fighter:GetAttribute("uid")
                                 or fighter:GetAttribute("Id")
                                 or fighter:GetAttribute("FighterUID")
                                 or fighter:GetAttribute("UniqueId")
                        -- Se nao achar atributo, usa o Name do fighter como uid
                        -- (alguns jogos usam o Name como chave)
                        if uid then
                            table.insert(uids, tostring(uid))
                        elseif fighter.Name ~= "" then
                            table.insert(uids, fighter.Name)
                        end
                    end
                    if #uids > 0 then break end
                end
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
local function getNearestEnemy()
    local char = player.Character
    if not char then return nil, nil, nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil, nil end

    local serverObj = WS:FindFirstChild("Server")
    if not serverObj then return nil, nil, nil end
    local serverEnemies = serverObj:FindFirstChild("Enemies")
    if not serverEnemies then return nil, nil, nil end

    local nearest, nearestDist, nearestWorld, nearestID = nil, math.huge, nil, nil

    for _, worldFolder in ipairs(serverEnemies:GetChildren()) do
        if worldFolder.Name == "Dummy" then continue end
        for _, enemy in ipairs(worldFolder:GetChildren()) do
            -- atributo confirmado pelo debug: "ID"
            local enemyID  = enemy:GetAttribute("ID")
            if not enemyID then continue end

            local enemyHRP = enemy:FindFirstChild("HumanoidRootPart")
            -- vida pode vir do atributo "Health" (debug confirmou) ou Humanoid
            local health   = enemy:GetAttribute("Health")
            local hum      = enemy:FindFirstChildOfClass("Humanoid")
            local alive    = (hum and hum.Health > 0)
                          or (type(health) == "number" and health > 0)

            if enemyHRP and alive then
                local dist = (hrp.Position - enemyHRP.Position).Magnitude
                if dist < nearestDist then
                    nearest      = enemy
                    nearestDist  = dist
                    nearestWorld = worldFolder.Name
                    nearestID    = tostring(enemyID)
                end
            end
        end
    end

    return nearest, nearestWorld, nearestID
end

-- ============================================================
-- CONSTANTES
-- ============================================================
local KNOWN_ACHIEVEMENTS = {
    "Defeat I","Defeat II","Defeat III","Defeat IV","Defeat V",
    "Luck I","Luck II","Luck III","Inventory I","Inventory II",
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
    -- No cliente: Teleport só aceita o PlaceId, sem arg player
    pcall(function()
        TeleportService:Teleport(placeId)
    end)
end

-- ============================================================
-- FLUENT WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Cat Empire",
    SubTitle    = "v5.4 | by Danonin",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(720, 480),
    Acrylic     = true,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

-- Botão minimizar flutuante (ImageButton separado do keybind)
local minFloatBtn = Instance.new("ImageButton")
minFloatBtn.Name             = "CatEmpireMinBtn"
minFloatBtn.Size             = UDim2.fromOffset(44,44)
minFloatBtn.Position         = UDim2.new(0, 12, 0.5, -22)
minFloatBtn.Image            = "rbxassetid://128797153413520"
minFloatBtn.BackgroundColor3 = Color3.fromRGB(0, 90, 200)
minFloatBtn.BackgroundTransparency = 0.1
minFloatBtn.ZIndex           = 50
Instance.new("UICorner", minFloatBtn).CornerRadius = UDim.new(0, 10)
minFloatBtn.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

local windowVisible = true
minFloatBtn.MouseButton1Click:Connect(function()
    windowVisible = not windowVisible
    -- Fluent expõe o frame raiz via Fluent.GUI ou CoreGui
    local fluentGui = game:GetService("CoreGui"):FindFirstChild("Fluent")
                   or game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("Fluent")
    if fluentGui then
        fluentGui.Enabled = windowVisible
    end
    minFloatBtn.BackgroundColor3 = windowVisible
        and Color3.fromRGB(0, 90, 200)
        or  Color3.fromRGB(50, 50, 80)
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
    toggleLoop("AutoAttack", v, 0.05, function()
        fire("Fighters","Attack","Click")
    end)
end)

Tabs.Main:AddToggle("AutoFarm", { Title = "Auto Farm", Default = false })
Options.AutoFarm:OnChanged(function(v)
    toggleLoop("AutoFarm", v, 0.35, function()
        local enemy, world, enemyID = getNearestEnemy()
        if not enemy or not world or not enemyID then
            fire("Fighters","Attack","Click")
            return
        end
        -- Move o personagem para perto do inimigo (servidor faz checagem de posição)
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local eHRP = enemy:FindFirstChild("HumanoidRootPart")
        if hrp and eHRP then
            local dist = (hrp.Position - eHRP.Position).Magnitude
            if dist > 20 then
                hrp.CFrame = eHRP.CFrame * CFrame.new(0, 0, 8)
            end
        end
        fire("Fighters","Attack","Attack", world, enemyID)
        task.wait(0.05)
        fire("Fighters","Attack","Do_Damage", enemyID)
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
    toggleLoop("DailyRewards", v, 120, function()
        -- Tenta todos os dias; o servidor ignora os já coletados
        for day = 1, 7 do
            fire("General","DailyRewards","Claim", day)
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
    Content = "Cat Empire v5.4\nDesenvolvido por Danonin",
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
    Title    = "Cat Empire v5.4",
    Content  = "Carregado com sucesso!",
    Duration = 4,
})
