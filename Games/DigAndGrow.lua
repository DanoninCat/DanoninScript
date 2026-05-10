-- ============================================================
--  DIG & GROW | v1.5 | by Danonin
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
    return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua", true))()
end)
if not ok1 then
    local ok1b
    ok1b, Fluent = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/dist/main.lua", true))()
    end)
    if not ok1b then warn("[DnG] Fluent falhou: "..tostring(Fluent)) return end
end

local ok2, SaveManager = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua", true))()
end)
if not ok2 then warn("[DnG] SaveManager: "..tostring(SaveManager)) return end

local ok3, InterfaceManager = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua", true))()
end)
if not ok3 then warn("[DnG] InterfaceManager: "..tostring(InterfaceManager)) return end

-- ============================================================
-- REMOTES — auto-scan de RS.Signals e RS inteiro
-- Só ToolSignal foi confirmado. Os outros precisam ser detectados.
-- ============================================================
local Signals = RS:FindFirstChild("Signals")

-- Mapeia todos os remotes encontrados
local foundSignals = {}  -- { name = remote }

local function scanSignals()
    foundSignals = {}
    local function scan(parent, prefix)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                local key = prefix == "" and child.Name or (prefix.."."..child.Name)
                foundSignals[key] = child
            end
            scan(child, prefix == "" and child.Name or (prefix.."."..child.Name))
        end
    end
    -- Escaneia RS.Signals primeiro, depois RS inteiro como fallback
    if Signals then scan(Signals, "") end
    scan(RS, "RS")
end

scanSignals() -- roda na inicialização

-- Tenta encontrar um remote por lista de nomes possíveis
local function findAny(names)
    -- Primeiro: RS.Signals direto
    if Signals then
        for _, name in ipairs(names) do
            local r = Signals:FindFirstChild(name)
            if r then return r, name end
            -- Case-insensitive
            for _, child in ipairs(Signals:GetDescendants()) do
                if child.Name:lower() == name:lower()
                and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
                    return child, child.Name
                end
            end
        end
    end
    -- Segundo: RS inteiro
    for _, name in ipairs(names) do
        for _, child in ipairs(RS:GetDescendants()) do
            if child.Name:lower() == name:lower()
            and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
                return child, child.Name
            end
        end
    end
    return nil, nil
end

local function fire(remote, ...)
    if not remote then return nil end
    local args = {...}
    if remote:IsA("RemoteFunction") then
        local ok, res = pcall(function() return remote:InvokeServer(table.unpack(args)) end)
        return ok and res or nil
    else
        pcall(function() remote:FireServer(table.unpack(args)) end)
        return true
    end
end

-- Remotes detectados (nil até serem encontrados)
local R = {
    Tool    = findAny({"ToolSignal","Tool","Dig","UseTool","ToolUse"}),
    Collect = findAny({"CollectFruit","Collect","HarvestFruit","Harvest","PickFruit","Pick"}),
    Mutate  = findAny({"MutationReceptor","Mutate","Mutation","ApplyMutation","MutateSignal"}),
    Sell    = findAny({"Shop","Sell","SellAll","Market","Store"}),
    Shovel  = findAny({"ShovelBuy","BuyShovel","Shovel","Purchase"}),
    Plant   = findAny({"PlantSeed","Plant","Seed","PlantSignal"}),
    Water   = findAny({"Water","WaterPlant","Irrigate"}),
}

-- Log do que foi encontrado
task.spawn(function()
    task.wait(2)
    warn("=== DIG & GROW — Remotes encontrados ===")
    for k, v in pairs(R) do
        warn(k .. ": " .. (v and v.Name or "NAO ENCONTRADO"))
    end
    warn("=== Total em RS.Signals: " .. (Signals and #Signals:GetChildren() or 0) .. " ===")
    if Signals then
        for _, child in ipairs(Signals:GetDescendants()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                warn("  Signal: " .. child.Name .. " [" .. child.ClassName .. "]")
            end
        end
    end
end)

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
    -- Tenta múltiplos caminhos comuns em jogos de farm
    local roots = {
        WS:FindFirstChild("Plots"),
        WS:FindFirstChild("Map") and WS.Map:FindFirstChild("Plots"),
        WS:FindFirstChild("World") and WS.World:FindFirstChild("Plots"),
        WS:FindFirstChild("Game") and WS.Game:FindFirstChild("Plots"),
    }
    for _, root in ipairs(roots) do
        if root then
            for _, plot in ipairs(root:GetChildren()) do
                local owner = plot:GetAttribute("Owner")
                           or plot:GetAttribute("Player")
                           or plot:GetAttribute("OwnerId")
                if owner == player.Name
                or owner == tostring(player.UserId)
                or owner == player.UserId then
                    return plot
                end
            end
        end
    end
    -- Fallback: plot mais próximo do player
    local char = player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local plotsRoot = WS:FindFirstChild("Plots")
        if plotsRoot then
            local nearest, nearestDist = nil, math.huge
            for _, plot in ipairs(plotsRoot:GetChildren()) do
                local plotPart = plot:FindFirstChildWhichIsA("BasePart", true)
                if plotPart then
                    local dist = (hrp.Position - plotPart.Position).Magnitude
                    if dist < nearestDist then
                        nearestDist = dist
                        nearest = plot
                    end
                end
            end
            if nearest then return nearest end
        end
    end
    return nil
end

local function getPlantUUIDs(plot)
    local uids = {}
    if not plot then return uids end
    for _, obj in ipairs(plot:GetDescendants()) do
        local uid = obj:GetAttribute("UUID")
                 or obj:GetAttribute("Id")
                 or obj:GetAttribute("ID")
                 or obj:GetAttribute("PlantId")
                 or obj:GetAttribute("FruitId")
        if uid then
            local stage = obj:GetAttribute("Stage")
                       or obj:GetAttribute("GrowthStage")
                       or obj:GetAttribute("Growth")
                       or 0
            table.insert(uids, { UID=tostring(uid), Object=obj, Stage=tonumber(stage) or 0 })
        end
    end
    return uids
end

local function getReadyFruits(plot)
    local ready = {}
    for _, p in ipairs(getPlantUUIDs(plot)) do
        if p.Stage >= 5 then table.insert(ready, p) end
    end
    return ready
end

-- CollectFruit confirmado: ok=true no debug
-- Tenta múltiplos formatos de chamada
local function tryCollect(uid)
    -- Formato 1: sem args (mais simples)
    if R.Collect then
        local ok = fire(R.Collect)
        if ok then return true end
    end
    -- Formato 2: só UID
    if R.Collect and uid then
        local ok = fire(R.Collect, uid)
        if ok then return true end
    end
    return false
end

local function collectAllReady()
    -- Tenta collect global primeiro (sem precisar de plot/UID)
    if R.Collect then
        fire(R.Collect)
        task.wait(0.3)
    end
    -- Tenta também por plant individual se tiver plot
    local plot  = getMyPlot()
    local ready = getReadyFruits(plot)
    for _, p in ipairs(ready) do
        fire(R.Collect, p.UID)
        task.wait(0.15)
    end
    return #ready
end

-- ============================================================
-- FLUENT WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Dig & Grow",
    SubTitle    = "v1.5 | by Danonin",
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
    -- Tenta por até 15 segundos
    for _ = 1, 30 do
        task.wait(0.5)
        -- Busca no PlayerGui primeiro
        for _, sg in ipairs(pg:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Name ~= "DnGMinGui" then
                -- Verifica se tem Frame filho com UICorner (estrutura do Fluent)
                for _, ch in ipairs(sg:GetChildren()) do
                    if ch:IsA("Frame") and ch:FindFirstChildOfClass("UICorner") then
                        fluentSG = sg
                        break
                    end
                end
            end
            if fluentSG then break end
        end
        -- Fallback: CoreGui (apenas ScreenGuis que não sejam do Roblox)
        if not fluentSG then
            for _, sg in ipairs(game:GetService("CoreGui"):GetChildren()) do
                if sg:IsA("ScreenGui")
                and sg.Name ~= "RobloxGui"
                and sg.Name ~= "DnGMinGui" then
                    fluentSG = sg
                    break
                end
            end
        end
        if fluentSG then
            warn("[DnG] Fluent GUI encontrado: " .. fluentSG.Name)
            break
        end
    end
    if not fluentSG then
        warn("[DnG] Fluent GUI nao encontrado — minimize pode nao funcionar")
    end
end)

local function doMin()
    winVis = not winVis
    if fluentSG then
        pcall(function() fluentSG.Enabled = winVis end)
    end
    minFrame.BackgroundColor3 = winVis
        and Color3.fromRGB(20, 140, 60) or Color3.fromRGB(140, 30, 30)
    minLbl.Text = winVis and "D&G" or ">"
end

local drag, moved, dStart, sPos = false, false, nil, nil

minHit.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        drag   = true
        moved  = false
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

-- MouseButton1Click consome o evento e impede de passar pro jogo
minHit.MouseButton1Click:Connect(function()
    if moved then return end  -- foi drag, não click
    doMin()
end)

UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        drag  = false
        moved = false
    end
end)

-- ============================================================
-- TABS
-- ============================================================
local Tabs = {
    Farm     = Window:AddTab({ Title = "Farm",     Icon = "sprout"        }),
    Garden   = Window:AddTab({ Title = "Garden",   Icon = "flower-2"      }),
    Shop     = Window:AddTab({ Title = "Shop",     Icon = "shopping-cart" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings"      }),
    Info     = Window:AddTab({ Title = "Info",     Icon = "info"          }),
}
local Options = Fluent.Options

-- ============================================================
-- TAB: FARM
-- ============================================================
Tabs.Farm:AddSection("Auto Collect")

local function collectAllReady()
    -- Tenta collect global primeiro (sem precisar de plot/UID)
    if R.Collect then
        fire(R.Collect)
        task.wait(0.3)
    end
    -- Tenta também por plant individual se tiver plot
    local plot  = getMyPlot()
    local ready = getReadyFruits(plot)
    for _, p in ipairs(ready) do
        fire(R.Collect, p.UID)
        task.wait(0.15)
    end
    return #ready
end

Tabs.Farm:AddToggle("AutoCollect", { Title = "Auto Collect Fruits", Default = false })
Options.AutoCollect:OnChanged(function(v)
    Safety:Toggle("AutoCollect", v, 3, function() collectAllReady() end)
end)

Tabs.Farm:AddButton({
    Title    = "Collect Now",
    Callback = function()
        if not R.Collect then
            Fluent:Notify({ Title="Erro", Content="Signal Collect nao encontrado. Veja Debug.", Duration=4 })
            return
        end
        local n = collectAllReady()
        Fluent:Notify({ Title="Collect", Content=n.." fruta(s) coletada(s)", Duration=3 })
    end,
})

Tabs.Farm:AddSection("Auto Mutation")

local mutStage = "5"
Tabs.Farm:AddDropdown("MutStage", {
    Title   = "Mutation Stage",
    Values  = { "1","2","3","4","5","6","7","8","9","10" },
    Default = "5",
})
Options.MutStage:OnChanged(function(v) mutStage = v end)

local function doSell()
    -- Tenta múltiplos formatos
    if R.Sell then
        fire(R.Sell)           -- sem args
        task.wait(0.1)
        fire(R.Sell, "Sell")   -- com string
        task.wait(0.1)
        fire(R.Sell, true)     -- com bool
    end
end

local function mutateAll()
    local count = 0
    -- Tenta mutate global primeiro
    if R.Mutate then
        fire(R.Mutate)
        task.wait(0.2)
    end
    -- Tenta por planta individual
    local plot   = getMyPlot()
    local plants = getPlantUUIDs(plot)
    for _, p in ipairs(plants) do
        fire(R.Mutate, p.UID, tonumber(mutStage) or 5)
        count += 1
        task.wait(0.15)
    end
    return count
end

Tabs.Farm:AddToggle("AutoMutate", { Title = "Auto Mutate Plants", Default = false })
Options.AutoMutate:OnChanged(function(v)
    Safety:Toggle("AutoMutate", v, 5, function() mutateAll() end)
end)

Tabs.Farm:AddButton({
    Title    = "Mutate All Now",
    Callback = function()
        if not R.Mutate then
            Fluent:Notify({ Title="Erro", Content="Signal Mutate nao encontrado. Veja Debug.", Duration=4 })
            return
        end
        local n = mutateAll()
        Fluent:Notify({ Title="Mutation", Content=n.." planta(s)", Duration=3 })
    end,
})

Tabs.Farm:AddSection("Auto Full Farm")

Tabs.Farm:AddToggle("AutoFullFarm", { Title = "Auto Full Farm (Collect+Sell)", Default = false })
Options.AutoFullFarm:OnChanged(function(v)
    Safety:Toggle("AutoFullFarm", v, 5, function()
        collectAllReady()
        task.wait(0.5)
        doSell()
    end)
end)

-- ============================================================
-- TAB: GARDEN
-- ============================================================
Tabs.Garden:AddSection("Auto Dig")

Tabs.Garden:AddToggle("AutoDig", { Title = "Auto Dig Plot", Default = false })
Options.AutoDig:OnChanged(function(v)
    Safety:Toggle("AutoDig", v, 0.5, function()
        local plot  = getMyPlot()
        if not plot then return end
        local floor = plot:FindFirstChild("Floor") or plot:FindFirstChild("Ground")
        if not floor then return end
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local pos  = hrp and hrp.Position or Vector3.new(0,0,0)
        fire(R.Tool, { ["Target"]=floor, ["Position"]=pos })
    end)
end)

Tabs.Garden:AddButton({
    Title    = "Dig Once",
    Callback = function()
        local plot = getMyPlot()
        if not plot then Fluent:Notify({ Title="Garden", Content="Plot nao encontrado!", Duration=3 }) return end
        local floor = plot:FindFirstChild("Floor") or plot:FindFirstChild("Ground")
        if not floor then Fluent:Notify({ Title="Garden", Content="Floor nao encontrado!", Duration=3 }) return end
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        fire(R.Tool, { ["Target"]=floor, ["Position"]=hrp and hrp.Position or Vector3.new(0,0,0) })
        Fluent:Notify({ Title="Garden", Content="Dig enviado", Duration=2 })
    end,
})

Tabs.Garden:AddSection("Plot Info")

local plotPara = Tabs.Garden:AddParagraph({ Title="Plot", Content="Clique em Scan" })

Tabs.Garden:AddButton({
    Title    = "Scan Plot",
    Callback = function()
        local plot = getMyPlot()
        if not plot then plotPara:SetDesc("Plot nao encontrado") return end
        local plants = getPlantUUIDs(plot)
        local ready  = getReadyFruits(plot)
        plotPara:SetDesc(
            "Plot: "..plot.Name..
            "\nPlantas detectadas: "..#plants..
            "\nProntas (Stage>=5): "..#ready
        )
        Fluent:Notify({ Title="Plot", Content=#plants.." planta(s), "..#ready.." pronta(s)", Duration=3 })
    end,
})

-- ============================================================
-- TAB: SHOP
-- ============================================================
Tabs.Shop:AddSection("Sell")

Tabs.Shop:AddButton({
    Title    = "Sell All",
    Callback = function()
        doSell()
        Fluent:Notify({ Title="Shop", Content="Sell enviado", Duration=2 })
    end,
})

Tabs.Shop:AddToggle("AutoSell", { Title = "Auto Sell", Default = false })
Options.AutoSell:OnChanged(function(v)
    Safety:Toggle("AutoSell", v, 10, function() doSell() end)
end)

Tabs.Shop:AddSection("Shovels")

local SHOVELS = { "Gold","Wood","Stone","Diamond","Emerald","Obsidian" }
Tabs.Shop:AddDropdown("ShovelType", { Title="Shovel Type", Values=SHOVELS, Default="Gold" })

Tabs.Shop:AddButton({
    Title    = "Buy Shovel",
    Callback = function()
        local shovel = Options.ShovelType.Value or "Gold"
        fire(R.Shovel, shovel)
        Fluent:Notify({ Title="Shop", Content="Compra: "..shovel, Duration=2 })
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
Tabs.Info:AddSection("Dig & Grow v1.5")
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
    Content = "RightControl — Toggle GUI\nBotao D&G — Toggle/Arrastar",
})

-- ============================================================
-- INIT
-- ============================================================
SaveManager:LoadAutoloadConfig()
Window:SelectTab(Tabs.Farm)
Fluent:Notify({
    Title   = "Dig & Grow v1.5",
    Content = "Script carregado!",
    Duration = 4,
})
print("DIG & GROW FULLY LOADED")
