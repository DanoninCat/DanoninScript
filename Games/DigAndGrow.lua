-- ============================================================
--  DIG & GROW | v2.2 | by Danonin
-- ============================================================

local Players   = game:GetService("Players")
local RS        = game:GetService("ReplicatedStorage")
local WS        = game:GetService("Workspace")
local UIS       = game:GetService("UserInputService")
local RunSvc    = game:GetService("RunService")
local player    = Players.LocalPlayer

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
    if not ok1b then warn("[DnG] Fluent falhou") return end
end

local ok2, SaveManager = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua", true))()
end)
if not ok2 then warn("[DnG] SaveManager falhou") return end

local ok3, InterfaceManager = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua", true))()
end)
if not ok3 then warn("[DnG] InterfaceManager falhou") return end

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
    Collect = findAny({"CollectFruit","Collect","HarvestFruit","Harvest"}),
    Mutate  = findAny({"MutationReceptor","Mutate","Mutation","ApplyMutation"}),
    Sell    = findAny({"Shop","Sell","SellAll","Market","Store"}),
    Shovel  = findAny({"ShovelBuy","BuyShovel","Shovel","Purchase"}),
}

task.spawn(function()
    task.wait(2)
    warn("=== DIG & GROW v2.1 — Remotes ===")
    for k, v in pairs(R) do
        warn(k..": "..(v and v.Name.." ["..v.ClassName.."]" or "NAO ENCONTRADO"))
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
            if self._active[key] then
                local ok, err = pcall(fn)
                if not ok then warn("[Safety:"..key.."] "..tostring(err)) end
            end
        end
        self._threads[key] = nil
    end)
    self._threads[key] = t
end

function Safety:Toggle(key, enabled, interval, fn)
    if enabled then self:Loop(key, interval, fn) else self:Kill(key) end
end

-- ============================================================
-- PLOT
-- ============================================================
local function getMyPlot()
    local roots = {
        WS:FindFirstChild("Plots"),
        WS:FindFirstChild("Map") and WS.Map:FindFirstChild("Plots"),
        WS:FindFirstChild("World") and WS.World:FindFirstChild("Plots"),
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
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        local plotsRoot = WS:FindFirstChild("Plots")
        if plotsRoot then
            local nearest, nearestDist = nil, math.huge
            for _, plot in ipairs(plotsRoot:GetChildren()) do
                local part = plot:FindFirstChildWhichIsA("BasePart", true)
                if part then
                    local dist = (hrp.Position - part.Position).Magnitude
                    if dist < nearestDist then nearestDist = dist nearest = plot end
                end
            end
            return nearest
        end
    end
    return nil
end

-- ============================================================
-- PLANTAS — filtra SOMENTE Models com UUID e atributo coletável
-- ============================================================
local HARVEST_ATTRS = { "Harvestable", "CanCollect", "Ready", "IsReady", "Collectable" }

local function isHarvestable(obj)
    for _, attr in ipairs(HARVEST_ATTRS) do
        local v = obj:GetAttribute(attr)
        if v == true or v == 1 or v == "true" then return true end
    end
    return false
end

local function getPlants(plot)
    local plants = {}
    if not plot then return plants end

    for _, obj in ipairs(plot:GetDescendants()) do
        if not obj:IsA("Model") then continue end

        local uid = obj:GetAttribute("UUID")
                 or obj:GetAttribute("Id")
                 or obj:GetAttribute("ID")
                 or obj:GetAttribute("PlantId")
                 or obj:GetAttribute("FruitId")
        if not uid then continue end

        local uidStr = tostring(uid)
        if uidStr == "" or uidStr == "0" or uidStr == "nil" then continue end

        local stage = obj:GetAttribute("Stage")
                   or obj:GetAttribute("GrowthStage")
                   or obj:GetAttribute("Growth")
                   or 0

        -- Guarda referência real do Model e do BasePart principal
        local mainPart = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")

        table.insert(plants, {
            UUID        = uidStr,
            Stage       = tonumber(stage) or 0,
            Harvestable = isHarvestable(obj),
            Object      = obj,   -- Model completo
            Model       = obj,   -- alias explícito
            Part        = mainPart, -- BasePart principal
        })
    end
    return plants
end

local function getHarvestablePlants(plot)
    local all     = getPlants(plot)
    local ready   = {}
    local notReady = {}
    for _, p in ipairs(all) do
        if p.Harvestable then
            table.insert(ready, p)
        else
            table.insert(notReady, p)
        end
    end
    -- Se nenhum tem atributo Harvestable, retorna todos (jogo pode não usar esse atributo)
    if #ready == 0 then return notReady end
    return ready
end

-- ============================================================
-- COLLECT PLOT — tenta múltiplas assinaturas do CollectFruit
-- O hook captura UUID+"1" mas o servidor pode exigir Model/Part
-- ============================================================
local function doCollect()
    if not R.Collect then
        warn("[COLLECT] Remote CollectFruit nao encontrado!")
        return 0
    end

    local plot = getMyPlot()
    if not plot then
        warn("[COLLECT] Plot nao encontrado")
        return 0
    end

    local plants = getHarvestablePlants(plot)
    warn("[COLLECT] Plot: "..plot.Name.." | Plantas: "..#plants)

    if #plants == 0 then
        warn("[COLLECT] Nenhuma planta encontrada")
        return 0
    end

    local count = 0
    for _, p in ipairs(plants) do
        print("[COLLECT ATTEMPT] UUID:", p.UUID, "| Model:", tostring(p.Model), "| Part:", tostring(p.Part))

        -- Tenta 5 assinaturas em ordem, para na primeira que não der erro
        local attempts = {
            -- 1. Só UUID + "1" (mais simples, confirmado pelo hook)
            function() R.Collect:FireServer(p.UUID, "1") end,
            -- 2. Model + UUID + "1" (jogo pode exigir referência da instância)
            function() R.Collect:FireServer(p.Model, p.UUID, "1") end,
            -- 3. Part + UUID
            function() if p.Part then R.Collect:FireServer(p.Part, p.UUID) end end,
            -- 4. Só o Model
            function() R.Collect:FireServer(p.Model) end,
            -- 5. Só o Part
            function() if p.Part then R.Collect:FireServer(p.Part) end end,
        }

        for i, attempt in ipairs(attempts) do
            local ok, err = pcall(attempt)
            if ok then
                print("[COLLECT] Tentativa", i, "OK — UUID:", p.UUID)
                break
            else
                print("[COLLECT] Tentativa", i, "falhou:", tostring(err))
            end
            task.wait(0.05)
        end

        count += 1
        task.wait(0.25)
    end

    warn("[COLLECT] Enviado para "..count.." planta(s)")
    return count
end

-- ============================================================
-- COLLECT CHÃO — frutas cavadas (ProximityPrompt / ClickDetector)
-- ============================================================
local GROUND_NAMES = {
    "fruit", "blueberry", "strawberry", "apple", "mango",
    "cherry", "melon", "pickup", "drop", "seed",
}

local function nameMatchesGround(name)
    local lower = name:lower()
    for _, keyword in ipairs(GROUND_NAMES) do
        if lower:find(keyword) then return true end
    end
    return false
end

local function collectGroundFruits()
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return 0 end

    local collected = 0
    local RANGE = 20  -- raio de coleta em studs

    -- Varre Workspace em busca de objetos coletáveis próximos
    for _, obj in ipairs(WS:GetDescendants()) do
        -- Ignora objetos do próprio personagem
        if obj:IsDescendantOf(player.Character) then continue end

        local part = obj:IsA("BasePart") and obj
                  or (obj:IsA("Model") and obj:FindFirstChildWhichIsA("BasePart", true))
        if not part then continue end

        local dist = (hrp.Position - part.Position).Magnitude
        if dist > RANGE then continue end

        -- Tenta ProximityPrompt
        local pp = obj:FindFirstChildOfClass("ProximityPrompt")
                or (obj:IsA("Model") and obj:FindFirstChildOfClass("ProximityPrompt", true))
        if pp then
            -- Só ativa se o objeto tem nome de fruta/pickup OU tem atributo coletável
            local objHarvestable = isHarvestable(obj)
            local objNameMatch   = nameMatchesGround(obj.Name)
            if objHarvestable or objNameMatch then
                pcall(function()
                    fireproximityprompt(pp)  -- função nativa de executores
                end)
                -- Fallback caso o executor não tenha fireproximityprompt
                pcall(function()
                    pp:InputHoldBegin()
                    task.wait(0.05)
                    pp:InputHoldEnd()
                end)
                collected += 1
                print("[GROUND] ProximityPrompt:", obj.Name, "dist:", math.floor(dist))
                task.wait(0.1)
                continue
            end
        end

        -- Tenta ClickDetector
        local cd = obj:FindFirstChildOfClass("ClickDetector")
               or (obj:IsA("Model") and obj:FindFirstChildOfClass("ClickDetector", true))
        if cd then
            local objHarvestable = isHarvestable(obj)
            local objNameMatch   = nameMatchesGround(obj.Name)
            if objHarvestable or objNameMatch then
                pcall(function()
                    fireclickdetector(cd)  -- função nativa de executores
                end)
                collected += 1
                print("[GROUND] ClickDetector:", obj.Name, "dist:", math.floor(dist))
                task.wait(0.1)
                continue
            end
        end

        -- Verifica se o próprio objeto tem atributo coletável e UUID (fruta no chão)
        if isHarvestable(obj) or nameMatchesGround(obj.Name) then
            local uid = obj:GetAttribute("UUID") or obj:GetAttribute("Id") or obj:GetAttribute("ID")
            if uid and R.Collect then
                print("[GROUND] Remote collect:", obj.Name, "UUID:", tostring(uid))
                pcall(function()
                    R.Collect:FireServer(tostring(uid), "1")
                end)
                collected += 1
                task.wait(0.1)
            end
        end
    end

    return collected
end

-- ============================================================
-- MUTATE — InvokeServer(UUID, string stage)
-- ============================================================
local function doMutate(stageNum)
    if not R.Mutate then return 0 end
    local plot     = getMyPlot()
    local plants   = getPlants(plot)
    local stageStr = tostring(stageNum)
    local count    = 0

    if #plants > 0 then
        for _, p in ipairs(plants) do
            pcall(function()
                if R.Mutate:IsA("RemoteFunction") then
                    R.Mutate:InvokeServer(p.UUID, stageStr)
                else
                    R.Mutate:FireServer(p.UUID, stageStr)
                end
            end)
            count += 1
            task.wait(0.2)
        end
    else
        pcall(function()
            if R.Mutate:IsA("RemoteFunction") then
                R.Mutate:InvokeServer(stageStr)
            else
                R.Mutate:FireServer(stageStr)
            end
        end)
    end
    return count
end

-- ============================================================
-- SELL — InvokeServer("Inventory") confirmado
-- ============================================================
local function doSell()
    if not R.Sell then return end
    pcall(function()
        if R.Sell:IsA("RemoteFunction") then
            R.Sell:InvokeServer("Inventory")
        else
            R.Sell:FireServer("Inventory")
        end
    end)
end

-- ============================================================
-- DIG
-- ============================================================
local function doDig()
    if not R.Tool then return end
    local plot  = getMyPlot()
    if not plot then return end
    local floor = plot:FindFirstChild("Floor") or plot:FindFirstChild("Ground")
    if not floor then return end
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    pcall(function()
        R.Tool:FireServer({ Target = floor, Position = hrp and hrp.Position or Vector3.zero })
    end)
end

-- ============================================================
-- FLUENT WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Dig & Grow",
    SubTitle    = "v2.2 | by Danonin",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(680, 460),
    Acrylic     = true,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

-- ============================================================
-- BOTÃO FLUTUANTE — v2.1
-- Fix definitivo mobile:
--   Active = true no Frame e no Button
--   MouseButton1Down vazio para consumir o clique
--   SEM Modal (não funciona mobile)
--   SEM SetModalEnabled (quebra clique)
-- ============================================================
local winVis = true
local pg     = player:WaitForChild("PlayerGui", 10)

local minSG = Instance.new("ScreenGui")
minSG.Name            = "DnGMinGui"
minSG.ResetOnSpawn    = false
minSG.DisplayOrder    = 9999
minSG.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
minSG.IgnoreGuiInset  = true
minSG.Parent          = pg

local minFrame = Instance.new("Frame", minSG)
minFrame.Size                   = UDim2.fromOffset(54, 54)
minFrame.Position               = UDim2.new(0, 8, 0.5, -27)
minFrame.BackgroundColor3       = Color3.fromRGB(20, 140, 60)
minFrame.BackgroundTransparency = 0.1
minFrame.ZIndex                 = 100
minFrame.Active                 = true  -- consome inputs
Instance.new("UICorner", minFrame).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", minFrame)
stroke.Color     = Color3.fromRGB(60, 220, 100)
stroke.Thickness = 2

local minLbl = Instance.new("TextLabel", minFrame)
minLbl.Size                   = UDim2.fromScale(1, 1)
minLbl.BackgroundTransparency = 1
minLbl.Text                   = "D&G"
minLbl.TextColor3             = Color3.new(1, 1, 1)
minLbl.Font                   = Enum.Font.GothamBold
minLbl.TextSize               = 13
minLbl.ZIndex                 = 101

local minHit = Instance.new("TextButton", minFrame)
minHit.Size                   = UDim2.fromScale(1, 1)
minHit.BackgroundTransparency = 1
minHit.Text                   = ""
minHit.AutoButtonColor        = false
minHit.Active                 = true  -- consome inputs, bloqueia jogo atrás
minHit.ZIndex                 = 102

minHit.Active      = true
minHit.Selectable  = false

-- MouseButton1Down VAZIO — consome o press antes de chegar no jogo
minHit.MouseButton1Down:Connect(function() end)
-- InputBegan VAZIO — consome input touch/mouse antes de qualquer coisa atrás
minHit.InputBegan:Connect(function() end)

-- Busca GUI do Fluent
local fluentSG = nil
task.spawn(function()
    for _ = 1, 40 do
        task.wait(0.5)
        for _, sg in ipairs(pg:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Name ~= "DnGMinGui" then
                for _, ch in ipairs(sg:GetChildren()) do
                    if ch:IsA("Frame") and ch:FindFirstChildOfClass("UICorner") then
                        fluentSG = sg break
                    end
                end
            end
            if fluentSG then break end
        end
        if not fluentSG then
            for _, sg in ipairs(game:GetService("CoreGui"):GetChildren()) do
                if sg:IsA("ScreenGui") and sg.Name ~= "RobloxGui" and sg.Name ~= "DnGMinGui" then
                    fluentSG = sg break
                end
            end
        end
        if fluentSG then
            warn("[DnG] Fluent GUI: "..fluentSG.Name)
            break
        end
    end
end)

local PPS = game:GetService("ProximityPromptService")

local function setButtonState(open)
    if open then
        minFrame.BackgroundColor3 = Color3.fromRGB(20, 140, 60)
        stroke.Color              = Color3.fromRGB(60, 220, 100)
        minLbl.Text               = "D&G"
    else
        minFrame.BackgroundColor3 = Color3.fromRGB(140, 30, 30)
        stroke.Color              = Color3.fromRGB(220, 80, 80)
        minLbl.Text               = ">"
    end
end

local function doMin()
    winVis = not winVis
    if fluentSG then pcall(function() fluentSG.Enabled = winVis end) end
    -- Desativa ProximityPrompts quando UI está fechada para não interagir com NPCs
    pcall(function() PPS.Enabled = winVis end)
    setButtonState(winVis)
end

-- Drag
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
        if math.abs(dx) > 6 or math.abs(dy) > 6 then
            moved = true
            minFrame.Position = UDim2.new(
                sPos.X.Scale, sPos.X.Offset + dx,
                sPos.Y.Scale, sPos.Y.Offset + dy
            )
        end
    end
end)

minHit.MouseButton1Click:Connect(function()
    if moved then return end
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

Tabs.Farm:AddToggle("AutoCollect", { Title = "Auto Collect (Plot)", Default = false })
Options.AutoCollect:OnChanged(function(v)
    Safety:Toggle("AutoCollect", v, 3, function() doCollect() end)
end)

Tabs.Farm:AddToggle("AutoCollectGround", { Title = "Auto Collect (Chão)", Default = false })
Options.AutoCollectGround:OnChanged(function(v)
    Safety:Toggle("AutoCollectGround", v, 2, function() collectGroundFruits() end)
end)

Tabs.Farm:AddButton({
    Title    = "Collect Now (Plot)",
    Callback = function()
        local n = doCollect()
        Fluent:Notify({ Title="Collect", Content=n.." planta(s) coletada(s)", Duration=2 })
    end,
})

Tabs.Farm:AddButton({
    Title    = "Collect Now (Chão)",
    Callback = function()
        local n = collectGroundFruits()
        Fluent:Notify({ Title="Collect Chão", Content=n.." objeto(s) coletado(s)", Duration=2 })
    end,
})

Tabs.Farm:AddSection("Auto Mutation")

local mutStage = 1
Tabs.Farm:AddDropdown("MutStage", {
    Title   = "Mutation Stage",
    Values  = { "1","2","3","4","5","6","7","8","9","10" },
    Default = "1",
})
Options.MutStage:OnChanged(function(v) mutStage = tonumber(v) or 1 end)

Tabs.Farm:AddToggle("AutoMutate", { Title = "Auto Mutate Plants", Default = false })
Options.AutoMutate:OnChanged(function(v)
    Safety:Toggle("AutoMutate", v, 5, function() doMutate(mutStage) end)
end)

Tabs.Farm:AddButton({
    Title    = "Mutate All Now",
    Callback = function()
        local n = doMutate(mutStage)
        Fluent:Notify({ Title="Mutation", Content=n.." planta(s)", Duration=3 })
    end,
})

Tabs.Farm:AddSection("Auto Full Farm")

-- Collect plot a cada 3s + chão a cada 2s + Sell a cada 15s
Tabs.Farm:AddToggle("AutoFullFarm", { Title = "Auto Full Farm (Collect + Sell)", Default = false })
Options.AutoFullFarm:OnChanged(function(v)
    Safety:Toggle("AFF_Plot",   v, 3,  function() doCollect()          end)
    Safety:Toggle("AFF_Ground", v, 2,  function() collectGroundFruits() end)
    Safety:Toggle("AFF_Sell",   v, 15, function() doSell()             end)
end)

-- ============================================================
-- TAB: GARDEN
-- ============================================================
Tabs.Garden:AddSection("Auto Dig")

Tabs.Garden:AddToggle("AutoDig", { Title = "Auto Dig Plot", Default = false })
Options.AutoDig:OnChanged(function(v)
    Safety:Toggle("AutoDig", v, 0.5, function() doDig() end)
end)

-- Auto Dig + Collect chão juntos
Tabs.Garden:AddToggle("AutoDigCollect", { Title = "Auto Dig + Collect Chão", Default = false })
Options.AutoDigCollect:OnChanged(function(v)
    Safety:Toggle("ADC_Dig",    v, 0.5, function() doDig()              end)
    Safety:Toggle("ADC_Ground", v, 2,   function() collectGroundFruits() end)
end)

-- Auto Dig + Sell
Tabs.Garden:AddToggle("AutoDigSell", { Title = "Auto Dig + Sell", Default = false })
Options.AutoDigSell:OnChanged(function(v)
    Safety:Toggle("ADS_Dig",  v, 0.5, function() doDig()   end)
    Safety:Toggle("ADS_Sell", v, 15,  function() doSell()  end)
end)

Tabs.Garden:AddButton({
    Title    = "Dig Once",
    Callback = function()
        if not R.Tool then
            Fluent:Notify({ Title="Garden", Content="Tool remote nao encontrado!", Duration=3 })
            return
        end
        doDig()
        Fluent:Notify({ Title="Garden", Content="Dig enviado!", Duration=2 })
    end,
})

Tabs.Garden:AddSection("Plot Info")
local plotPara = Tabs.Garden:AddParagraph({ Title = "Plot", Content = "Clique em Scan" })

Tabs.Garden:AddButton({
    Title    = "Scan Plot",
    Callback = function()
        local plot = getMyPlot()
        if not plot then
            plotPara:SetDesc("Plot nao encontrado")
            return
        end
        local all     = getPlants(plot)
        local ready   = {}
        for _, p in ipairs(all) do
            if p.Harvestable then table.insert(ready, p) end
        end
        plotPara:SetDesc(
            "Plot: "..plot.Name..
            "\nTotal plantas: "..#all..
            "\nProntas: "..#ready
        )
        Fluent:Notify({ Title="Plot", Content=#all.." planta(s), "..#ready.." pronta(s)", Duration=3 })
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
        Fluent:Notify({ Title="Shop", Content="Sell enviado!", Duration=2 })
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
        if R.Shovel then
            pcall(function()
                if R.Shovel:IsA("RemoteFunction") then
                    R.Shovel:InvokeServer(shovel)
                else
                    R.Shovel:FireServer(shovel)
                end
            end)
        end
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
Tabs.Info:AddSection("Danonin Hub")
Tabs.Info:AddParagraph({ Title = "Dev",     Content = "Danonin" })
Tabs.Info:AddParagraph({ Title = "Discord", Content = "discord.gg/qDeZ9sEdGY" })
Tabs.Info:AddButton({
    Title    = "Copiar Discord",
    Callback = function()
        setclipboard("https://discord.gg/qDeZ9sEdGY")
        Fluent:Notify({ Title="Copiado!", Content="discord.gg/qDeZ9sEdGY", Duration=3 })
    end,
})
Tabs.Info:AddParagraph({
    Title   = "Keybinds",
    Content = "RightControl — Abrir/Fechar GUI\nBotão D&G — Toggle / Arrastar",
})

-- ============================================================
-- INIT
-- ============================================================
SaveManager:LoadAutoloadConfig()
Window:SelectTab(Tabs.Farm)
Fluent:Notify({
    Title    = "Dig & Grow v2.2",
    Content  = "Carregado!",
    Duration = 4,
})
print("DIG & GROW v2.2 FULLY LOADED")
