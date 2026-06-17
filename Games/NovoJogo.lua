-- ============================================================
--  DANONIN HUB | Novo Jogo (Minigame Grade/Gacha)
--  v1.0 | by Danonin
--  PlaceId: SUBSTITUIR_AQUI
-- ============================================================

-- Anti-duplicata
if _G.DanoninNovoJogo then
    pcall(function() _G.DanoninNovoJogo:Destroy() end)
end

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local UIS          = game:GetService("UserInputService")
local player       = Players.LocalPlayer
local pg           = player:WaitForChild("PlayerGui", 10)

-- ============================================================
-- FLUENT
-- ============================================================
local Fluent         = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager    = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- ============================================================
-- CONNECTION — framework customizado do jogo
-- FIX: chamada como função estática, NÃO como método (sem self)
-- ============================================================
local connection = nil
pcall(function()
    connection = require(RS:WaitForChild("frame_work", 5)
        :WaitForChild("library", 5)
        :WaitForChild("connection", 5))
end)

if not connection then
    warn("[Hub] connection nao encontrado — verifique o caminho do framework")
end

-- FIX: send correto — connection.send é função estática, não método
-- Não passa connection como self (isso inseria argumento extra)
local function send(system, categoria, acao, ...)
    if not connection then return end
    local args = {...}
    pcall(function()
        connection.send(
            { tasks = {}, remotes = {}, localTasks = {} },
            system, categoria, acao,
            table.unpack(args)
        )
    end)
end

-- ============================================================
-- AÇÕES CONFIRMADAS (tabela de ações da análise)
-- ============================================================
local A = {}

function A.click()
    send("System", "Game", "_click")
end

function A.open()
    send("System", "Game", "_open")
end

-- FIX: removido "_status" extra — tabela de ações não o lista
-- Parâmetro é só o tipo (ex: "Power3")
function A.grid(tipo)
    send("System", "Game", "_grid", tipo)
end

-- Slot como número (não string — servidor provavelmente espera number)
function A.egg(slot)
    send("System", "_egg", "_open", slot)
end

-- Boost: coins/damage/power/luck → _coins_potion/_damage_potion etc
function A.boost(tipo)
    send("System", "Game", "_use_boost", "_" .. tipo .. "_potion")
end

function A.equipPet(id)
    send("System", "_pets", "_equip", id)
end

function A.equipWeapon(id)
    send("System", "_weapons", "_equip", id)
end

function A.teleport(destino)
    send("System", "Game", "_teleport", "_opc_2", destino)
end

function A.buyEggs(qtd)
    send("System", "Game", "_f2p_shop", "Eggs" .. tostring(qtd))
end

function A.viewGacha(tipo)
    send("System", "Game", "_gachas", "_" .. tipo)
end

-- ============================================================
-- LOOP MANAGER — task.spawn + cancel handle, sem bloquear thread
-- ============================================================
local loops = {}  -- { key = thread }

local function startLoop(key, interval, fn)
    if loops[key] then
        pcall(function() task.cancel(loops[key]) end)
        loops[key] = nil
    end
    loops[key] = task.spawn(function()
        while loops[key] do
            pcall(fn)
            task.wait(interval)
        end
    end)
end

local function stopLoop(key)
    if loops[key] then
        pcall(function() task.cancel(loops[key]) end)
        loops[key] = nil
    end
end

local function stopAll()
    for key in pairs(loops) do stopLoop(key) end
end

-- ============================================================
-- JANELA FLUENT
-- ============================================================
local Window = Fluent:CreateWindow({
    Title      = "Danonin Hub",
    SubTitle   = "v1.0 | Novo Jogo",
    TabWidth   = 160,
    Size       = UDim2.fromOffset(580, 460),
    Acrylic    = true,
    Theme      = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

_G.DanoninNovoJogo = Window

local Tabs = {
    Click    = Window:AddTab({ Title = "Click",    Icon = "mouse-pointer" }),
    Eggs     = Window:AddTab({ Title = "Eggs",     Icon = "package"       }),
    Boosts   = Window:AddTab({ Title = "Boosts",   Icon = "zap"           }),
    Gacha    = Window:AddTab({ Title = "Gacha",    Icon = "star"          }),
    Equip    = Window:AddTab({ Title = "Equip",    Icon = "shield"        }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings"      }),
    Info     = Window:AddTab({ Title = "Info",     Icon = "info"          }),
}
local Options = Fluent.Options

-- ============================================================
-- TAB: CLICK
-- ============================================================
Tabs.Click:AddSection("Auto Click")

-- FIX: velocidade em slider (0.05s ~ 1s)
Tabs.Click:AddSlider("ClickSpeed", {
    Title   = "Velocidade (segundos)",
    Min     = 0.05,
    Max     = 1.0,
    Default = 0.15,
    Rounding = 2,
})

Tabs.Click:AddToggle("AutoClick", { Title = "Auto Click", Default = false })
Options.AutoClick:OnChanged(function(v)
    if v then
        startLoop("click", Options.ClickSpeed.Value, function()
            A.click()
        end)
    else
        stopLoop("click")
    end
end)

Tabs.Click:AddButton({
    Title    = "Click Agora (1x)",
    Callback = function()
        A.click()
        Fluent:Notify({ Title="Click", Content="Clique enviado", Duration=2 })
    end,
})

Tabs.Click:AddSection("Grid")

local GRID_TYPES = { "Power3", "Power2", "Power1", "Speed", "Luck" }

Tabs.Click:AddDropdown("GridType", {
    Title   = "Tipo de Grid",
    Values  = GRID_TYPES,
    Default = "Power3",
})

Tabs.Click:AddButton({
    Title    = "Ativar Grid",
    Callback = function()
        local tipo = Options.GridType.Value or "Power3"
        A.grid(tipo)
        Fluent:Notify({ Title="Grid", Content=tipo.." ativado", Duration=2 })
    end,
})

Tabs.Click:AddToggle("AutoGrid", { Title = "Auto Grid (loop)", Default = false })
Options.AutoGrid:OnChanged(function(v)
    if v then
        startLoop("grid", 1, function()
            A.grid(Options.GridType.Value or "Power3")
        end)
    else
        stopLoop("grid")
    end
end)

-- ============================================================
-- TAB: EGGS
-- ============================================================
Tabs.Eggs:AddSection("Abrir Ovos")

Tabs.Eggs:AddSlider("EggSlot", {
    Title   = "Slot do Ovo",
    Min     = 1,
    Max     = 20,
    Default = 1,
    Rounding = 0,
})

Tabs.Eggs:AddSlider("EggSpeed", {
    Title   = "Velocidade (segundos)",
    Min     = 0.1,
    Max     = 1.0,
    Default = 0.25,
    Rounding = 2,
})

Tabs.Eggs:AddToggle("AutoEgg", { Title = "Auto Egg (infinito)", Default = false })
Options.AutoEgg:OnChanged(function(v)
    if v then
        startLoop("egg", Options.EggSpeed.Value, function()
            A.egg(Options.EggSlot.Value)
        end)
    else
        stopLoop("egg")
    end
end)

Tabs.Eggs:AddButton({
    Title    = "Egg 1x",
    Callback = function()
        A.egg(Options.EggSlot.Value)
        Fluent:Notify({ Title="Egg", Content="Slot "..Options.EggSlot.Value.." aberto", Duration=2 })
    end,
})

Tabs.Eggs:AddSection("Comprar Ovos")

Tabs.Eggs:AddSlider("BuyEggsQtd", {
    Title    = "Quantidade",
    Min      = 10,
    Max      = 1000,
    Default  = 100,
    Rounding = 0,
})

Tabs.Eggs:AddButton({
    Title    = "Comprar Ovos",
    Callback = function()
        local qtd = Options.BuyEggsQtd.Value
        A.buyEggs(qtd)
        Fluent:Notify({ Title="Shop", Content=qtd.." ovos comprados", Duration=2 })
    end,
})

-- ============================================================
-- TAB: BOOSTS
-- ============================================================
Tabs.Boosts:AddSection("Usar Boosts")

local BOOST_TYPES = {
    { Key="coins",  Label="Coins Potion"  },
    { Key="damage", Label="Damage Potion" },
    { Key="power",  Label="Power Potion"  },
    { Key="luck",   Label="Luck Potion"   },
}

for _, b in ipairs(BOOST_TYPES) do
    local bt = b
    Tabs.Boosts:AddButton({
        Title    = bt.Label,
        Callback = function()
            A.boost(bt.Key)
            Fluent:Notify({ Title="Boost", Content=bt.Label.." usado", Duration=2 })
        end,
    })
end

Tabs.Boosts:AddSection("Auto Boost")

Tabs.Boosts:AddSlider("BoostInterval", {
    Title    = "Intervalo (minutos)",
    Min      = 1,
    Max      = 30,
    Default  = 5,
    Rounding = 0,
})

Tabs.Boosts:AddToggle("AutoBoost", { Title = "Auto Usar Todos Boosts", Default = false })
Options.AutoBoost:OnChanged(function(v)
    if v then
        startLoop("boost", Options.BoostInterval.Value * 60, function()
            for _, b in ipairs(BOOST_TYPES) do
                A.boost(b.Key)
                task.wait(0.3)
            end
        end)
    else
        stopLoop("boost")
    end
end)

Tabs.Boosts:AddButton({
    Title    = "Usar Todos Agora",
    Callback = function()
        for _, b in ipairs(BOOST_TYPES) do
            A.boost(b.Key)
            task.wait(0.3)
        end
        Fluent:Notify({ Title="Boosts", Content="Todos os boosts usados", Duration=3 })
    end,
})

-- ============================================================
-- TAB: GACHA
-- ============================================================
Tabs.Gacha:AddSection("Gacha")

local GACHA_TYPES = { "rods", "sail" }

Tabs.Gacha:AddDropdown("GachaType", {
    Title   = "Tipo de Gacha",
    Values  = GACHA_TYPES,
    Default = "rods",
})

Tabs.Gacha:AddButton({
    Title    = "Ver Gacha",
    Callback = function()
        local tipo = Options.GachaType.Value or "rods"
        A.viewGacha(tipo)
        Fluent:Notify({ Title="Gacha", Content=tipo.." aberto", Duration=2 })
    end,
})

-- ============================================================
-- TAB: EQUIP
-- ============================================================
Tabs.Equip:AddSection("Equipar Pet")

Tabs.Equip:AddInput("PetID", {
    Title       = "ID do Pet (hash)",
    Placeholder = "Cole o hash aqui...",
    Numeric     = false,
})

Tabs.Equip:AddButton({
    Title    = "Equipar Pet",
    Callback = function()
        local id = Options.PetID.Value or ""
        if id == "" then
            Fluent:Notify({ Title="Erro", Content="ID vazio", Duration=2 })
            return
        end
        A.equipPet(id)
        Fluent:Notify({ Title="Pet", Content="Equipado", Duration=2 })
    end,
})

Tabs.Equip:AddSection("Equipar Arma")

Tabs.Equip:AddInput("WeaponID", {
    Title       = "ID da Arma (hash)",
    Placeholder = "Cole o hash aqui...",
    Numeric     = false,
})

Tabs.Equip:AddButton({
    Title    = "Equipar Arma",
    Callback = function()
        local id = Options.WeaponID.Value or ""
        if id == "" then
            Fluent:Notify({ Title="Erro", Content="ID vazio", Duration=2 })
            return
        end
        A.equipWeapon(id)
        Fluent:Notify({ Title="Arma", Content="Equipada", Duration=2 })
    end,
})

Tabs.Equip:AddSection("Teleporte")

Tabs.Equip:AddInput("TeleportDest", {
    Title       = "Destino",
    Placeholder = "Nome do destino...",
    Numeric     = false,
})

Tabs.Equip:AddButton({
    Title    = "Teleportar",
    Callback = function()
        local dest = Options.TeleportDest.Value or ""
        if dest == "" then
            Fluent:Notify({ Title="Erro", Content="Destino vazio", Duration=2 })
            return
        end
        A.teleport(dest)
        Fluent:Notify({ Title="Teleporte", Content="Teleportando...", Duration=2 })
    end,
})

-- ============================================================
-- TAB: SETTINGS
-- ============================================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("DanoninHub/NovoJogo")
SaveManager:SetFolder("DanoninHub/NovoJogo/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

-- ============================================================
-- TAB: INFO
-- ============================================================
Tabs.Info:AddSection("Danonin Hub")
Tabs.Info:AddParagraph({ Title="Dev",     Content="Danonin"                })
Tabs.Info:AddParagraph({ Title="Discord", Content="discord.gg/qDeZ9sEdGY" })
Tabs.Info:AddButton({
    Title    = "Copiar Discord",
    Callback = function()
        setclipboard("https://discord.gg/qDeZ9sEdGY")
        Fluent:Notify({ Title="Copiado!", Content="Link copiado.", Duration=2 })
    end,
})
Tabs.Info:AddParagraph({
    Title   = "Keybind",
    Content = "RightControl — Toggle GUI",
})

-- ============================================================
-- BOTÃO FLUTUANTE MINIMIZAR
-- Sem VirtualInputManager, sem Modal
-- Usa apenas fluentSG.Enabled
-- ============================================================
local winVis  = true
local fluentSG = nil

local minSG = Instance.new("ScreenGui")
minSG.Name          = "HubMinGui"
minSG.ResetOnSpawn  = false
minSG.DisplayOrder  = 999
minSG.Parent        = pg

local minFrame = Instance.new("Frame", minSG)
minFrame.Size             = UDim2.fromOffset(54, 54)
minFrame.Position         = UDim2.new(0, 8, 0.5, -27)
minFrame.BackgroundColor3 = Color3.fromRGB(0, 80, 190)
minFrame.BackgroundTransparency = 0.08
minFrame.ZIndex           = 50
minFrame.Active           = true
Instance.new("UICorner", minFrame).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", minFrame)
stroke.Color = Color3.fromRGB(60, 140, 255)

local minImg = Instance.new("ImageLabel", minFrame)
minImg.Size             = UDim2.fromOffset(32, 32)
minImg.Position         = UDim2.new(0.5, -16, 0, 3)
minImg.Image            = "rbxassetid://128797153413520"
minImg.BackgroundTransparency = 1
minImg.ZIndex           = 51

local minLbl = Instance.new("TextLabel", minFrame)
minLbl.Size             = UDim2.new(1, 0, 0, 16)
minLbl.Position         = UDim2.new(0, 0, 1, -17)
minLbl.BackgroundTransparency = 1
minLbl.Text             = "Hub"
minLbl.TextColor3       = Color3.new(1, 1, 1)
minLbl.Font             = Enum.Font.GothamBold
minLbl.TextSize         = 11
minLbl.ZIndex           = 51

local minHit = Instance.new("TextButton", minFrame)
minHit.Size             = UDim2.fromScale(1, 1)
minHit.BackgroundTransparency = 1
minHit.Text             = ""
minHit.ZIndex           = 52
minHit.Active           = true
minHit.Selectable       = false

-- Consome input antes do jogo
minHit.MouseButton1Down:Connect(function() end)
minHit.InputBegan:Connect(function() end)

-- Busca fluentSG — tenta PlayerGui e CoreGui
task.spawn(function()
    for _ = 1, 40 do
        task.wait(0.5)
        local function tryFind(parent)
            for _, sg in ipairs(parent:GetChildren()) do
                if sg:IsA("ScreenGui") and sg.Name ~= "HubMinGui" then
                    for _, ch in ipairs(sg:GetChildren()) do
                        if ch:IsA("Frame") and ch:FindFirstChildOfClass("UICorner") then
                            return sg
                        end
                    end
                end
            end
        end
        fluentSG = tryFind(pg)
        if not fluentSG then
            pcall(function()
                fluentSG = tryFind(game:GetService("CoreGui"))
            end)
        end
        if fluentSG then break end
    end
end)

local function setButtonState(open)
    winVis = open
    minFrame.BackgroundColor3 = open and Color3.fromRGB(0,80,190) or Color3.fromRGB(140,30,30)
    stroke.Color              = open and Color3.fromRGB(60,140,255) or Color3.fromRGB(220,80,80)
    minLbl.Text               = open and "Hub" or ">"
end

local function doMin()
    local newState = not winVis
    if fluentSG then pcall(function() fluentSG.Enabled = newState end) end
    setButtonState(newState)
end

-- Drag + Click no botão
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
            minFrame.Position = UDim2.new(
                sPos.X.Scale, sPos.X.Offset + dx,
                sPos.Y.Scale, sPos.Y.Offset + dy
            )
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
-- INIT
-- ============================================================
Window:SelectTab(1)
SaveManager:LoadAutoloadConfig()

Fluent:Notify({
    Title    = "Danonin Hub",
    Content  = "Novo Jogo carregado!",
    Duration = 4,
})

warn("[Hub] Novo Jogo v1.0 carregado | connection:", connection ~= nil and "OK" or "FALHOU")
