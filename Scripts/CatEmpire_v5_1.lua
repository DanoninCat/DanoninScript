-- ============================================================
--  CAT EMPIRE | v5.1 | CODED FOR DANONIN
-- ============================================================

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UIS              = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Stats            = game:GetService("Stats")
local WS               = game:GetService("Workspace")
local TeleportService  = game:GetService("TeleportService")

local player  = Players.LocalPlayer
local placeId = game.PlaceId

-- Anti-duplicata
if player.PlayerGui:FindFirstChild("CatEmpireGUI") then
    player.PlayerGui.CatEmpireGUI:Destroy()
end

-- ============================================================
-- BRIDGE
-- ============================================================
local RS     = game:GetService("ReplicatedStorage")
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
-- Retorna: enemyModel, worldName, enemyID (atributo "ID" do inimigo)
-- Ignora pasta "Dummy" (Client.Enemies — so animacoes, inutil para farm)
local function getNearestEnemy()
    local char = player.Character
    if not char then return nil, nil, nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil, nil end

    -- APENAS Server.Enemies — Client.Enemies tem so dummies de animacao
    local serverObj = WS:FindFirstChild("Server")
    if not serverObj then return nil, nil, nil end
    local serverEnemies = serverObj:FindFirstChild("Enemies")
    if not serverEnemies then return nil, nil, nil end

    local nearest, nearestDist, nearestWorld, nearestID = nil, math.huge, nil, nil

    for _, worldFolder in pairs(serverEnemies:GetChildren()) do
        -- Pula pasta Dummy
        if worldFolder.Name == "Dummy" then continue end

        for _, enemy in ipairs(worldFolder:GetChildren()) do
            -- ID real do inimigo esta no atributo "ID" (nao UID)
            local enemyID  = enemy:GetAttribute("ID")
            if not enemyID then continue end

            local enemyHRP = enemy:FindFirstChild("HumanoidRootPart")
            local hum      = enemy:FindFirstChildOfClass("Humanoid")
            local health   = enemy:GetAttribute("Health")

            -- Aceita se tem HRP e vida > 0 (via Humanoid ou atributo)
            local alive = (hum and hum.Health > 0)
                       or (health and type(health) == "number" and health > 0)

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

-- Tenta detectar o dia atual de daily rewards ja coletado
-- Retorna o proximo dia disponivel (1..7)
local dailyDay = 1

local KNOWN_ACHIEVEMENTS = {
    "Defeat I","Defeat II","Defeat III","Defeat IV","Defeat V",
    "Luck I","Luck II","Luck III","Inventory I","Inventory II",
}

-- Mundos confirmados pelo debug: Workspace.Server.Enemies[worldName]
local WORLDS = {
    "Leaf Village","Dragon Town","Slayer Village",
    "Pirate Island","Solo City","Z City","Hollow Island","Lobby"
}
local selectedWorld = WORLDS[2]

-- Fighter selection state
local selectedFighterUID  = ""
local selectedFighterName = "Nenhum selecionado"
local fNameLbl -- referencia ao label, definida mais abaixo

local function updateFighterDisplay()
    if fNameLbl then
        if selectedFighterUID ~= "" then
            fNameLbl.Text = selectedFighterName .. "\n" .. selectedFighterUID
            fNameLbl.TextColor3 = Color3.fromRGB(100,230,150)
        else
            fNameLbl.Text = "Nenhum selecionado"
            fNameLbl.TextColor3 = Color3.fromRGB(200,220,255)
        end
    end
end

-- ============================================================
-- DETECTAR FIGHTER DA UI NATIVA DO JOGO
-- Captura UID de qualquer elemento visivel no PlayerGui do jogo
-- (nao no nosso GUI) que tenha atributo de UID/fighter
-- ============================================================
-- Captura fighters do caminho real: Workspace.Server.Fighters[UserId]
-- O NAME de cada filho E o UID. Atributos: Trait, Level, Enabled
local function captureFromGameUI()
    local candidates = {}

    -- FONTE PRIMARIA: Workspace.Server.Fighters[UserId]
    pcall(function()
        local serverObj = WS:FindFirstChild("Server")
        if not serverObj then return end
        local fightersRoot = serverObj:FindFirstChild("Fighters")
        if not fightersRoot then return end
        local playerFolder = fightersRoot:FindFirstChild(tostring(player.UserId))
        if not playerFolder then return end

        for _, fighter in ipairs(playerFolder:GetChildren()) do
            -- Name do objeto = UID do fighter
            local uid   = fighter.Name
            local trait = fighter:GetAttribute("Trait") or "?"
            local level = fighter:GetAttribute("Level") or "?"
            -- Nome de exibicao: Trait + Level (o jogo nao expoe o nome do personagem aqui)
            local displayName = trait .. "  Lv." .. tostring(level)
            table.insert(candidates, {UID=uid, Name=displayName, Source="WS.Server.Fighters"})
        end
    end)

    -- FALLBACK: TextLabels na UI do jogo com padrao UUID
    -- (caso o jogador tenha uma UI de girar aberta mostrando o UID)
    if #candidates == 0 then
        pcall(function()
            local ourGui = player.PlayerGui:FindFirstChild("CatEmpireGUI")
            for _, desc in ipairs(player.PlayerGui:GetDescendants()) do
                if ourGui and desc:IsDescendantOf(ourGui) then continue end
                if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                    local txt = (desc.Text or ""):gsub("%s+","")
                    -- padrao UUID parcial ou completo
                    if txt:match("%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x") then
                        table.insert(candidates, {UID=txt, Name="UI:"..desc.Name, Source="TextLabel"})
                    end
                end
            end
        end)
    end

    return candidates
end

-- ============================================================
-- FUNCTION TABLES
-- ============================================================
local mainFunctions = {
    {
        Name="Auto Attack", Enabled=false, Interval=0.05,
        Run=function() fire("Fighters","Attack","Click") end,
    },
    {
        Name="Auto Farm", Enabled=false, Interval=0.3,
        Run=function()
            -- getNearestEnemy agora retorna o ID real do atributo "ID"
            local enemy, world, enemyID = getNearestEnemy()
            if not enemy or not world or not enemyID then return end
            fire("Fighters","Attack","Attack", world, enemy, enemyID)
            fire("Fighters","Attack","Do_Damage", enemyID)
        end,
    },
    {
        Name="Anti-AFK", Enabled=false, Interval=30,
        Run=function()
            fire("General","AntiAfk","Auto_Click",true)
            fire("General","AntiAfk","Auto_Attack",true)
        end,
    },
    {
        Name="Auto Equip Best", Enabled=false, Interval=3,
        Run=function() fire("General","Fighters","Equip_Best") end,
    },
    {
        Name="Auto Quest", Enabled=false, Interval=15,
        Run=function() fire("General","World_Quest","accept",selectedWorld) end,
    },
    {
        Name="Auto Star Open", Enabled=false, Interval=1.5,
        Run=function() fire("General","Star","Open",1) end,
    },
    {
        -- Percorre achievements conhecidos um por um com delay seguro
        Name="Auto Claim Achiev.", Enabled=false, Interval=8,
        Run=function()
            for _, achName in ipairs(KNOWN_ACHIEVEMENTS) do
                pcall(function()
                    fire("General","Achievements","Claim",achName)
                end)
                task.wait(0.5) -- delay generoso entre cada claim
            end
        end,
    },
    {
        Name="Auto Retreat", Enabled=false, Interval=20,
        Run=function() fire("Fighters","Attack","Retreat_All") end,
    },
}

local rewardsFunctions = {
    {
        -- Tenta coletar o daily do dia atual, depois incrementa
        Name="Daily Reward", Enabled=false, Interval=5,
        Run=function()
            fire("General","DailyRewards","Claim",dailyDay)
            -- Avanca dia ate 7, depois para automaticamente
            if dailyDay < 7 then
                dailyDay += 1
            else
                -- Todos os dias coletados, desativa
                for _, f in ipairs(rewardsFunctions) do
                    if f.Name == "Daily Reward" then f.Enabled = false end
                end
            end
        end,
    },
    {
        Name="Time Rewards", Enabled=false, Interval=300,
        Run=function() fire("General","TimeRewards","Claim",1) end,
    },
    {
        Name="Auto Rank Up", Enabled=false, Interval=10,
        Run=function() fire("General","RankUp","Up") end,
    },
}

local traitsLoopFunc = {
    Name="Auto Traits Reroll", Enabled=false, Interval=1.5,
    Run=function()
        if selectedFighterUID == "" then return end
        fire("General","Traits","Reroll",selectedFighterUID,{})
    end,
}

local statsLoopFunc = {
    Name="Auto Stats Reroll", Enabled=false, Interval=1.5,
    Run=function()
        if selectedFighterUID == "" then return end
        fire("General","StatsReroll","Reroll",selectedFighterUID,{})
    end,
}

local allFunctions = {}
for _, f in ipairs(mainFunctions)    do table.insert(allFunctions, f) end
for _, f in ipairs(rewardsFunctions) do table.insert(allFunctions, f) end
table.insert(allFunctions, traitsLoopFunc)
table.insert(allFunctions, statsLoopFunc)

-- ============================================================
-- LOOP CONTROL
-- ============================================================
local activeLoops = {}

local function createLoop(func)
    local thread = task.spawn(function()
        while true do
            task.wait(func.Interval or 0.2)
            if func.Enabled then
                pcall(function() func.Run() end)
            end
        end
    end)
    table.insert(activeLoops, thread)
end

local function destroyAllLoops()
    for _, t in ipairs(activeLoops) do task.cancel(t) end
    activeLoops = {}
end

-- ============================================================
-- TOAST
-- ============================================================
local toastQueue   = {}
local toastRunning = false

local function showToast(msg)
    table.insert(toastQueue, msg)
    if toastRunning then return end
    toastRunning = true
    task.spawn(function()
        while #toastQueue > 0 do
            local text  = table.remove(toastQueue,1)
            local guiTarget = player.PlayerGui:FindFirstChild("CatEmpireGUI") or game:GetService("CoreGui")
            local toast = Instance.new("Frame", guiTarget)
            toast.Size             = UDim2.fromOffset(300,44)
            toast.Position         = UDim2.new(0.5,-150,1,10)
            toast.BackgroundColor3 = Color3.fromRGB(0,100,210)
            toast.ZIndex           = 20
            Instance.new("UICorner",toast).CornerRadius = UDim.new(0,10)
            local lbl = Instance.new("TextLabel",toast)
            lbl.Size               = UDim2.fromScale(1,1)
            lbl.Text               = text
            lbl.BackgroundTransparency = 1
            lbl.TextColor3         = Color3.new(1,1,1)
            lbl.Font               = Enum.Font.GothamMedium
            lbl.TextSize           = 13
            lbl.ZIndex             = 21
            TweenService:Create(toast, TweenInfo.new(0.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{
                Position = UDim2.new(0.5,-150,1,-60)
            }):Play()
            task.wait(2.5)
            TweenService:Create(toast, TweenInfo.new(0.2),{Position=UDim2.new(0.5,-150,1,10)}):Play()
            task.wait(0.25)
            toast:Destroy()
        end
        toastRunning = false
    end)
end

-- ============================================================
-- GUI ROOT
-- ============================================================
local gui = Instance.new("ScreenGui")
gui.Name           = "CatEmpireGUI"
gui.ResetOnSpawn   = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent         = player.PlayerGui

local FULL_SIZE = UDim2.fromOffset(720,500)
local MINI_SIZE = UDim2.fromOffset(280,52)

local panel = Instance.new("Frame",gui)
panel.Name             = "Panel"
panel.Size             = UDim2.fromOffset(0,0)
panel.Position         = UDim2.fromScale(0.5,0.5)
panel.AnchorPoint      = Vector2.new(0.5,0.5)
panel.BackgroundColor3 = Color3.fromRGB(10,10,16)
panel.BackgroundTransparency = 1
panel.ClipsDescendants = true
Instance.new("UICorner",panel).CornerRadius = UDim.new(0,14)

local panelStroke = Instance.new("UIStroke",panel)
panelStroke.Color     = Color3.fromRGB(0,130,255)
panelStroke.Thickness = 1.5

TweenService:Create(panel, TweenInfo.new(0.38,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{
    Size = FULL_SIZE, BackgroundTransparency = 0,
}):Play()

-- ============================================================
-- HEADER
-- ============================================================
local header = Instance.new("Frame",panel)
header.Size             = UDim2.new(1,0,0,52)
header.BackgroundColor3 = Color3.fromRGB(0,100,220)
header.BorderSizePixel  = 0
Instance.new("UICorner",header).CornerRadius = UDim.new(0,14)
local hFix = Instance.new("Frame",header)
hFix.Size             = UDim2.new(1,0,0.5,0)
hFix.Position         = UDim2.new(0,0,0.5,0)
hFix.BackgroundColor3 = Color3.fromRGB(0,100,220)
hFix.BorderSizePixel  = 0

local titleLbl = Instance.new("TextLabel",header)
titleLbl.Text             = "CAT EMPIRE"
titleLbl.Size             = UDim2.new(1,-120,1,0)
titleLbl.Position         = UDim2.fromOffset(16,0)
titleLbl.BackgroundTransparency = 1
titleLbl.TextColor3       = Color3.new(1,1,1)
titleLbl.Font             = Enum.Font.GothamBlack
titleLbl.TextSize         = 20
titleLbl.TextXAlignment   = Enum.TextXAlignment.Left

local verLbl = Instance.new("TextLabel",header)
verLbl.Text             = "v4.2"
verLbl.Size             = UDim2.fromOffset(40,20)
verLbl.Position         = UDim2.new(0,168,0.5,-10)
verLbl.BackgroundTransparency = 1
verLbl.TextColor3       = Color3.fromRGB(180,220,255)
verLbl.Font             = Enum.Font.GothamMedium
verLbl.TextSize         = 11

local closeBtn = Instance.new("TextButton",header)
closeBtn.Size             = UDim2.fromOffset(36,36)
closeBtn.Position         = UDim2.new(1,-44,0.5,-18)
closeBtn.Text             = "X"
closeBtn.BackgroundColor3 = Color3.fromRGB(200,50,50)
closeBtn.TextColor3       = Color3.new(1,1,1)
closeBtn.Font             = Enum.Font.GothamBold
closeBtn.TextSize         = 14
Instance.new("UICorner",closeBtn).CornerRadius = UDim.new(0,8)

local minBtn = Instance.new("TextButton",header)
minBtn.Size             = UDim2.fromOffset(36,36)
minBtn.Position         = UDim2.new(1,-84,0.5,-18)
minBtn.Text             = "-"
minBtn.BackgroundColor3 = Color3.fromRGB(30,30,45)
minBtn.TextColor3       = Color3.new(1,1,1)
minBtn.Font             = Enum.Font.GothamBold
minBtn.TextSize         = 14
Instance.new("UICorner",minBtn).CornerRadius = UDim.new(0,8)

-- ============================================================
-- STATUS BAR
-- ============================================================
local statusBar = Instance.new("Frame",panel)
statusBar.Size             = UDim2.new(1,0,0,22)
statusBar.Position         = UDim2.new(0,0,1,-22)
statusBar.BackgroundColor3 = Color3.fromRGB(0,75,170)
statusBar.BorderSizePixel  = 0
local sbFix = Instance.new("Frame",statusBar)
sbFix.Size             = UDim2.new(1,0,0.5,0)
sbFix.BackgroundColor3 = Color3.fromRGB(0,75,170)
sbFix.BorderSizePixel  = 0

local statusLbl = Instance.new("TextLabel",statusBar)
statusLbl.Size             = UDim2.new(1,-10,1,0)
statusLbl.Position         = UDim2.fromOffset(10,0)
statusLbl.BackgroundTransparency = 1
statusLbl.TextColor3       = Color3.fromRGB(180,220,255)
statusLbl.Font             = Enum.Font.Gotham
statusLbl.TextSize         = 11
statusLbl.TextXAlignment   = Enum.TextXAlignment.Left
statusLbl.Text             = "Carregando..."

-- watermark
local watermark = Instance.new("TextLabel",panel)
watermark.Size             = UDim2.fromOffset(130,14)
watermark.Position         = UDim2.new(1,-136,1,-38)
watermark.BackgroundTransparency = 1
watermark.TextColor3       = Color3.fromRGB(55,70,105)
watermark.Font             = Enum.Font.Gotham
watermark.TextSize         = 9
watermark.TextXAlignment   = Enum.TextXAlignment.Right
watermark.Text             = "coded for danonin"
watermark.ZIndex           = 5

task.spawn(function()
    while gui.Parent do
        local ok, fps = pcall(function() return math.floor(1/RunService.Heartbeat:Wait()) end)
        local ping = 0
        pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
        local activeFuncs = 0
        for _, f in ipairs(allFunctions) do if f.Enabled then activeFuncs += 1 end end
        statusLbl.Text = ("FPS: %d  |  Ping: %dms  |  Ativos: %d  |  Mundo: %s"):format(
            ok and fps or 0, ping, activeFuncs, selectedWorld
        )
    end
end)

-- ============================================================
-- FLOATING RESTORE BUTTON
-- ============================================================
local floatBtn = Instance.new("ImageButton",gui)
floatBtn.Size             = UDim2.fromOffset(48,48)
floatBtn.Position         = UDim2.new(0,12,0.5,-24)
floatBtn.Image            = "rbxassetid://128797153413520"
floatBtn.BackgroundColor3 = Color3.fromRGB(0,90,200)
floatBtn.BackgroundTransparency = 0.15
floatBtn.Visible          = false
floatBtn.ZIndex           = 30
Instance.new("UICorner",floatBtn).CornerRadius = UDim.new(0,10)

-- ============================================================
-- SIDEBAR + TABS
-- ============================================================
local sidebar = Instance.new("Frame",panel)
sidebar.Position           = UDim2.fromOffset(10,60)
sidebar.Size               = UDim2.fromOffset(148,410)
sidebar.BackgroundTransparency = 1
local sideLayout = Instance.new("UIListLayout",sidebar)
sideLayout.Padding   = UDim.new(0,5)
sideLayout.SortOrder = Enum.SortOrder.LayoutOrder

local tabNames   = {"Main","Rewards","Fighters","Teleport","Rollback","Config","MISC"}
local tabButtons = {}
local tabFrames  = {}
local currentTab = "Main"

for _, name in ipairs(tabNames) do
    local color = Color3.fromRGB(20,20,32)
    if name == "Rollback" then color = Color3.fromRGB(35,10,10) end

    local btn = Instance.new("TextButton",sidebar)
    btn.Size             = UDim2.new(1,0,0,44)
    btn.Text             = name
    btn.BackgroundColor3 = (name == "Main") and Color3.fromRGB(0,120,255) or color
    btn.TextColor3       = (name == "Rollback") and Color3.fromRGB(255,80,80) or Color3.new(1,1,1)
    btn.Font             = Enum.Font.GothamSemibold
    btn.TextSize         = 13
    Instance.new("UICorner",btn).CornerRadius = UDim.new(0,10)
    tabButtons[name] = btn

    local frame = Instance.new("Frame",panel)
    frame.Position           = UDim2.fromOffset(168,58)
    frame.Size               = UDim2.new(1,-178,1,-88)
    frame.BackgroundTransparency = 1
    frame.Visible            = (name == "Main")
    tabFrames[name] = frame

    btn.MouseButton1Click:Connect(function()
        currentTab = name
        for n, f in pairs(tabFrames)  do f.Visible = (n == name) end
        for n, b in pairs(tabButtons) do
            local isRb = (n == "Rollback")
            b.BackgroundColor3 = (n == name) and Color3.fromRGB(0,120,255)
                or (isRb and Color3.fromRGB(35,10,10) or Color3.fromRGB(20,20,32))
            b.TextColor3 = isRb and Color3.fromRGB(255,80,80) or Color3.new(1,1,1)
        end
    end)
end

-- ============================================================
-- UI HELPERS
-- ============================================================
local function makeScroll(parent)
    local s = Instance.new("ScrollingFrame",parent)
    s.Size                = UDim2.fromScale(1,1)
    s.BackgroundTransparency = 1
    s.ScrollBarThickness  = 4
    s.ScrollBarImageColor3 = Color3.fromRGB(0,120,255)
    s.CanvasSize          = UDim2.fromOffset(0,0)
    s.AutomaticCanvasSize = Enum.AutomaticSize.Y
    local layout = Instance.new("UIListLayout",s)
    layout.Padding   = UDim.new(0,8)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    return s
end

local function sectionLbl(parent, text)
    local lbl = Instance.new("TextLabel",parent)
    lbl.Size             = UDim2.new(1,0,0,24)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3       = Color3.fromRGB(0,160,255)
    lbl.Font             = Enum.Font.GothamBold
    lbl.TextSize         = 13
    lbl.TextXAlignment   = Enum.TextXAlignment.Left
    lbl.Text             = text
    return lbl
end

local function infoCard(parent, text, color)
    local card = Instance.new("Frame",parent)
    card.Size             = UDim2.new(1,-8,0,10)
    card.AutomaticSize    = Enum.AutomaticSize.Y
    card.BackgroundColor3 = Color3.fromRGB(15,15,26)
    Instance.new("UICorner",card).CornerRadius = UDim.new(0,10)
    local pad = Instance.new("UIPadding",card)
    pad.PaddingLeft   = UDim.new(0,14) pad.PaddingRight  = UDim.new(0,14)
    pad.PaddingTop    = UDim.new(0,10) pad.PaddingBottom = UDim.new(0,10)
    local lbl = Instance.new("TextLabel",card)
    lbl.Size             = UDim2.new(1,0,0,0)
    lbl.AutomaticSize    = Enum.AutomaticSize.Y
    lbl.BackgroundTransparency = 1
    lbl.TextColor3       = color or Color3.fromRGB(180,200,255)
    lbl.Font             = Enum.Font.GothamMedium
    lbl.TextSize         = 12
    lbl.TextXAlignment   = Enum.TextXAlignment.Left
    lbl.TextWrapped      = true
    lbl.Text             = text
    return card, lbl
end

local function createToggle(parent, func)
    local row = Instance.new("Frame",parent)
    row.Size             = UDim2.new(1,-8,0,56)
    row.BackgroundColor3 = Color3.fromRGB(15,15,26)
    Instance.new("UICorner",row).CornerRadius = UDim.new(0,10)

    local bar = Instance.new("Frame",row)
    bar.Size             = UDim2.fromOffset(4,34)
    bar.Position         = UDim2.fromOffset(0,11)
    bar.BackgroundColor3 = Color3.fromRGB(40,40,55)
    Instance.new("UICorner",bar).CornerRadius = UDim.new(0,4)

    local nameLbl = Instance.new("TextLabel",row)
    nameLbl.Text             = func.Name
    nameLbl.Size             = UDim2.new(0.62,0,1,0)
    nameLbl.Position         = UDim2.fromOffset(18,0)
    nameLbl.BackgroundTransparency = 1
    nameLbl.TextColor3       = Color3.new(1,1,1)
    nameLbl.Font             = Enum.Font.GothamMedium
    nameLbl.TextSize         = 13
    nameLbl.TextXAlignment   = Enum.TextXAlignment.Left

    local intLbl = Instance.new("TextLabel",row)
    intLbl.Text             = (func.Interval or 0.2).."s"
    intLbl.Size             = UDim2.fromOffset(38,20)
    intLbl.Position         = UDim2.new(0.63,0,0.5,-10)
    intLbl.BackgroundTransparency = 1
    intLbl.TextColor3       = Color3.fromRGB(90,130,190)
    intLbl.Font             = Enum.Font.Gotham
    intLbl.TextSize         = 10

    local track = Instance.new("Frame",row)
    track.Size             = UDim2.fromOffset(52,26)
    track.Position         = UDim2.new(1,-66,0.5,-13)
    track.BackgroundColor3 = Color3.fromRGB(35,35,50)
    Instance.new("UICorner",track).CornerRadius = UDim.new(0,13)

    local knob = Instance.new("Frame",track)
    knob.Size             = UDim2.fromOffset(20,20)
    knob.Position         = UDim2.fromOffset(3,3)
    knob.BackgroundColor3 = Color3.new(1,1,1)
    Instance.new("UICorner",knob).CornerRadius = UDim.new(0,10)

    local click = Instance.new("TextButton",track)
    click.Size             = UDim2.fromScale(1,1)
    click.BackgroundTransparency = 1
    click.Text             = ""

    local function setState(v)
        func.Enabled           = v
        track.BackgroundColor3 = v and Color3.fromRGB(0,120,255) or Color3.fromRGB(35,35,50)
        bar.BackgroundColor3   = v and Color3.fromRGB(0,220,100) or Color3.fromRGB(40,40,55)
        TweenService:Create(knob, TweenInfo.new(0.18),{
            Position = v and UDim2.fromOffset(29,3) or UDim2.fromOffset(3,3)
        }):Play()
        showToast(func.Name .. (v and " ativado" or " desativado"))
        if func.Name == "Anti-AFK" and not v then
            pcall(function()
                fire("General","AntiAfk","Auto_Click",false)
                fire("General","AntiAfk","Auto_Attack",false)
            end)
        end
    end

    click.MouseButton1Click:Connect(function() setState(not func.Enabled) end)
    createLoop(func)
    return setState -- retorna setState para controle externo se necessario
end

-- ============================================================
-- TAB MAIN
-- ============================================================
local scrollMain = makeScroll(tabFrames["Main"])
for _, f in ipairs(mainFunctions) do createToggle(scrollMain, f) end

-- ============================================================
-- TAB REWARDS
-- ============================================================
local scrollRewards = makeScroll(tabFrames["Rewards"])
sectionLbl(scrollRewards,"Recompensas:")

-- Daily com indicador de dia atual
local dailyToggleHolder = Instance.new("Frame",scrollRewards)
dailyToggleHolder.Size             = UDim2.new(1,-8,0,80)
dailyToggleHolder.BackgroundColor3 = Color3.fromRGB(15,15,26)
Instance.new("UICorner",dailyToggleHolder).CornerRadius = UDim.new(0,10)

local dailyTitleLbl = Instance.new("TextLabel",dailyToggleHolder)
dailyTitleLbl.Size             = UDim2.new(1,0,0,28)
dailyTitleLbl.Position         = UDim2.fromOffset(14,6)
dailyTitleLbl.BackgroundTransparency = 1
dailyTitleLbl.TextColor3       = Color3.new(1,1,1)
dailyTitleLbl.Font             = Enum.Font.GothamMedium
dailyTitleLbl.TextSize         = 13
dailyTitleLbl.TextXAlignment   = Enum.TextXAlignment.Left
dailyTitleLbl.Text             = "Daily Reward"

local dailyDayLbl = Instance.new("TextLabel",dailyToggleHolder)
dailyDayLbl.Size             = UDim2.new(0.6,0,0,20)
dailyDayLbl.Position         = UDim2.fromOffset(14,34)
dailyDayLbl.BackgroundTransparency = 1
dailyDayLbl.TextColor3       = Color3.fromRGB(90,160,255)
dailyDayLbl.Font             = Enum.Font.Gotham
dailyDayLbl.TextSize         = 11
dailyDayLbl.TextXAlignment   = Enum.TextXAlignment.Left
dailyDayLbl.Text             = "Proximo: Dia " .. dailyDay

-- Atualiza label de dia quando daily roda
task.spawn(function()
    while gui.Parent do
        task.wait(1)
        dailyDayLbl.Text = dailyDay <= 7 and ("Proximo: Dia " .. dailyDay) or "Todos os dias coletados"
    end
end)

-- Toggle do daily manualmente (so o track)
local dTrack = Instance.new("Frame",dailyToggleHolder)
dTrack.Size             = UDim2.fromOffset(52,26)
dTrack.Position         = UDim2.new(1,-66,0.5,-13)
dTrack.BackgroundColor3 = Color3.fromRGB(35,35,50)
Instance.new("UICorner",dTrack).CornerRadius = UDim.new(0,13)
local dKnob = Instance.new("Frame",dTrack)
dKnob.Size             = UDim2.fromOffset(20,20)
dKnob.Position         = UDim2.fromOffset(3,3)
dKnob.BackgroundColor3 = Color3.new(1,1,1)
Instance.new("UICorner",dKnob).CornerRadius = UDim.new(0,10)
local dClick = Instance.new("TextButton",dTrack)
dClick.Size             = UDim2.fromScale(1,1)
dClick.BackgroundTransparency = 1
dClick.Text             = ""

local dailyFunc = rewardsFunctions[1] -- Daily Reward
createLoop(dailyFunc)

dClick.MouseButton1Click:Connect(function()
    dailyFunc.Enabled = not dailyFunc.Enabled
    dTrack.BackgroundColor3 = dailyFunc.Enabled and Color3.fromRGB(0,120,255) or Color3.fromRGB(35,35,50)
    TweenService:Create(dKnob,TweenInfo.new(0.18),{
        Position = dailyFunc.Enabled and UDim2.fromOffset(29,3) or UDim2.fromOffset(3,3)
    }):Play()
    if dailyFunc.Enabled then dailyDay = 1 end -- reseta ao ativar
    showToast("Daily Reward " .. (dailyFunc.Enabled and "ativado (Dia 1)" or "desativado"))
end)

-- Restante das rewards
for i = 2, #rewardsFunctions do
    createToggle(scrollRewards, rewardsFunctions[i])
end

-- ============================================================
-- TAB FIGHTERS
-- ============================================================
local scrollFighters = makeScroll(tabFrames["Fighters"])

sectionLbl(scrollFighters,"Fighter para reroll:")

-- Display do fighter selecionado
local fDisplayRow = Instance.new("Frame",scrollFighters)
fDisplayRow.Size             = UDim2.new(1,-8,0,60)
fDisplayRow.BackgroundColor3 = Color3.fromRGB(15,15,26)
Instance.new("UICorner",fDisplayRow).CornerRadius = UDim.new(0,10)

fNameLbl = Instance.new("TextLabel",fDisplayRow) -- atribuido a variavel exterior
fNameLbl.Size             = UDim2.new(0.6,0,1,0)
fNameLbl.Position         = UDim2.fromOffset(12,0)
fNameLbl.BackgroundTransparency = 1
fNameLbl.TextColor3       = Color3.fromRGB(200,220,255)
fNameLbl.Font             = Enum.Font.GothamMedium
fNameLbl.TextSize         = 11
fNameLbl.TextXAlignment   = Enum.TextXAlignment.Left
fNameLbl.TextWrapped      = true
fNameLbl.Text             = "Nenhum selecionado"

local captureBtn = Instance.new("TextButton",fDisplayRow)
captureBtn.Size             = UDim2.fromOffset(84,36)
captureBtn.Position         = UDim2.new(1,-92,0.5,-18)
captureBtn.Text             = "Capturar\nda UI"
captureBtn.BackgroundColor3 = Color3.fromRGB(0,130,60)
captureBtn.TextColor3       = Color3.new(1,1,1)
captureBtn.Font             = Enum.Font.GothamBold
captureBtn.TextSize         = 11
captureBtn.TextWrapped      = true
Instance.new("UICorner",captureBtn).CornerRadius = UDim.new(0,8)

-- Instrucao de uso do capturar
infoCard(scrollFighters,
    "Como usar: Abra a UI de girar do jogo, selecione o personagem que quer usar, depois clique em 'Capturar da UI'. O script vai detectar o UID automaticamente.",
    Color3.fromRGB(140,180,255)
)

-- Lista de candidatos encontrados (aparece apos captura)
local candidatesHolder = Instance.new("Frame",scrollFighters)
candidatesHolder.Size             = UDim2.new(1,-8,0,0)
candidatesHolder.AutomaticSize    = Enum.AutomaticSize.Y
candidatesHolder.BackgroundTransparency = 1
local candLayout = Instance.new("UIListLayout",candidatesHolder)
candLayout.Padding   = UDim.new(0,6)
candLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- UID manual
sectionLbl(scrollFighters,"UID manual (alternativo):")

local uidRow = Instance.new("Frame",scrollFighters)
uidRow.Size             = UDim2.new(1,-8,0,50)
uidRow.BackgroundColor3 = Color3.fromRGB(15,15,26)
Instance.new("UICorner",uidRow).CornerRadius = UDim.new(0,10)

local uidInput = Instance.new("TextBox",uidRow)
uidInput.Size             = UDim2.new(0.68,0,0,32)
uidInput.Position         = UDim2.fromOffset(10,9)
uidInput.BackgroundColor3 = Color3.fromRGB(22,22,38)
uidInput.TextColor3       = Color3.new(1,1,1)
uidInput.PlaceholderText  = "Cole o UID aqui..."
uidInput.PlaceholderColor3= Color3.fromRGB(70,80,110)
uidInput.Font             = Enum.Font.Code
uidInput.TextSize         = 11
uidInput.ClearTextOnFocus = false
uidInput.TextXAlignment   = Enum.TextXAlignment.Left
uidInput.Text             = ""
Instance.new("UICorner",uidInput).CornerRadius = UDim.new(0,8)
local uidPad = Instance.new("UIPadding",uidInput)
uidPad.PaddingLeft = UDim.new(0,8)

local uidUseBtn = Instance.new("TextButton",uidRow)
uidUseBtn.Size             = UDim2.fromOffset(68,32)
uidUseBtn.Position         = UDim2.new(1,-76,0.5,-16)
uidUseBtn.Text             = "Usar"
uidUseBtn.BackgroundColor3 = Color3.fromRGB(0,100,200)
uidUseBtn.TextColor3       = Color3.new(1,1,1)
uidUseBtn.Font             = Enum.Font.GothamBold
uidUseBtn.TextSize         = 12
Instance.new("UICorner",uidUseBtn).CornerRadius = UDim.new(0,8)

-- Separador
local sep1 = Instance.new("Frame",scrollFighters)
sep1.Size             = UDim2.new(1,0,0,2)
sep1.BackgroundColor3 = Color3.fromRGB(25,25,45)

-- Traits Reroll
sectionLbl(scrollFighters,"Traits Reroll:")
createToggle(scrollFighters, traitsLoopFunc)

local traitsManRow = Instance.new("Frame",scrollFighters)
traitsManRow.Size             = UDim2.new(1,-8,0,44)
traitsManRow.BackgroundColor3 = Color3.fromRGB(15,15,26)
Instance.new("UICorner",traitsManRow).CornerRadius = UDim.new(0,10)
local traitsManLbl = Instance.new("TextLabel",traitsManRow)
traitsManLbl.Size             = UDim2.new(0.65,0,1,0)
traitsManLbl.Position         = UDim2.fromOffset(12,0)
traitsManLbl.BackgroundTransparency = 1
traitsManLbl.TextColor3       = Color3.fromRGB(170,190,230)
traitsManLbl.Font             = Enum.Font.Gotham
traitsManLbl.TextSize         = 11
traitsManLbl.TextXAlignment   = Enum.TextXAlignment.Left
traitsManLbl.Text             = "Reroll manual (1x)"
local traitsManBtn = Instance.new("TextButton",traitsManRow)
traitsManBtn.Size             = UDim2.fromOffset(72,32)
traitsManBtn.Position         = UDim2.new(1,-80,0.5,-16)
traitsManBtn.Text             = "Reroll"
traitsManBtn.BackgroundColor3 = Color3.fromRGB(0,120,255)
traitsManBtn.TextColor3       = Color3.new(1,1,1)
traitsManBtn.Font             = Enum.Font.GothamBold
traitsManBtn.TextSize         = 12
Instance.new("UICorner",traitsManBtn).CornerRadius = UDim.new(0,8)

-- Stats Reroll
local sep2 = Instance.new("Frame",scrollFighters)
sep2.Size             = UDim2.new(1,0,0,2)
sep2.BackgroundColor3 = Color3.fromRGB(25,25,45)
sectionLbl(scrollFighters,"Stats Reroll:")
createToggle(scrollFighters, statsLoopFunc)

local statsManRow = Instance.new("Frame",scrollFighters)
statsManRow.Size             = UDim2.new(1,-8,0,44)
statsManRow.BackgroundColor3 = Color3.fromRGB(15,15,26)
Instance.new("UICorner",statsManRow).CornerRadius = UDim.new(0,10)
local statsManLbl = Instance.new("TextLabel",statsManRow)
statsManLbl.Size             = UDim2.new(0.65,0,1,0)
statsManLbl.Position         = UDim2.fromOffset(12,0)
statsManLbl.BackgroundTransparency = 1
statsManLbl.TextColor3       = Color3.fromRGB(170,190,230)
statsManLbl.Font             = Enum.Font.Gotham
statsManLbl.TextSize         = 11
statsManLbl.TextXAlignment   = Enum.TextXAlignment.Left
statsManLbl.Text             = "Reroll manual (1x)"
local statsManBtn = Instance.new("TextButton",statsManRow)
statsManBtn.Size             = UDim2.fromOffset(72,32)
statsManBtn.Position         = UDim2.new(1,-80,0.5,-16)
statsManBtn.Text             = "Reroll"
statsManBtn.BackgroundColor3 = Color3.fromRGB(0,120,255)
statsManBtn.TextColor3       = Color3.new(1,1,1)
statsManBtn.Font             = Enum.Font.GothamBold
statsManBtn.TextSize         = 12
Instance.new("UICorner",statsManBtn).CornerRadius = UDim.new(0,8)

-- Lock Stat
local sep3 = Instance.new("Frame",scrollFighters)
sep3.Size             = UDim2.new(1,0,0,2)
sep3.BackgroundColor3 = Color3.fromRGB(25,25,45)
sectionLbl(scrollFighters,"Lock Stat:")

local STAT_NAMES  = {"Attack","Defense","Health","Speed"}
local lockBtns    = {}
local selectedStat = "Attack"

-- Grid de botoes de stat
local lockGrid = Instance.new("Frame",scrollFighters)
lockGrid.Size             = UDim2.new(1,-8,0,44)
lockGrid.BackgroundColor3 = Color3.fromRGB(15,15,26)
Instance.new("UICorner",lockGrid).CornerRadius = UDim.new(0,10)
local lockGridLayout = Instance.new("UIListLayout",lockGrid)
lockGridLayout.FillDirection     = Enum.FillDirection.Horizontal
lockGridLayout.VerticalAlignment = Enum.VerticalAlignment.Center
lockGridLayout.Padding           = UDim.new(0,6)
local lockGridPad = Instance.new("UIPadding",lockGrid)
lockGridPad.PaddingLeft = UDim.new(0,8)

for _, stat in ipairs(STAT_NAMES) do
    local b = Instance.new("TextButton",lockGrid)
    b.Size             = UDim2.fromOffset(76,30)
    b.Text             = stat
    b.BackgroundColor3 = (stat == selectedStat) and Color3.fromRGB(0,120,255) or Color3.fromRGB(28,28,45)
    b.TextColor3       = Color3.new(1,1,1)
    b.Font             = Enum.Font.GothamMedium
    b.TextSize         = 11
    Instance.new("UICorner",b).CornerRadius = UDim.new(0,8)
    lockBtns[stat] = b
    b.MouseButton1Click:Connect(function()
        selectedStat = stat
        for s, btn in pairs(lockBtns) do
            btn.BackgroundColor3 = (s == stat) and Color3.fromRGB(0,120,255) or Color3.fromRGB(28,28,45)
        end
    end)
end

local lockApplyRow = Instance.new("Frame",scrollFighters)
lockApplyRow.Size             = UDim2.new(1,-8,0,44)
lockApplyRow.BackgroundColor3 = Color3.fromRGB(15,15,26)
Instance.new("UICorner",lockApplyRow).CornerRadius = UDim.new(0,10)
local lockApplyLbl = Instance.new("TextLabel",lockApplyRow)
lockApplyLbl.Size             = UDim2.new(0.65,0,1,0)
lockApplyLbl.Position         = UDim2.fromOffset(12,0)
lockApplyLbl.BackgroundTransparency = 1
lockApplyLbl.TextColor3       = Color3.fromRGB(170,190,230)
lockApplyLbl.Font             = Enum.Font.Gotham
lockApplyLbl.TextSize         = 11
lockApplyLbl.TextXAlignment   = Enum.TextXAlignment.Left
lockApplyLbl.Text             = "Aplicar lock no stat selecionado"
local lockApplyBtn = Instance.new("TextButton",lockApplyRow)
lockApplyBtn.Size             = UDim2.fromOffset(72,32)
lockApplyBtn.Position         = UDim2.new(1,-80,0.5,-16)
lockApplyBtn.Text             = "Aplicar"
lockApplyBtn.BackgroundColor3 = Color3.fromRGB(180,80,0)
lockApplyBtn.TextColor3       = Color3.new(1,1,1)
lockApplyBtn.Font             = Enum.Font.GothamBold
lockApplyBtn.TextSize         = 12
Instance.new("UICorner",lockApplyBtn).CornerRadius = UDim.new(0,8)

-- ============================================================
-- FIGHTERS: LOGICA DOS BOTOES
-- ============================================================

-- Monta linha de candidato clicavel
local function addCandidateRow(uid, name, source)
    local row = Instance.new("Frame",candidatesHolder)
    row.Size             = UDim2.new(1,0,0,50)
    row.BackgroundColor3 = Color3.fromRGB(15,15,26)
    Instance.new("UICorner",row).CornerRadius = UDim.new(0,10)

    local nLbl = Instance.new("TextLabel",row)
    nLbl.Size             = UDim2.new(0.62,0,0.5,0)
    nLbl.Position         = UDim2.fromOffset(10,2)
    nLbl.BackgroundTransparency = 1
    nLbl.TextColor3       = Color3.new(1,1,1)
    nLbl.Font             = Enum.Font.GothamMedium
    nLbl.TextSize         = 12
    nLbl.TextXAlignment   = Enum.TextXAlignment.Left
    nLbl.Text             = name

    local srcLbl = Instance.new("TextLabel",row)
    srcLbl.Size             = UDim2.new(0.62,0,0,16)
    srcLbl.Position         = UDim2.new(0,10,0.5,2)
    srcLbl.BackgroundTransparency = 1
    srcLbl.TextColor3       = Color3.fromRGB(60,110,180)
    srcLbl.Font             = Enum.Font.Code
    srcLbl.TextSize         = 9
    srcLbl.TextXAlignment   = Enum.TextXAlignment.Left
    srcLbl.Text             = uid .. "  [" .. source .. "]"

    local selBtn = Instance.new("TextButton",row)
    selBtn.Size             = UDim2.fromOffset(72,32)
    selBtn.Position         = UDim2.new(1,-80,0.5,-16)
    selBtn.Text             = "Usar este"
    selBtn.BackgroundColor3 = Color3.fromRGB(0,100,200)
    selBtn.TextColor3       = Color3.new(1,1,1)
    selBtn.Font             = Enum.Font.GothamBold
    selBtn.TextSize         = 11
    selBtn.TextWrapped      = true
    Instance.new("UICorner",selBtn).CornerRadius = UDim.new(0,8)

    selBtn.MouseButton1Click:Connect(function()
        selectedFighterUID  = uid
        selectedFighterName = name
        updateFighterDisplay()
        showToast("Fighter: " .. name)
    end)
end

captureBtn.MouseButton1Click:Connect(function()
    captureBtn.Text = "..."
    -- Limpa lista anterior
    for _, c in ipairs(candidatesHolder:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end

    local candidates = captureFromGameUI()

    if #candidates == 0 then
        infoCard(candidatesHolder,
            "Nenhum UID detectado na UI do jogo.\nAbra a UI de girar, selecione o personagem e tente novamente. Ou use o campo UID manual.",
            Color3.fromRGB(255,120,80)
        )
        showToast("Nenhum UID encontrado na UI")
    else
        -- Remove duplicatas por UID
        local seen = {}
        for _, cand in ipairs(candidates) do
            if not seen[cand.UID] then
                seen[cand.UID] = true
                addCandidateRow(cand.UID, cand.Name, cand.Source)
            end
        end
        showToast(#candidates .. " candidato(s) detectado(s)")
    end

    captureBtn.Text = "Capturar\nda UI"
end)

uidUseBtn.MouseButton1Click:Connect(function()
    local uid = uidInput.Text:gsub("%s+","")
    if uid == "" then showToast("UID vazio") return end
    selectedFighterUID  = uid
    selectedFighterName = "Manual"
    updateFighterDisplay()
    showToast("UID definido")
end)

traitsManBtn.MouseButton1Click:Connect(function()
    if selectedFighterUID == "" then showToast("Selecione um fighter primeiro") return end
    fire("General","Traits","Reroll",selectedFighterUID,{})
    showToast("Traits reroll enviado")
end)

statsManBtn.MouseButton1Click:Connect(function()
    if selectedFighterUID == "" then showToast("Selecione um fighter primeiro") return end
    fire("General","StatsReroll","Reroll",selectedFighterUID,{})
    showToast("Stats reroll enviado")
end)

lockApplyBtn.MouseButton1Click:Connect(function()
    if selectedFighterUID == "" then showToast("Selecione um fighter primeiro") return end
    fire("General","StatsReroll","Lock",selectedFighterUID,selectedStat)
    showToast("Lock: " .. selectedStat .. " aplicado")
end)

-- ============================================================
-- TAB TELEPORT
-- ============================================================
local tpScroll = makeScroll(tabFrames["Teleport"])
sectionLbl(tpScroll,"Selecione o mundo:")

local worldButtons = {}

for _, world in ipairs(WORLDS) do
    local row = Instance.new("Frame",tpScroll)
    row.Size             = UDim2.new(1,-8,0,52)
    row.BackgroundColor3 = Color3.fromRGB(15,15,26)
    Instance.new("UICorner",row).CornerRadius = UDim.new(0,10)

    local wLbl = Instance.new("TextLabel",row)
    wLbl.Text             = world
    wLbl.Size             = UDim2.new(0.52,0,1,0)
    wLbl.Position         = UDim2.fromOffset(14,0)
    wLbl.BackgroundTransparency = 1
    wLbl.TextColor3       = Color3.new(1,1,1)
    wLbl.Font             = Enum.Font.GothamSemibold
    wLbl.TextSize         = 13
    wLbl.TextXAlignment   = Enum.TextXAlignment.Left

    local selBtn = Instance.new("TextButton",row)
    selBtn.Size             = UDim2.fromOffset(84,34)
    selBtn.Position         = UDim2.new(0.52,4,0.5,-17)
    selBtn.Text             = (world == selectedWorld) and "Selecionado" or "Selecionar"
    selBtn.BackgroundColor3 = (world == selectedWorld) and Color3.fromRGB(0,120,255) or Color3.fromRGB(28,28,45)
    selBtn.TextColor3       = Color3.new(1,1,1)
    selBtn.Font             = Enum.Font.GothamMedium
    selBtn.TextSize         = 11
    selBtn.TextWrapped      = true
    Instance.new("UICorner",selBtn).CornerRadius = UDim.new(0,8)
    worldButtons[world] = selBtn

    local tpBtn = Instance.new("TextButton",row)
    tpBtn.Size             = UDim2.fromOffset(62,34)
    tpBtn.Position         = UDim2.new(1,-70,0.5,-17)
    tpBtn.Text             = "Ir agora"
    tpBtn.BackgroundColor3 = Color3.fromRGB(0,160,80)
    tpBtn.TextColor3       = Color3.new(1,1,1)
    tpBtn.Font             = Enum.Font.GothamBold
    tpBtn.TextSize         = 11
    Instance.new("UICorner",tpBtn).CornerRadius = UDim.new(0,8)

    selBtn.MouseButton1Click:Connect(function()
        selectedWorld = world
        for w, b in pairs(worldButtons) do
            b.Text             = (w == world) and "Selecionado" or "Selecionar"
            b.BackgroundColor3 = (w == world) and Color3.fromRGB(0,120,255) or Color3.fromRGB(28,28,45)
        end
        showToast("Mundo: " .. world)
    end)

    tpBtn.MouseButton1Click:Connect(function()
        fire("General","Teleport","Teleport",world)
        showToast("Teleportando para " .. world .. "...")
    end)
end

-- ============================================================
-- TAB ROLLBACK
-- ============================================================
local rbScroll = makeScroll(tabFrames["Rollback"])

infoCard(rbScroll,
    "Como funciona: O jogo salva seus dados a cada alguns minutos. Se voce fizer um reroll ou gastar itens e nao gostar do resultado, clique em 'Rollback + Rejoin' ANTES do servidor salvar. Ao reconectar, seus dados voltam ao estado anterior.",
    Color3.fromRGB(255,160,80)
)

infoCard(rbScroll,
    "Tempo medio de save: 60 a 180 segundos. Use o timer abaixo para controlar o tempo desde a ultima acao.",
    Color3.fromRGB(180,180,255)
)

sectionLbl(rbScroll,"Timer desde ultima acao:")

-- Timer visual
local timerCard = Instance.new("Frame",rbScroll)
timerCard.Size             = UDim2.new(1,-8,0,60)
timerCard.BackgroundColor3 = Color3.fromRGB(15,15,26)
Instance.new("UICorner",timerCard).CornerRadius = UDim.new(0,10)

local timerLbl = Instance.new("TextLabel",timerCard)
timerLbl.Size             = UDim2.new(0.55,0,1,0)
timerLbl.Position         = UDim2.fromOffset(14,0)
timerLbl.BackgroundTransparency = 1
timerLbl.TextColor3       = Color3.fromRGB(255,200,80)
timerLbl.Font             = Enum.Font.GothamBold
timerLbl.TextSize         = 22
timerLbl.TextXAlignment   = Enum.TextXAlignment.Left
timerLbl.Text             = "0:00"

local timerRunning  = false
local timerStart    = 0
local timerThread   = nil

local startTimerBtn = Instance.new("TextButton",timerCard)
startTimerBtn.Size             = UDim2.fromOffset(82,34)
startTimerBtn.Position         = UDim2.new(1,-90,0.5,-17)
startTimerBtn.Text             = "Iniciar"
startTimerBtn.BackgroundColor3 = Color3.fromRGB(0,140,60)
startTimerBtn.TextColor3       = Color3.new(1,1,1)
startTimerBtn.Font             = Enum.Font.GothamBold
startTimerBtn.TextSize         = 12
Instance.new("UICorner",startTimerBtn).CornerRadius = UDim.new(0,8)

local function startTimer()
    timerRunning = true
    timerStart   = tick()
    startTimerBtn.Text             = "Resetar"
    startTimerBtn.BackgroundColor3 = Color3.fromRGB(120,100,0)
    if timerThread then task.cancel(timerThread) end
    timerThread = task.spawn(function()
        while timerRunning do
            task.wait(0.5)
            local elapsed = tick() - timerStart
            local mins    = math.floor(elapsed / 60)
            local secs    = math.floor(elapsed % 60)
            timerLbl.Text = string.format("%d:%02d", mins, secs)
            -- Aviso visual quando chega perto do save (90s)
            if elapsed >= 90 then
                timerLbl.TextColor3 = Color3.fromRGB(255,60,60)
            elseif elapsed >= 60 then
                timerLbl.TextColor3 = Color3.fromRGB(255,160,40)
            else
                timerLbl.TextColor3 = Color3.fromRGB(255,200,80)
            end
        end
    end)
end

startTimerBtn.MouseButton1Click:Connect(function()
    startTimer()
    showToast("Timer iniciado")
end)

sectionLbl(rbScroll,"Rollback:")

-- Botao de rollback principal
local rbCard = Instance.new("Frame",rbScroll)
rbCard.Size             = UDim2.new(1,-8,0,70)
rbCard.BackgroundColor3 = Color3.fromRGB(30,8,8)
Instance.new("UICorner",rbCard).CornerRadius = UDim.new(0,12)
local rbStroke = Instance.new("UIStroke",rbCard)
rbStroke.Color     = Color3.fromRGB(200,40,40)
rbStroke.Thickness = 1.5

local rbInfoLbl = Instance.new("TextLabel",rbCard)
rbInfoLbl.Size             = UDim2.new(0.55,0,1,0)
rbInfoLbl.Position         = UDim2.fromOffset(14,0)
rbInfoLbl.BackgroundTransparency = 1
rbInfoLbl.TextColor3       = Color3.fromRGB(255,100,100)
rbInfoLbl.Font             = Enum.Font.GothamMedium
rbInfoLbl.TextSize         = 12
rbInfoLbl.TextXAlignment   = Enum.TextXAlignment.Left
rbInfoLbl.TextWrapped      = true
rbInfoLbl.Text             = "Volta no tempo.\nRejoina antes do save."

local rbBtn = Instance.new("TextButton",rbCard)
rbBtn.Size             = UDim2.fromOffset(110,42)
rbBtn.Position         = UDim2.new(1,-118,0.5,-21)
rbBtn.Text             = "ROLLBACK\n+ REJOIN"
rbBtn.BackgroundColor3 = Color3.fromRGB(180,30,30)
rbBtn.TextColor3       = Color3.new(1,1,1)
rbBtn.Font             = Enum.Font.GothamBlack
rbBtn.TextSize         = 12
rbBtn.TextWrapped      = true
Instance.new("UICorner",rbBtn).CornerRadius = UDim.new(0,10)

-- Confirmacao antes de rejoin (evita clique acidental)
local rbConfirmPending = false
local rbConfirmThread  = nil

rbBtn.MouseButton1Click:Connect(function()
    if not rbConfirmPending then
        rbConfirmPending        = true
        rbBtn.Text              = "CONFIRMAR?"
        rbBtn.BackgroundColor3  = Color3.fromRGB(220,120,0)
        showToast("Clique de novo para confirmar o rollback")
        if rbConfirmThread then task.cancel(rbConfirmThread) end
        rbConfirmThread = task.spawn(function()
            task.wait(3)
            rbConfirmPending       = false
            rbBtn.Text             = "ROLLBACK\n+ REJOIN"
            rbBtn.BackgroundColor3 = Color3.fromRGB(180,30,30)
        end)
    else
        -- Confirmado — executa rejoin
        rbConfirmPending = false
        if rbConfirmThread then task.cancel(rbConfirmThread) end
        showToast("Executando rollback...")
        -- Para todos os loops primeiro
        for _, f in ipairs(allFunctions) do f.Enabled = false end
        pcall(function()
            fire("General","AntiAfk","Auto_Click",false)
            fire("General","AntiAfk","Auto_Attack",false)
        end)
        task.wait(0.3)
        -- Rejoin no mesmo servidor (rollback via reconexao rapida)
        pcall(function()
            TeleportService:Teleport(placeId, player)
        end)
    end
end)

-- ============================================================
-- TAB CONFIG
-- ============================================================
local cfgScroll = makeScroll(tabFrames["Config"])
sectionLbl(cfgScroll,"Opacidade do painel:")

local opRow = Instance.new("Frame",cfgScroll)
opRow.Size             = UDim2.new(1,-8,0,40)
opRow.BackgroundColor3 = Color3.fromRGB(15,15,26)
Instance.new("UICorner",opRow).CornerRadius = UDim.new(0,10)
local opTrack = Instance.new("Frame",opRow)
opTrack.Size             = UDim2.new(0.72,0,0,6)
opTrack.Position         = UDim2.new(0,14,0.5,-3)
opTrack.BackgroundColor3 = Color3.fromRGB(35,35,55)
Instance.new("UICorner",opTrack).CornerRadius = UDim.new(0,3)
local opFill = Instance.new("Frame",opTrack)
opFill.Size             = UDim2.fromScale(1,1)
opFill.BackgroundColor3 = Color3.fromRGB(0,120,255)
Instance.new("UICorner",opFill).CornerRadius = UDim.new(0,3)
local opVal = Instance.new("TextLabel",opRow)
opVal.Size             = UDim2.fromOffset(55,40)
opVal.Position         = UDim2.new(0.73,4,0,0)
opVal.BackgroundTransparency = 1
opVal.TextColor3       = Color3.new(1,1,1)
opVal.Font             = Enum.Font.GothamMedium
opVal.TextSize         = 13
opVal.Text             = "100%"

local opDrag = false
local function setOpacity(v)
    v = math.clamp(v,0,1)
    opFill.Size                  = UDim2.fromScale(1-v,1)
    opVal.Text                   = math.floor((1-v)*100).."%"
    panel.BackgroundTransparency = v
    panelStroke.Transparency     = v
end
opTrack.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then opDrag = true end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then opDrag = false end
end)
UIS.InputChanged:Connect(function(i)
    if opDrag and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local x = math.clamp(i.Position.X - opTrack.AbsolutePosition.X, 0, opTrack.AbsoluteSize.X)
        setOpacity(1 - x/opTrack.AbsoluteSize.X)
    end
end)

sectionLbl(cfgScroll,"Atalho de teclado:")
local kbInfo = Instance.new("TextLabel",cfgScroll)
kbInfo.Size             = UDim2.new(1,-8,0,38)
kbInfo.BackgroundColor3 = Color3.fromRGB(15,15,26)
kbInfo.TextColor3       = Color3.fromRGB(180,220,255)
kbInfo.Font             = Enum.Font.GothamMedium
kbInfo.TextSize         = 13
kbInfo.Text             = "RightControl — Mostrar / Ocultar GUI"
kbInfo.TextWrapped      = true
Instance.new("UICorner",kbInfo).CornerRadius = UDim.new(0,10)

-- ============================================================
-- TAB MISC
-- ============================================================
local miscScroll = makeScroll(tabFrames["MISC"])

sectionLbl(miscScroll,"Sobre o script:")
infoCard(miscScroll,"CAT EMPIRE  v4.2\nScript criado por DANONIN para a comunidade.", Color3.fromRGB(200,220,255))

sectionLbl(miscScroll,"Servidor do Discord:")
infoCard(miscScroll,"Entre para novidades, suporte e atualizacoes:\ndiscord.gg/qDeZ9sEdGY", Color3.fromRGB(120,180,255))

local copyBtn = Instance.new("TextButton",miscScroll)
copyBtn.Size             = UDim2.new(1,-8,0,40)
copyBtn.BackgroundColor3 = Color3.fromRGB(88,101,242)
copyBtn.TextColor3       = Color3.new(1,1,1)
copyBtn.Font             = Enum.Font.GothamBold
copyBtn.TextSize         = 13
copyBtn.Text             = "Copiar link do Discord"
Instance.new("UICorner",copyBtn).CornerRadius = UDim.new(0,10)
copyBtn.MouseButton1Click:Connect(function()
    pcall(function() setclipboard("https://discord.gg/qDeZ9sEdGY") end)
    showToast("Link copiado!")
end)

sectionLbl(miscScroll,"Sugestoes:")
infoCard(miscScroll,"Tem uma ideia para o script?\nMande no canal de sugestoes do Discord.\nTodas serao lidas.", Color3.fromRGB(170,200,255))

-- ============================================================
-- MINIMIZAR / FECHAR / FLOAT
-- ============================================================
local minimized = false

local function setMinimized(v)
    minimized = v
    minBtn.Text = v and "+" or "-"
    TweenService:Create(panel, TweenInfo.new(0.25,Enum.EasingStyle.Quad),{
        Size = v and MINI_SIZE or FULL_SIZE
    }):Play()
    sidebar.Visible   = not v
    statusBar.Visible = not v
    watermark.Visible = not v
    for name, frame in pairs(tabFrames) do
        frame.Visible = (not v) and (name == currentTab)
    end
end

minBtn.MouseButton1Click:Connect(function() setMinimized(not minimized) end)

closeBtn.MouseButton1Click:Connect(function()
    pcall(function()
        fire("General","AntiAfk","Auto_Click",false)
        fire("General","AntiAfk","Auto_Attack",false)
    end)
    destroyAllLoops()
    TweenService:Create(panel, TweenInfo.new(0.2),{
        Size = UDim2.fromOffset(0,0), BackgroundTransparency = 1,
    }):Play()
    task.delay(0.25, function() gui:Destroy() end)
end)

floatBtn.MouseButton1Click:Connect(function()
    panel.Visible    = true
    floatBtn.Visible = false
end)

-- ============================================================
-- KEYBIND
-- ============================================================
UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        local visible    = not panel.Visible
        panel.Visible    = visible
        floatBtn.Visible = not visible
    end
end)

-- ============================================================
-- DRAG
-- ============================================================
local dragging, dragStart, startPos = false, nil, nil
local function beginDrag(pos) dragging=true dragStart=pos startPos=panel.Position end
local function updateDrag(pos)
    if not dragging then return end
    local d = pos - dragStart
    panel.Position = UDim2.new(
        startPos.X.Scale, startPos.X.Offset + d.X,
        startPos.Y.Scale, startPos.Y.Offset + d.Y
    )
end
local function endDrag() dragging=false end

header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then beginDrag(i.Position) end
end)
UIS.InputChanged:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch then updateDrag(i.Position) end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then endDrag() end
end)

-- ============================================================
-- INIT
-- ============================================================
showToast("CAT EMPIRE v4.2 carregado")
