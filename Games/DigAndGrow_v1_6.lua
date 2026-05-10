-- ============================================================
--  DIG & GROW | v1.6 | by Danonin
--  Fix: CollectFruit(Instance, number), MutationReceptor(Instance, number)
--  Fix: Shop:InvokeServer("Inventory") para Sell
--  Fix: botão minimizar bloqueando input via UserInputService:SetModalEnabled
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
-- REMOTES
-- ============================================================
local Signals = RS:FindFirstChild("Signals")

local function findAny(names)
    if Signals then
        for _, name in ipairs(names) do
            local r = Signals:FindFirstChild(name)
            if r then return r end
            for _, child in ipairs(Signals:GetDescendants()) do
                if child.Name:lower() == name:lower()
                and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
                    return child
                end
            end
        end
    end
    for _, name in ipairs(names) do
        for _, child in ipairs(RS:GetDescendants()) do
            if child.Name:lower() == name:lower()
            and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
                return child
            end
        end
    end
    return nil
end

local R = {
    Tool    = findAny({"ToolSignal","Tool","Dig","UseTool","ToolUse"}),
    Collect = findAny({"CollectFruit","Collect","HarvestFruit","Harvest","PickFruit","Pick"}),
    Mutate  = findAny({"MutationReceptor","Mutate","Mutation","ApplyMutation","MutateSignal"}),
    Sell    = findAny({"Shop","Sell","SellAll","Market","Store"}),
    Shovel  = findAny({"ShovelBuy","BuyShovel","Shovel","Purchase"}),
    Plant   = findAny({"PlantSeed","Plant","Seed","PlantSignal"}),
    Water   = findAny({"Water","WaterPlant","Irrigate"}),
}

task.spawn(function()
    task.wait(2)
    warn("=== DIG & GROW v1.6 — Remotes ===")
    for k, v in pairs(R) do
        warn(k .. ": " .. (v and (v.Name .. " [" .. v.ClassName .. "]") or "NAO ENCONTRADO"))
    end
end)

-- ============================================================
-- FIRE HELPERS
-- ============================================================
-- FireServer genérico
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

-- SELL: debug mostrou Shop:InvokeServer([1]Inventory)
local function doSell()
    if not R.Sell then return end
    if R.Sell:IsA("RemoteFunction") then
        pcall(function() R.Sell:InvokeServer("Inventory") end)
    else
        pcall(function() R.Sell:FireServer("Inventory") end)
    end
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
-- HELPERS — PLOT
-- ============================================================
local function getMyPlot()
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
    -- Fallback: plot mais próximo
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

-- ============================================================
-- HELPERS — PLANTAS
-- Debug mostrou: CollectFruit:FireServer([1]Instance_UUID, [2]number)
-- O primeiro argumento é o OBJETO Instance, não uma string UUID.
-- MutationReceptor igual: (Instance, number)
-- ============================================================
local function getPlants(plot)
    -- Retorna lista de { Object=Instance, Stage=number }
    -- O "Object" é o próprio objeto enviado ao remote (Instance)
    local plants = {}
    if not plot then return plants end
    for _, obj in ipairs(plot:GetDescendants()) do
        -- Planta válida: tem atributo de stage/growth
        local hasUUID = obj:GetAttribute("UUID")
                     or obj:GetAttribute("Id")
                     or obj:GetAttribute("ID")
                     or obj:GetAttribute("PlantId")
                     or obj:GetAttribute("FruitId")
        local stage   = obj:GetAttribute("Stage")
                     or obj:GetAttribute("GrowthStage")
                     or obj:GetAttribute("Growth")
                     or 0
        if hasUUID then
            table.insert(plants, {
                Object = obj,
                Stage  = tonumber(stage) or 0,
            })
        end
    end
    return plants
end

local function getReadyFruits(plot)
    local ready = {}
    for _, p in ipairs(getPlants(plot)) do
        if p.Stage >= 5 then table.insert(ready, p) end
    end
    return ready
end

-- COLLECT: passa o Instance e um número (visto no debug como [2]2, [2]4, etc.)
-- Testamos com 1 pois é o valor mais comum para "coletar tudo"
local function collectAllReady()
    local plot  = getMyPlot()
    local ready = getReadyFruits(plot)
    local count = 0

    if #ready > 0 then
        -- Formato confirmado: CollectFruit:FireServer(Instance, number)
        for _, p in ipairs(ready) do
            pcall(function()
                R.Collect:FireServer(p.Object, 1)
            end)
            count += 1
            task.wait(0.15)
        end
    else
        -- Fallback sem plot: tenta sem args ou só com número
        if R.Collect then
            pcall(function() R.Collect:FireServer() end)
        end
    end
    return count
end

-- MUTATE: MutationReceptor:InvokeServer(Instance, number)
-- número = stage da mutação
local function mutateAll(stageNum)
    local count = 0
    local plot   = getMyPlot()
    local plants = getPlants(plot)

    if #plants > 0 then
        for _, p in ipairs(plants) do
            pcall(function()
                if R.Mutate:IsA("RemoteFunction") then
                    R.Mutate:InvokeServer(p.Object, stageNum)
                else
                    R.Mutate:FireServer(p.Object, stageNum)
                end
            end)
            count += 1
            task.wait(0.2)
        end
    else
        -- Fallback sem plot
        if R.Mutate then
            pcall(function()
                if R.Mutate:IsA("RemoteFunction") then
                    R.Mutate:InvokeServer(stageNum)
                else
                    R.Mutate:FireServer(stageNum)
                end
            end)
        end
    end
    return count
end

-- ============================================================
-- FLUENT WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Dig & Grow",
    SubTitle    = "v1.6 | by Danonin",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(680, 460),
    Acrylic     = true,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

-- ============================================================
-- BOTÃO FLUTUANTE — v1.6
-- Fix: SetModalEnabled bloqueia input do jogo durante drag/minimizar
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
minLbl.Size                 = UDim2.fromScale(1, 1)
minLbl.BackgroundTransparency = 1
minLbl.Text                 = "D&G"
minLbl.TextColor3           = Color3.new(1, 1, 1)
minLbl.Font                 = Enum.Font.GothamBold
minLbl.TextSize             = 13
minLbl.ZIndex               = 51

-- TextButton consome o evento via MouseButton1Click — não passa pro jogo
local minHit = Instance.new("TextButton", minFrame)
minHit.Size                 = UDim2.fromScale(1, 1)
minHit.BackgroundTransparency = 1
minHit.Text                 = ""
minHit.ZIndex               = 52
-- CRÍTICO: Modal = true bloqueia qualquer clique de passar para o jogo
-- enquanto o botão está sendo clicado/arrastado
minHit.Modal                = false  -- não ativar permanentemente

-- Encontra ScreenGui do Fluent
local fluentSG = nil
task.spawn(function()
    for _ = 1, 30 do
        task.wait(0.5)
        for _, sg in ipairs(pg:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Name ~= "DnGMinGui" then
                for _, ch in ipairs(sg:GetChildren()) do
                    if ch:IsA("Frame") and ch:FindFirstChildOfClass("UICorner") then
                        fluentSG = sg
                        break
                    end
                end
            end
            if fluentSG then break end
        end
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
            warn("[DnG] Fluent GUI: " .. fluentSG.Name)
            break
        end
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

-- Drag logic com bloqueio de input via SetModalEnabled
local drag, moved, dStart, sPos = false, false, nil, nil

minHit.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        drag   = true
        moved  = false
        dStart = Vector2.new(i.Position.X, i.Position.Y)
        sPos   = minFrame.Position
        -- Bloqueia input do jogo durante interação com o botão
        UIS:SetModalEnabled(true)
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

-- MouseButton1Click: só dispara em click real (não drag)
minHit.MouseButton1Click:Connect(function()
    if moved then
        -- Foi drag — só libera modal, não minimiza
        UIS:SetModalEnabled(false)
        drag  = false
        moved = false
        return
    end
    doMin()
    UIS:SetModalEnabled(false)
    drag  = false
    moved = false
end)

UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        -- Garante liberar modal caso MouseButton1Click não dispare
        if drag then
            UIS:SetModalEnabled(false)
        end
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

Tabs.Farm:AddToggle("AutoCollect", { Title = "Auto Collect Fruits", Default = false })
Options.AutoCollect:OnChanged(function(v)
    Safety:Toggle("AutoCollect", v, 3, function() collectAllReady() end)
end)

Tabs.Farm:AddButton({
    Title    = "Collect Now",
    Callback = function()
        if not R.Collect then
            Fluent:Notify({ Title="Erro", Content="Collect nao encontrado", Duration=4 })
            return
        end
        local n = collectAllReady()
        Fluent:Notify({ Title="Collect", Content=n.." fruta(s) coletada(s)", Duration=3 })
    end,
})

Tabs.Farm:AddSection("Auto Mutation")

local mutStage = 5
Tabs.Farm:AddDropdown("MutStage", {
    Title   = "Mutation Stage",
    Values  = { "1","2","3","4","5","6","7","8","9","10" },
    Default = "5",
})
Options.MutStage:OnChanged(function(v) mutStage = tonumber(v) or 5 end)

Tabs.Farm:AddToggle("AutoMutate", { Title = "Auto Mutate Plants", Default = false })
Options.AutoMutate:OnChanged(function(v)
    Safety:Toggle("AutoMutate", v, 5, function() mutateAll(mutStage) end)
end)

Tabs.Farm:AddButton({
    Title    = "Mutate All Now",
    Callback = function()
        if not R.Mutate then
            Fluent:Notify({ Title="Erro", Content="Mutate nao encontrado", Duration=4 })
            return
        end
        local n = mutateAll(mutStage)
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
        local plants = getPlants(plot)
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
Tabs.Info:AddSection("Dig & Grow v1.6")
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
Tabs.Info:AddParagraph({
    Title   = "v1.6 Fixes",
    Content = "- Collect: agora envia Instance + numero\n- Mutate: agora envia Instance + stage\n- Sell: agora envia 'Inventory'\n- Minimize: SetModalEnabled bloqueia loja",
})

-- ============================================================
-- INIT
-- ============================================================
SaveManager:LoadAutoloadConfig()
Window:SelectTab(Tabs.Farm)
Fluent:Notify({
    Title   = "Dig & Grow v1.6",
    Content = "Script carregado! Fixes: Collect, Mutate, Sell, Minimize",
    Duration = 5,
})
print("DIG & GROW v1.6 FULLY LOADED")
