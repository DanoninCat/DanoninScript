-- ============================================================
--  DIG & GROW | v1.2 | by Danonin
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
        WS,
    }
    for _, root in ipairs(roots) do
        if not root then continue end
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
    -- Fallback: qualquer plot com Floor
    local firstRoot = WS:FindFirstChild("Plots") or WS
    for _, plot in ipairs(firstRoot:GetChildren()) do
        if plot:FindFirstChild("Floor") or plot:FindFirstChild("Ground") then
            return plot
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

-- ============================================================
-- FLUENT WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Dig & Grow",
    SubTitle    = "v1.2 | by Danonin",
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
    Farm     = Window:AddTab({ Title = "Farm",     Icon = "sprout"        }),
    Garden   = Window:AddTab({ Title = "Garden",   Icon = "flower-2"      }),
    Shop     = Window:AddTab({ Title = "Shop",     Icon = "shopping-cart" }),
    Debug    = Window:AddTab({ Title = "Debug",    Icon = "terminal"      }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings"      }),
    Info     = Window:AddTab({ Title = "Info",     Icon = "info"          }),
}
local Options = Fluent.Options

-- ============================================================
-- TAB: FARM
-- ============================================================
Tabs.Farm:AddSection("Auto Collect")

local function collectAllReady()
    local plot  = getMyPlot()
    local ready = getReadyFruits(plot)
    local count = 0
    for _, p in ipairs(ready) do
        -- Tenta com stage como string e como número
        local ok = fire(R.Collect, p.UID, "5")
        if not ok then fire(R.Collect, p.UID, 5) end
        count += 1
        task.wait(0.15)
    end
    return count
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

local function mutateAll()
    local plot   = getMyPlot()
    local plants = getPlantUUIDs(plot)
    local count  = 0
    for _, p in ipairs(plants) do
        fire(R.Mutate, p.UID, mutStage)
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
        fire(R.Sell, "Sell")
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
        fire(R.Sell, "Sell")
        Fluent:Notify({ Title="Shop", Content="Sell enviado", Duration=2 })
    end,
})

Tabs.Shop:AddToggle("AutoSell", { Title = "Auto Sell", Default = false })
Options.AutoSell:OnChanged(function(v)
    Safety:Toggle("AutoSell", v, 10, function() fire(R.Sell, "Sell") end)
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
-- TAB: DEBUG — scanner de signals reais do jogo
-- ============================================================
Tabs.Debug:AddSection("Signals Encontrados")

local signalListPara = Tabs.Debug:AddParagraph({
    Title   = "Status",
    Content = "Clique em Escanear para ver os signals reais.",
})

Tabs.Debug:AddButton({
    Title    = "Escanear Signals (Output)",
    Callback = function()
        scanSignals()
        local lines = {}
        -- Mostra os principais detectados
        for k, v in pairs(R) do
            table.insert(lines, k..": "..(v and v.Name or "NAO ENCONTRADO"))
        end
        signalListPara:SetDesc(table.concat(lines, "\n"))
        -- Lista todos no output
        warn("=== TODOS OS SIGNALS ===")
        if Signals then
            for _, child in ipairs(Signals:GetDescendants()) do
                if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                    warn("  " .. child.Name .. " [" .. child.ClassName .. "]")
                end
            end
        end
        -- RS inteiro
        for _, child in ipairs(RS:GetDescendants()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                warn("  RS."..child.Name.." [" .. child.ClassName .. "]")
            end
        end
        warn("=== FIM ===")
        Fluent:Notify({ Title="Debug", Content="Ver output do executor.", Duration=3 })
    end,
})

Tabs.Debug:AddSection("Sniffer de Atividade")

local sniffConns = {}
local sniffActive = false
local sniffPara = Tabs.Debug:AddParagraph({ Title="Ultimo evento", Content="Inativo" })

Tabs.Debug:AddToggle("SniffToggle", { Title = "Sniffer (OnClientEvent)", Default = false })
Options.SniffToggle:OnChanged(function(v)
    sniffActive = v
    if v then
        -- Conecta em todos os signals
        if Signals then
            for _, child in ipairs(Signals:GetDescendants()) do
                if child:IsA("RemoteEvent") then
                    local name = child.Name
                    local c = child.OnClientEvent:Connect(function(...)
                        local args = {...}
                        local parts = {}
                        for _, a in ipairs(args) do
                            local t = type(a)
                            if t == "string" or t == "number" or t == "boolean" then
                                table.insert(parts, tostring(a))
                            else
                                table.insert(parts, "["..t.."]")
                            end
                        end
                        local line = name..": "..table.concat(parts, ", ")
                        warn("[DnG Sniff] "..line)
                        sniffPara:SetDesc(line)
                    end)
                    table.insert(sniffConns, c)
                end
            end
        end
        Fluent:Notify({ Title="Sniffer", Content="Ativo. Execute acoes no jogo.", Duration=3 })
    else
        for _, c in ipairs(sniffConns) do pcall(function() c:Disconnect() end) end
        sniffConns = {}
        sniffPara:SetDesc("Desativado")
    end
end)

Tabs.Debug:AddSection("Testar Signal Manual")

Tabs.Debug:AddInput("TestSignalName", {
    Title       = "Nome do Signal",
    Placeholder = "ex: CollectFruit",
    Numeric     = false,
})

Tabs.Debug:AddInput("TestSignalArg", {
    Title       = "Argumento (opcional)",
    Placeholder = "ex: Sell",
    Numeric     = false,
})

Tabs.Debug:AddButton({
    Title    = "Testar Signal",
    Callback = function()
        local name = Options.TestSignalName.Value or ""
        local arg  = Options.TestSignalArg.Value or ""
        if name == "" then
            Fluent:Notify({ Title="Debug", Content="Digite o nome do signal.", Duration=2 })
            return
        end
        local sig = Signals and Signals:FindFirstChild(name)
        if not sig then
            -- Busca no RS inteiro
            for _, child in ipairs(RS:GetDescendants()) do
                if child.Name == name then sig = child break end
            end
        end
        if not sig then
            Fluent:Notify({ Title="Debug", Content="Signal '"..name.."' nao encontrado.", Duration=3 })
            return
        end
        local ok, err
        if arg ~= "" then
            if sig:IsA("RemoteFunction") then
                ok, err = pcall(function() return sig:InvokeServer(arg) end)
            else
                ok, err = pcall(function() sig:FireServer(arg) end)
            end
        else
            if sig:IsA("RemoteFunction") then
                ok, err = pcall(function() return sig:InvokeServer() end)
            else
                ok, err = pcall(function() sig:FireServer() end)
            end
        end
        warn("[DnG Test] "..name.." → ok="..tostring(ok).." err="..tostring(err))
        Fluent:Notify({ Title="Teste", Content=name..": "..(ok and "OK" or tostring(err)), Duration=4 })
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
Tabs.Info:AddSection("Dig & Grow v1.2")
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
    Title   = "Dig & Grow v1.2",
    Content = "Script carregado!",
    Duration = 4,
})
