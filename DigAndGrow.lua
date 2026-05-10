-- ============================================================
--  DIG & GROW | v1.0 | by Danonin
--  Roblox: Dig & Grow (Place ID: 75995379831247)
--  Remotes: ReplicatedStorage.Signals.*
-- ============================================================

local Players  = game:GetService("Players")
local RS       = game:GetService("ReplicatedStorage")
local WS       = game:GetService("Workspace")
local UIS      = game:GetService("UserInputService")
local TweenSvc = game:GetService("TweenService")
local player   = Players.LocalPlayer

repeat task.wait() until player:FindFirstChild("PlayerGui")

-- ============================================================
-- FLUENT
-- ============================================================
local ok1, Fluent = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/main.lua", true))()
end)
if not ok1 then
    local ok1b
    ok1b, Fluent = pcall(function()
        return loadstring(game:HttpGet("https://cdn.jsdelivr.net/gh/dawid-scripts/Fluent@master/main.lua", true))()
    end)
    if not ok1b then warn("[DnG] Fluent falhou: "..tostring(Fluent)) return end
end

local ok2, SaveManager = pcall(function()
    return loadstring(game:HttpGet("https://cdn.jsdelivr.net/gh/dawid-scripts/Fluent@master/Addons/SaveManager.lua", true))()
end)
if not ok2 then warn("[DnG] SaveManager: "..tostring(SaveManager)) return end

local ok3, InterfaceManager = pcall(function()
    return loadstring(game:HttpGet("https://cdn.jsdelivr.net/gh/dawid-scripts/Fluent@master/Addons/InterfaceManager.lua", true))()
end)
if not ok3 then warn("[DnG] InterfaceManager: "..tostring(InterfaceManager)) return end

-- ============================================================
-- REMOTES
-- Estrutura: ReplicatedStorage.Signals.<Name>
-- ============================================================
local Signals = RS:WaitForChild("Signals", 10)

local function getSignal(name)
    if not Signals then return nil end
    return Signals:FindFirstChild(name)
end

-- Fire ou Invoke genérico com pcall
local function fireSignal(name, ...)
    local args = {...}
    local sig  = getSignal(name)
    if not sig then
        warn("[DnG] Signal nao encontrado: "..name)
        return nil
    end
    if sig:IsA("RemoteFunction") then
        local ok, res = pcall(function() return sig:InvokeServer(table.unpack(args)) end)
        return ok and res or nil
    elseif sig:IsA("RemoteEvent") then
        pcall(function() sig:FireServer(table.unpack(args)) end)
        return true
    end
    return nil
end

-- ============================================================
-- SAFETY
-- ============================================================
local Safety = { _threads = {}, _active = {} }

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

function Safety:Loop(key, interval, fn)
    self:Kill(key)
    self._active[key] = true
    local t = task.spawn(function()
        while self._active[key] do
            task.wait(interval)
            if self._active[key] then pcall(fn) end
        end
        self._threads[key] = nil
    end)
    self._threads[key] = t
end

function Safety:Toggle(key, enabled, interval, fn)
    if enabled then self:Loop(key, interval, fn) else self:Kill(key) end
end

function Safety:IsActive(key) return self._active[key] == true end

-- ============================================================
-- HELPERS — ESCANEAR PLANTAS DO PLOT
-- ============================================================
local function getMyPlot()
    local plots = WS:FindFirstChild("Plots")
    if not plots then return nil end
    -- Tenta por nome do player
    for _, plot in ipairs(plots:GetChildren()) do
        local owner = plot:GetAttribute("Owner") or plot:GetAttribute("Player")
        if owner == player.Name or owner == tostring(player.UserId) then
            return plot
        end
    end
    -- Fallback: primeiro plot com Floor
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:FindFirstChild("Floor") then return plot end
    end
    return nil
end

local function getPlantUUIDs(plot)
    local uids = {}
    if not plot then return uids end
    -- Escaneia objetos no plot com atributo UUID ou Id
    for _, obj in ipairs(plot:GetDescendants()) do
        local uid = obj:GetAttribute("UUID") or obj:GetAttribute("Id") or obj:GetAttribute("ID")
        if uid then
            local stage = obj:GetAttribute("Stage") or obj:GetAttribute("GrowthStage") or 0
            table.insert(uids, { UID = tostring(uid), Object = obj, Stage = stage })
        end
    end
    return uids
end

local function getReadyFruits(plot)
    -- Frutas prontas para coleta: Stage >= 5 (confirmado no remote CollectFruit com [2]="5")
    local ready = {}
    local plants = getPlantUUIDs(plot)
    for _, p in ipairs(plants) do
        if p.Stage >= 5 then table.insert(ready, p) end
    end
    return ready
end

-- ============================================================
-- FLUENT WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Dig & Grow",
    SubTitle    = "v1.0 | by Danonin",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(680, 460),
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
minSG.Name          = "DnGMinGui"
minSG.ResetOnSpawn  = false
minSG.DisplayOrder  = 999
minSG.Parent        = pg

local minFrame = Instance.new("Frame", minSG)
minFrame.Size             = UDim2.fromOffset(54, 54)
minFrame.Position         = UDim2.new(0, 8, 0.5, -27)
minFrame.BackgroundColor3 = Color3.fromRGB(20, 140, 60)
minFrame.BackgroundTransparency = 0.08
minFrame.ZIndex           = 50
Instance.new("UICorner", minFrame).CornerRadius = UDim.new(0, 12)
Instance.new("UIStroke", minFrame).Color = Color3.fromRGB(60, 220, 100)

local minLbl = Instance.new("TextLabel", minFrame)
minLbl.Size             = UDim2.fromScale(1, 1)
minLbl.BackgroundTransparency = 1
minLbl.Text             = "D&G"
minLbl.TextColor3       = Color3.new(1, 1, 1)
minLbl.Font             = Enum.Font.GothamBold
minLbl.TextSize         = 13
minLbl.ZIndex           = 51

local minHit = Instance.new("TextButton", minFrame)
minHit.Size             = UDim2.fromScale(1, 1)
minHit.BackgroundTransparency = 1
minHit.Text             = ""
minHit.ZIndex           = 52

local fluentSG = nil
task.spawn(function()
    for _ = 1, 30 do
        task.wait(0.5)
        for _, sg in ipairs(pg:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Name == "Fluent" then
                fluentSG = sg break
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
            VIM:SendKeyEvent(true,  Enum.KeyCode.RightControl, false, game)
            task.wait(0.05)
            VIM:SendKeyEvent(false, Enum.KeyCode.RightControl, false, game)
        end)
        winVis = not winVis
    end
    minFrame.BackgroundColor3 = winVis
        and Color3.fromRGB(20, 140, 60) or Color3.fromRGB(140, 30, 30)
    minLbl.Text = winVis and "D&G" or ">"
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
    Farm     = Window:AddTab({ Title = "Farm",     Icon = "sprout"   }),
    Garden   = Window:AddTab({ Title = "Garden",   Icon = "flower-2" }),
    Shop     = Window:AddTab({ Title = "Shop",     Icon = "shopping-cart" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
    Info     = Window:AddTab({ Title = "Info",     Icon = "info"     }),
}
local Options = Fluent.Options

-- ============================================================
-- TAB: FARM — Coleta e mutação automática
-- ============================================================
Tabs.Farm:AddSection("Auto Collect")

-- CollectFruit: FireServer({[1]=UUID, [2]="5"})
local function collectAllReady()
    local plot  = getMyPlot()
    local ready = getReadyFruits(plot)
    local count = 0
    for _, p in ipairs(ready) do
        fireSignal("CollectFruit", p.UID, "5")
        count += 1
        task.wait(0.15)
    end
    return count
end

Tabs.Farm:AddToggle("AutoCollect", { Title = "Auto Collect Fruits", Default = false })
Options.AutoCollect:OnChanged(function(v)
    Safety:Toggle("AutoCollect", v, 3, function()
        collectAllReady()
    end)
end)

Tabs.Farm:AddButton({
    Title    = "Collect Now",
    Callback = function()
        local n = collectAllReady()
        Fluent:Notify({ Title="Collect", Content=n.." fruta(s) coletada(s)", Duration=3 })
    end,
})

Tabs.Farm:AddSection("Auto Mutation")

-- MutationReceptor: InvokeServer(UUID, "5")
-- Aplica mutação em todas as plantas do plot
local mutStage = "5"
Tabs.Farm:AddDropdown("MutStage", {
    Title   = "Mutation Stage",
    Values  = { "1","2","3","4","5","6","7","8","9","10" },
    Default = "5",
})
Options.MutStage:OnChanged(function(v) mutStage = v end)

local function mutateAll()
    local plot   = getMyPlot()
    local plants = getPlantUUIDs(plot)
    local count  = 0
    for _, p in ipairs(plants) do
        fireSignal("MutationReceptor", p.UID, mutStage)
        count += 1
        task.wait(0.15)
    end
    return count
end

Tabs.Farm:AddToggle("AutoMutate", { Title = "Auto Mutate Plants", Default = false })
Options.AutoMutate:OnChanged(function(v)
    Safety:Toggle("AutoMutate", v, 5, function()
        mutateAll()
    end)
end)

Tabs.Farm:AddButton({
    Title    = "Mutate All Now",
    Callback = function()
        local n = mutateAll()
        Fluent:Notify({ Title="Mutation", Content=n.." planta(s) mutada(s)", Duration=3 })
    end,
})

Tabs.Farm:AddSection("Auto Full Farm")

-- Loop completo: coleta + muta + vende
Tabs.Farm:AddToggle("AutoFullFarm", { Title = "Auto Full Farm (Collect+Sell)", Default = false })
Options.AutoFullFarm:OnChanged(function(v)
    Safety:Toggle("AutoFullFarm", v, 5, function()
        collectAllReady()
        task.wait(0.5)
        fireSignal("Shop", "Sell")
    end)
end)

-- ============================================================
-- TAB: GARDEN — Ferramenta e escavação
-- ============================================================
Tabs.Garden:AddSection("Tool")

-- ToolSignal: FireServer({["Target"]=Floor, ["Position"]=Vector3})
-- Usa a pá automaticamente no plot
Tabs.Garden:AddToggle("AutoDig", { Title = "Auto Dig Plot", Default = false })
Options.AutoDig:OnChanged(function(v)
    Safety:Toggle("AutoDig", v, 0.5, function()
        local plot = getMyPlot()
        if not plot then return end
        local floor = plot:FindFirstChild("Floor")
        if not floor then return end
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local pos   = hrp and hrp.Position or Vector3.new(0, 0, 0)
        fireSignal("ToolSignal", {
            ["Target"]   = floor,
            ["Position"] = pos,
        })
    end)
end)

Tabs.Garden:AddButton({
    Title    = "Dig Once",
    Callback = function()
        local plot = getMyPlot()
        if not plot then
            Fluent:Notify({ Title="Garden", Content="Plot nao encontrado!", Duration=3 })
            return
        end
        local floor = plot:FindFirstChild("Floor")
        if not floor then
            Fluent:Notify({ Title="Garden", Content="Floor nao encontrado!", Duration=3 })
            return
        end
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        fireSignal("ToolSignal", {
            ["Target"]   = floor,
            ["Position"] = hrp and hrp.Position or Vector3.new(0,0,0),
        })
        Fluent:Notify({ Title="Garden", Content="Dig enviado", Duration=2 })
    end,
})

Tabs.Garden:AddSection("Plot Info")

local plotPara = Tabs.Garden:AddParagraph({ Title="Plot", Content="Clique em Scan" })

Tabs.Garden:AddButton({
    Title    = "Scan Plot",
    Callback = function()
        local plot = getMyPlot()
        if not plot then
            plotPara:SetDesc("Plot nao encontrado")
            return
        end
        local plants = getPlantUUIDs(plot)
        local ready  = getReadyFruits(plot)
        plotPara:SetDesc(
            "Plot: "..plot.Name..
            "\nPlantas: "..#plants..
            "\nProntas: "..#ready
        )
        Fluent:Notify({ Title="Plot", Content=#plants.." planta(s), "..#ready.." pronta(s)", Duration=3 })
    end,
})

-- ============================================================
-- TAB: SHOP — Compras e vendas
-- ============================================================
Tabs.Shop:AddSection("Sell")

-- Shop: InvokeServer("Sell")
Tabs.Shop:AddButton({
    Title    = "Sell All",
    Callback = function()
        local res = fireSignal("Shop", "Sell")
        Fluent:Notify({ Title="Shop", Content="Sell enviado", Duration=2 })
    end,
})

Tabs.Shop:AddToggle("AutoSell", { Title = "Auto Sell", Default = false })
Options.AutoSell:OnChanged(function(v)
    Safety:Toggle("AutoSell", v, 10, function()
        fireSignal("Shop", "Sell")
    end)
end)

Tabs.Shop:AddSection("Shovels")

-- ShovelBuy: InvokeServer("Gold") — compra pá
local SHOVELS = { "Gold","Wood","Stone","Diamond","Emerald","Obsidian" }

Tabs.Shop:AddDropdown("ShovelType", {
    Title   = "Shovel Type",
    Values  = SHOVELS,
    Default = "Gold",
})

Tabs.Shop:AddButton({
    Title    = "Buy Shovel",
    Callback = function()
        local shovel = Options.ShovelType.Value or "Gold"
        fireSignal("ShovelBuy", shovel)
        Fluent:Notify({ Title="Shop", Content="Compra: "..shovel.." Shovel", Duration=2 })
    end,
})

-- ============================================================
-- TAB: SETTINGS
-- ============================================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("DigAndGrow")
SaveManager:SetFolder("DigAndGrow/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

-- ============================================================
-- TAB: INFO
-- ============================================================
Tabs.Info:AddSection("Dig & Grow v1.0")
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
    Title   = "Remotes Confirmados",
    Content = "CollectFruit · MutationReceptor\nToolSignal · Shop · ShovelBuy",
})
Tabs.Info:AddParagraph({
    Title   = "Keybind",
    Content = "RightControl — Toggle GUI\nBotao D&G — Toggle/Arrastar",
})

-- ============================================================
-- INIT
-- ============================================================
SaveManager:LoadAutoloadConfig()
Window:SelectTab(1)
Fluent:Notify({
    Title   = "Dig & Grow v1.0",
    Content = "Script carregado!",
    Duration = 4,
})
