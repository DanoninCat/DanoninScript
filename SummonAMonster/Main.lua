if game.PlaceId ~= 84554009750048 then return end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local GuiService = game:GetService("GuiService")
local TeleportService = game:GetService("TeleportService")
local LP = Players.LocalPlayer
local Env = (getgenv and getgenv()) or _G
local LOADER = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Loader/Loader.lua", true))()]]

if type(Env.__CE_SUMMON_CLEANUP) == "function" then pcall(Env.__CE_SUMMON_CLEANUP) end
Env.__CE_SUMMON_LAST_ERROR = nil
local fluentSource = Env["__CE_F_91A7"]
if type(fluentSource) ~= "string" or fluentSource == "" then
    Env.__CE_SUMMON_LAST_ERROR = "FluentPro source missing: execute through primary loader"
    return
end
local okUI, Fluent = pcall(function() return loadstring(fluentSource)() end)
if not okUI or not Fluent then
    Env.__CE_SUMMON_LAST_ERROR = tostring(Fluent)
    return
end

local S = {
    Running = true, AutoFarm = false, AutoAttack = false, FollowTarget = false,
    BossOnly = false, Selected = {}, FarmRange = 140, AttackDistance = 35,
    AttackInterval = 0.25, Target = nil, AutoCollect = false,
    CollectNormal = true, CollectRadiant = true, CollectShiny = true,
    AutoEquipCores = false, AutoEquipGear = false, AutoCraftBest = false,
    AutoDaily = false, AutoGroup = false, AutoHeal = false,
    AutoTower = false, AutoNative = false, AutoSell = false,
    SellDuplicates = false, SellRarity = 1, ConfirmSell = false,
    ESPMonsters = false, ESPCores = false, NotifyRare = true,
    AntiAFK = false, AutoRejoin = false, AutoExecute = false,
    MovePriority = "", AutoCollectDistance = 120, FarmAttacks = 0,
    LastFarmResult = "", LastRemoteError = "", LastClaim = 0,
    LastMonsterRefresh = 0, LastTargetKey = "", NextDaily = 0,
    NextTower = 0, NextCollection = 0, NextCraft = 0,
    LastPity = "", ReforgeZone = "eq", ReforgeIndex = 1,
    CraftRecipe = "", PortalArea = "", ConfigName = "CATEMPIRE_SummonAMonster.json",
}
local Links, Highlights, Toggles = {}, {}, {}
local MonsterOptions, MonsterDropdown, Status, WindowRef
local MonsterData = {}
pcall(function() MonsterData = require(RS:WaitForChild("DadosMonstros", 8)) end)

local function notify(message, duration)
    pcall(function()
        Fluent:Notify({Title = "CAT EMPIRE", Content = tostring(message), Duration = duration or 4})
    end)
end

local function remote(name, ...)
    local endpoint = RS:FindFirstChild(name)
    if not endpoint then
        S.LastRemoteError = name .. ": remote unavailable"
        return false
    end
    local args = table.pack(...)
    local ok, result = pcall(function()
        if endpoint:IsA("RemoteEvent") then
            endpoint:FireServer(table.unpack(args, 1, args.n))
            return true
        elseif endpoint:IsA("RemoteFunction") then
            return endpoint:InvokeServer(table.unpack(args, 1, args.n))
        else
            error("Unexpected remote class")
        end
    end)
    if not ok then S.LastRemoteError = name .. ": " .. tostring(result) end
    return ok, result
end

local function link(signal, callback)
    if signal then
        local c = signal:Connect(callback)
        Links[#Links + 1] = c
        return c
    end
end

local function setStatus(label, content)
    if not Status then return end
    pcall(function()
        Status:SetTitle(label)
        Status:SetDesc(content or "")
    end)
end

local function getRoot()
    local ch = LP.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local root = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hum or hum.Health <= 0 then return nil end
    return root, hum
end

local function modelPos(model)
    if not model then return nil end
    local part = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if part then return part.Position end
    local success, pivot = pcall(function() return model:GetPivot() end)
    if success then return pivot.Position end
    return nil
end

local function monsterType(model)
    return tostring(model:GetAttribute("TipoMonstro") or model.Name)
end

local function isBoss(model)
    local info = MonsterData[monsterType(model)]
    return model:GetAttribute("Chefe") == true or
        (type(info) == "table" and info.Chefe == true) or
        model:GetAttribute("Boss") == true
end

local function validMonster(model)
    if not model or not model.Parent or not model:IsA("Model") then return false end
    local h = model:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return false end
    local owner = model:GetAttribute("DonoId")
    if owner and tonumber(owner) ~= LP.UserId then return false end
    if model:GetAttribute("DueloBonecoId") ~= nil then return false end
    return modelPos(model) ~= nil
end

local function refreshMonsters(force)
    local folder = workspace:FindFirstChild("Monstros")
    local found = {}
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if validMonster(model) then found[monsterType(model)] = true end
        end
    end
    local values = {}
    for name in pairs(found) do values[#values + 1] = name end
    table.sort(values)
    local signature = table.concat(values, "|")
    if MonsterDropdown and (force or signature ~= S.LastTargetKey) then
        S.LastTargetKey = signature
        MonsterOptions = values
        local selected = {}
        for _, name in ipairs(values) do
            if S.Selected[name] then selected[name] = true end
        end
        pcall(function()
            MonsterDropdown:SetValues(values)
            MonsterDropdown:SetValue(selected)
        end)
    end
    S.LastMonsterRefresh = os.clock()
    return #values
end

local function chooseTarget()
    local folder = workspace:FindFirstChild("Monstros")
    local root = getRoot()
    if not folder or not root then return nil end
    local chosen, distance
    for _, monster in ipairs(folder:GetChildren()) do
        if validMonster(monster) then
            local name = monsterType(monster)
            if (next(S.Selected) == nil or S.Selected[name]) and
                (not S.BossOnly or isBoss(monster)) then
                local pos = modelPos(monster)
                if pos then
                    local d = (root.Position - pos).Magnitude
                    if d <= S.FarmRange and (not distance or d < distance) then
                        chosen, distance = monster, d
                    end
                end
            end
        end
    end
    return chosen, distance
end

local function attackTarget(model, distance)
    local root = getRoot()
    local pos = modelPos(model)
    if not root or not pos or not model.Parent then return end
    local v = Vector3.new(pos.X - root.Position.X, 0, pos.Z - root.Position.Z)
    if v.Magnitude < 0.4 then return end
    if S.FollowTarget and distance > S.AttackDistance then
        local humanoid = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            S.MovePriority = "farm"
            humanoid:MoveTo(pos - v.Unit * math.min(S.AttackDistance - 4, 12))
        end
    end
    if distance > S.AttackDistance then return end
    local facing = v.Unit
    local okay1 = remote("Atacar", model)
    local okay2 = remote("Golpear", facing, true, pos)
    if okay1 and okay2 then S.FarmAttacks = S.FarmAttacks + 1 end
end

local function coreFlags(item)
    local radiant = item:GetAttribute("Radiante") == true
    local shiny = item:GetAttribute("Shiny") == true
    local kind = tostring(item:GetAttribute("TipoNucleo") or "")
    return radiant or kind:find("Radiante") ~= nil,
           shiny or kind:find("Shiny") ~= nil
end

local function allowCore(item)
    local radiant, shiny = coreFlags(item)
    if shiny then return S.CollectShiny end
    if radiant then return S.CollectRadiant end
    return S.CollectNormal
end

local function corePosition(obj)
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") then return modelPos(obj) end
    local part = obj:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position
end

local function nearestCore()
    local root = getRoot()
    if not root then return nil end
    local selected, at, distance
    for _, name in ipairs({"Nucleos", "NucleosRaros"}) do
        local folder = workspace:FindFirstChild(name)
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                local pos = corePosition(child)
                if pos and allowCore(child) then
                    local d = (root.Position - pos).Magnitude
                    if d <= S.AutoCollectDistance and (not distance or d < distance) then
                        selected, at, distance = child, pos, d
                    end
                end
            end
        end
    end
    return selected, at, distance
end

local function collectCore()
    local root, hum = getRoot()
    if not root then return end
    local item, pos, d = nearestCore()
    if not item then return end
    if S.AutoFarm and S.Target and validMonster(S.Target) then return end
    if d > 4 then
        S.MovePriority = "collect"
        hum:MoveTo(pos)
    else
        for _, obj in ipairs(item:GetDescendants()) do
            if obj:IsA("ProximityPrompt") and obj.Enabled then
                local fn = rawget(Env, "fireproximityprompt")
                if type(fn) == "function" then pcall(fn, obj) end
            end
        end
    end
end

local function inventory(action, ...)
    return remote("InventarioAcao", action, ...)
end
local function dailyTick()
    if os.clock() < S.NextDaily then return end
    S.NextDaily = os.clock() + 65
    remote("BonusDiario", "Pedir")
end

local function queueLoader()
    local fn = rawget(Env, "queue_on_teleport") or rawget(Env, "queueonteleport")
    if not fn then
        local syn = rawget(Env, "syn")
        fn = type(syn) == "table" and syn.queue_on_teleport
    end
    if type(fn) == "function" then return pcall(fn, LOADER) end
    return false
end

local function rejoin()
    if not S.AutoRejoin then return end
    if S.AutoExecute then pcall(queueLoader) end
    pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
end

local function cleanup()
    S.Running = false
    for k in pairs(S) do if type(S[k]) == "boolean" then S[k] = false end end
    for _, c in ipairs(Links) do pcall(function() c:Disconnect() end) end
    table.clear(Links)
    for _, obj in pairs(Highlights) do pcall(function() obj:Destroy() end) end
    table.clear(Highlights)
    if WindowRef and WindowRef.Destroy then
        pcall(function() WindowRef:Destroy() end)
    elseif Fluent.Destroy then
        pcall(function() Fluent:Destroy() end)
    end
    Env.__CE_SUMMON_CLEANUP = nil
end
Env.__CE_SUMMON_CLEANUP = cleanup

local Window = Fluent:CreateWindow({
    Title = "CAT EMPIRE", SubTitle = "Summon A Monster",
    TabWidth = 150, Size = UDim2.fromOffset(760, 485),
    Acrylic = true, Animated = true, Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
    ScreenGuiName = "CAT_EMPIRE_SUMMON_A_MONSTER_84554009750048",
})
WindowRef = Window
local Tabs = {
    Farm = Window:AddTab({Title = "Farm", Icon = "solar/sword-bold"}),
    Cores = Window:AddTab({Title = "Nucleos", Icon = "solar/star-bold"}),
    Inventory = Window:AddTab({Title = "Inventory", Icon = "solar/bag-bold"}),
    Upgrades = Window:AddTab({Title = "Upgrades", Icon = "solar/hammer-bold"}),
    Challenges = Window:AddTab({Title = "Challenges", Icon = "solar/cup-star-bold"}),
    Visuals = Window:AddTab({Title = "Visuals", Icon = "solar/eye-bold"}),
    Settings = Window:AddTab({Title = "Settings", Icon = "solar/settings-bold"}),
}

local function toggle(tab, id, title, key, default)
    local control = tab:AddToggle("SAM_" .. id, {
        Title = title, Default = default == true,
        Callback = function(value) S[key] = value == true end,
    })
    Toggles[key] = control
    return control
end
local function action(tab, title, callback)
    tab:AddButton({
        Title = title, Icon = "solar/refresh-bold",
        Callback = function()
            task.spawn(function()
                local ok, err = pcall(callback)
                if not ok then
                    S.LastRemoteError = tostring(err)
                    notify("Action failed: " .. tostring(err))
                end
            end)
        end,
    })
end

Status = Tabs.Farm:AddParagraph({Title = "Farm Status", Content = "Scanning current area"})
MonsterDropdown = Tabs.Farm:AddDropdown("SAM_Monsters", {
    Title = "Monsters", Values = {}, Multi = true, Default = {},
    DropdownOutsideWindow = true,
    Callback = function(chosen)
        table.clear(S.Selected)
        if type(chosen) == "table" then
            for key, val in pairs(chosen) do
                if type(key) == "string" and val == true then
                    S.Selected[key] = true
                elseif type(val) == "string" then
                    S.Selected[val] = true
                end
            end
        end
    end,
})
action(Tabs.Farm, "Refresh NPCs", function()
    notify("Found " .. refreshMonsters(true) .. " monsters")
end)
toggle(Tabs.Farm, "AutoFarm", "Auto Farm", "AutoFarm")
toggle(Tabs.Farm, "AutoAttack", "Auto Attack", "AutoAttack")
toggle(Tabs.Farm, "FollowTarget", "Auto Follow Target", "FollowTarget")
toggle(Tabs.Farm, "BossOnly", "Only Bosses", "BossOnly")
Tabs.Farm:AddSlider("SAM_Range", {
    Title = "Target Range", Default = 140, Min = 20, Max = 350, Rounding = 0,
    Callback = function(value) S.FarmRange = value end,
})
Tabs.Farm:AddSlider("SAM_Distance", {
    Title = "Attack Distance", Default = 35, Min = 6, Max = 55, Rounding = 0,
    Callback = function(value) S.AttackDistance = value end,
})
Tabs.Farm:AddSlider("SAM_AttackInterval", {
    Title = "Attack Interval", Default = 0.25, Min = 0.1, Max = 1, Rounding = 2,
    Callback = function(value) S.AttackInterval = math.max(.1, value) end,
})
toggle(Tabs.Farm, "Heal", "Auto Heal (40% HP)", "AutoHeal")

toggle(Tabs.Cores, "Collect", "Auto Collect Nucleos", "AutoCollect")
toggle(Tabs.Cores, "Normal", "Collect Normal", "CollectNormal", true)
toggle(Tabs.Cores, "Radiant", "Collect Radiant", "CollectRadiant", true)
toggle(Tabs.Cores, "Shiny", "Collect Shiny", "CollectShiny", true)
Tabs.Cores:AddSlider("SAM_CollectRange", {
    Title = "Collect Radius", Min = 20, Max = 250, Default = 120, Rounding = 0,
    Callback = function(v) S.AutoCollectDistance = v end,
})
toggle(Tabs.Cores, "EquipCores", "Auto Equip Best Nucleos", "AutoEquipCores")
action(Tabs.Cores, "Equip Best Nucleos", function()
    inventory("EquiparMelhores", "nucleos")
end)
action(Tabs.Cores, "Sync Nucleos", function() inventory("Sincronizar") end)
Toggles.AutoNative = Tabs.Cores:AddToggle("SAM_NativeAuto", {
    Title = "Native Auto (Requires Gamepass)", Default = false,
    Callback = function(value)
        if value == true and LP:GetAttribute("Passe_Auto") ~= true then
            S.AutoNative = false
            notify("Native Auto requires the game's pass")
            task.defer(function() pcall(function() Toggles.AutoNative:SetValue(false) end) end)
            return
        end
        S.AutoNative = value == true
        if not S.AutoNative and S.NativeStarted then
            S.NativeStarted = false
            remote("AutoEvento", "desligar")
        end
    end,
})

toggle(Tabs.Inventory, "EquipGear", "Auto Equip Best Equipment", "AutoEquipGear")
action(Tabs.Inventory, "Equip Best Equipment", function()
    inventory("EquiparMelhores", "equipamento")
end)
toggle(Tabs.Inventory, "ConfirmSell", "Allow Automatic Selling", "ConfirmSell")
toggle(Tabs.Inventory, "SellDuplicates", "Auto Sell Repeated Equipment", "SellDuplicates")
toggle(Tabs.Inventory, "SellLow", "Auto Sell By Rarity", "AutoSell")
Tabs.Inventory:AddDropdown("SAM_SellRarity", {
    Title = "Sell Up To", Values = {"Basic", "Rare", "Epic"},
    Default = "Basic", DropdownOutsideWindow = true,
    Callback = function(v)
        S.SellRarity = ({Basic = 1, Rare = 2, Epic = 3})[v] or 1
    end,
})
action(Tabs.Inventory, "Sync Inventory", function() inventory("Sincronizar") end)

toggle(Tabs.Upgrades, "CraftBest", "Auto Craft Best", "AutoCraftBest")
action(Tabs.Upgrades, "Craft Best Once", function() remote("CraftingEvento", "CraftarMelhores") end)
action(Tabs.Upgrades, "Plan Best Craft", function() remote("CraftingEvento", "PlanejarMelhores") end)
Tabs.Upgrades:AddInput("SAM_Recipe", {
    Title = "Recipe ID", Default = "", Placeholder = "Recipe ID from game",
    Callback = function(v) S.CraftRecipe = tostring(v) end,
})
action(Tabs.Upgrades, "Craft Selected Recipe", function()
    if S.CraftRecipe == "" then notify("Enter recipe ID"); return end
    remote("CraftingEvento", "Craftar", S.CraftRecipe)
end)
Tabs.Upgrades:AddDropdown("SAM_ReforgeZone", {
    Title = "Reforge Nucleo Zone", Values = {"eq", "inv"}, Default = "eq",
    DropdownOutsideWindow = true,
    Callback = function(v) S.ReforgeZone = tostring(v) end,
})
Tabs.Upgrades:AddInput("SAM_ReforgeIndex", {
    Title = "Reforge Equipment Index", Default = "1", Numeric = true,
    Callback = function(v) S.ReforgeIndex = math.max(1, math.floor(tonumber(v) or 1)) end,
})
action(Tabs.Upgrades, "Reforge Nucleo Once (No Locks)", function()
    remote("ReforjaEvento", "Reforjar", S.ReforgeZone, S.ReforgeIndex, {})
end)

toggle(Tabs.Challenges, "Daily", "Auto Claim Daily", "AutoDaily")
toggle(Tabs.Challenges, "Group", "Auto Claim Group Reward", "AutoGroup")
action(Tabs.Challenges, "Refresh Quests", function() remote("MissoesPedir") end)
action(Tabs.Challenges, "Refresh Daily", function() remote("BonusDiario", "Pedir") end)
action(Tabs.Challenges, "Claim Group Reward", function() remote("GrupoResgatar") end)
action(Tabs.Challenges, "Open Tower", function() remote("TorreEvento", "Abrir") end)
action(Tabs.Challenges, "Enter Tower", function() remote("TorreEvento", "Entrar") end)
action(Tabs.Challenges, "Continue Tower", function() remote("TorreEvento", "Continuar") end)
action(Tabs.Challenges, "Exit Tower", function() remote("TorreEvento", "Sair") end)
toggle(Tabs.Challenges, "AutoTower", "Auto Tower Continue", "AutoTower")
Tabs.Challenges:AddInput("SAM_PortalArea", {
    Title = "Portal Area ID", Default = "",
    Callback = function(v) S.PortalArea = tostring(v) end,
})
action(Tabs.Challenges, "Open Portal", function()
    if S.PortalArea == "" then notify("Enter area ID"); return end
    remote("PortalEvento", "Abrir", S.PortalArea)
end)

toggle(Tabs.Visuals, "ESPMonsters", "ESP Monsters & Bosses", "ESPMonsters")
toggle(Tabs.Visuals, "ESPCores", "ESP Nucleos", "ESPCores")
toggle(Tabs.Visuals, "RareNotify", "Rare Drop Notifications", "NotifyRare", true)
action(Tabs.Visuals, "Show Diagnostics", function()
    notify(string.format("Hits: %d | Target: %s | Remote: %s",
        S.FarmAttacks, S.Target and monsterType(S.Target) or "none",
        S.LastRemoteError ~= "" and S.LastRemoteError or "OK"), 7)
end)

toggle(Tabs.Settings, "AntiAFK", "Anti AFK", "AntiAFK")
toggle(Tabs.Settings, "AutoRejoin", "Auto Rejoin", "AutoRejoin")
toggle(Tabs.Settings, "AutoExecute", "Load Script After Rejoin", "AutoExecute")
Tabs.Settings:AddDropdown("SAM_Theme", {
    Title = "Theme", Values = Fluent.Themes, Default = "Dark",
    DropdownOutsideWindow = true,
    Callback = function(v) pcall(function() Fluent:SetTheme(v) end) end,
})
local ConfigKeys = {
    "AutoFarm", "AutoAttack", "FollowTarget", "BossOnly", "AutoCollect",
    "CollectNormal", "CollectRadiant", "CollectShiny", "AutoEquipCores",
    "AutoEquipGear", "AutoCraftBest", "AutoDaily", "AutoGroup", "AutoHeal",
    "AutoTower", "AutoNative", "AutoSell", "SellDuplicates", "ConfirmSell",
    "ESPMonsters", "ESPCores", "NotifyRare", "AntiAFK",
    "AutoRejoin", "AutoExecute",
}
local function saveConfig()
    local fn = rawget(Env, "writefile")
    if type(fn) ~= "function" then notify("Executor does not support writefile"); return end
    local data = {selected = S.Selected, SellRarity = S.SellRarity,
        FarmRange = S.FarmRange, AttackDistance = S.AttackDistance,
        AttackInterval = S.AttackInterval, AutoCollectDistance = S.AutoCollectDistance}
    for _, name in ipairs(ConfigKeys) do data[name] = S[name] end
    local ok, err = pcall(fn, S.ConfigName, HttpService:JSONEncode(data))
    notify(ok and "Settings saved" or ("Save failed: " .. tostring(err)))
end
local function loadConfig()
    local fn = rawget(Env, "readfile")
    if type(fn) ~= "function" then notify("Executor does not support readfile"); return end
    local ok, config = pcall(function()
        return HttpService:JSONDecode(fn(S.ConfigName))
    end)
    if not ok or type(config) ~= "table" then notify("No valid saved settings"); return end
    if type(config.selected) == "table" then
        S.Selected = config.selected
        local selected = {}
        for _, name in ipairs(MonsterOptions) do
            if S.Selected[name] then selected[name] = true end
        end
        pcall(function() MonsterDropdown:SetValue(selected) end)
    end
    for _, name in ipairs(ConfigKeys) do
        if type(config[name]) == "boolean" and Toggles[name] then
            pcall(function() Toggles[name]:SetValue(config[name]) end)
        end
    end
    for _, name in ipairs({"SellRarity", "FarmRange", "AttackDistance", "AttackInterval", "AutoCollectDistance"}) do
        if type(config[name]) == "number" then S[name] = config[name] end
    end
    notify("Saved settings loaded")
end
action(Tabs.Settings, "Save Settings", saveConfig)
action(Tabs.Settings, "Load Settings", loadConfig)
action(Tabs.Settings, "Unload CAT EMPIRE", cleanup)

local function highlight(item, tag, enabled, color)
    local old = Highlights[item]
    if not enabled or not item or not item.Parent then
        if old then pcall(function() old:Destroy() end) end
        Highlights[item] = nil
        return
    end
    if old and old.Parent then return end
    local success, object = pcall(function()
        local h = Instance.new("Highlight")
        h.Name = "CAT_EMPIRE_" .. tag
        h.Adornee = item
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.FillTransparency = 0.84
        h.OutlineTransparency = 0.08
        h.FillColor = color
        h.OutlineColor = color
        h.Parent = item
        return h
    end)
    if success then Highlights[item] = object end
end

local function syncESP()
    local seen = {}
    local folder = workspace:FindFirstChild("Monstros")
    if S.ESPMonsters and folder then
        for _, m in ipairs(folder:GetChildren()) do
            if validMonster(m) then
                seen[m] = true
                highlight(m, "MONSTER", true,
                    isBoss(m) and Color3.fromRGB(255, 100, 75) or Color3.fromRGB(130, 195, 255))
            end
        end
    end
    if S.ESPCores then
        for _, name in ipairs({"Nucleos", "NucleosRaros"}) do
            local cores = workspace:FindFirstChild(name)
            if cores then
                for _, core in ipairs(cores:GetChildren()) do
                    seen[core] = true
                    local radiant, shiny = coreFlags(core)
                    highlight(core, "CORE", true,
                        shiny and Color3.fromRGB(255, 220, 80) or
                        radiant and Color3.fromRGB(245, 70, 245) or
                        Color3.fromRGB(90, 255, 140))
                end
            end
        end
    end
    for item in pairs(Highlights) do
        if not seen[item] then highlight(item, "", false) end
    end
end

local lastRare = {}
local function watchCore(core)
    local radiant, shiny = coreFlags(core)
    if not S.NotifyRare or (not radiant and not shiny) then return end
    if lastRare[core] then return end
    lastRare[core] = true
    notify((shiny and "Shiny" or "Radiant") .. " core: " .. tostring(core:GetAttribute("TipoNucleo") or core.Name), 5)
    task.delay(50, function() lastRare[core] = nil end)
end
for _, name in ipairs({"Nucleos", "NucleosRaros"}) do
    local folder = workspace:FindFirstChild(name)
    if folder then link(folder.ChildAdded, function(core) task.defer(watchCore, core) end) end
end
local dailyResponse = RS:FindFirstChild("BonusDiario")
if dailyResponse and dailyResponse:IsA("RemoteEvent") then
    link(dailyResponse.OnClientEvent, function(command, data)
        if command == "Estado" and type(data) == "table" and
           data.Disponivel == true and S.AutoDaily then
            remote("BonusDiario", "Resgatar")
        end
    end)
end
link(LP.Idled, function()
    if S.AntiAFK then pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end) end
end)
local okErr, errorSignal = pcall(function() return GuiService.ErrorMessageChanged end)
if okErr and errorSignal then link(errorSignal, function(message)
    if S.AutoRejoin and tostring(message):lower():find("disconnect", 1, true) then rejoin() end
end) end

local function worker(name, interval, fn)
    task.spawn(function()
        while S.Running do
            if S[name] then
                local ok, err = pcall(fn)
                if not ok then S.LastRemoteError = tostring(err) end
            end
            task.wait(type(interval) == "function" and interval() or interval)
        end
    end)
end

worker("AutoFarm", function() return S.AttackInterval end, function()
    local monster, distance = chooseTarget()
    S.Target = monster
    if not monster then
        S.LastFarmResult = "No matching monster in range"
    else
        S.LastFarmResult = monsterType(monster)
        attackTarget(monster, distance)
    end
end)
worker("AutoAttack", function() return S.AttackInterval end, function()
    if S.AutoFarm then return end
    local monster, distance = chooseTarget()
    if monster then attackTarget(monster, distance) end
end)
worker("AutoCollect", 0.6, collectCore)
worker("AutoHeal", 2, function()
    local _, hum = getRoot()
    if hum and hum.Health / math.max(1, hum.MaxHealth) < 0.4 then
        remote("FrascoEvento", "Usar")
    end
end)
worker("AutoEquipCores", 15, function() inventory("EquiparMelhores", "nucleos") end)
worker("AutoEquipGear", 15, function() inventory("EquiparMelhores", "equipamento") end)
worker("AutoCraftBest", 22, function() remote("CraftingEvento", "CraftarMelhores") end)
worker("AutoDaily", 6, dailyTick)
worker("AutoGroup", 120, function() remote("GrupoResgatar") end)
worker("AutoTower", 12, function() remote("TorreEvento", "Continuar") end)
worker("AutoNative", 4, function()
    if LP:GetAttribute("Passe_Auto") == true then
        if LP:GetAttribute("AutoAtivo") ~= true then
            local ok = remote("AutoEvento", "ligar")
            if ok then S.NativeStarted = true end
        end
    else
        S.AutoNative = false
        pcall(function() Toggles.AutoNative:SetValue(false) end)
        notify("Native Auto requires the game's pass")
    end
end)
worker("AutoSell", 28, function()
    if S.ConfirmSell then inventory("VenderAte", S.SellRarity) end
end)
worker("SellDuplicates", 32, function()
    if S.ConfirmSell then inventory("LimparRepetidos") end
end)

task.spawn(function()
    while S.Running do
        if os.clock() - S.LastMonsterRefresh > 5 then
            pcall(refreshMonsters, false)
        end
        if S.ESPMonsters or S.ESPCores or next(Highlights) then
            pcall(syncESP)
        end
        if S.AutoFarm then
            setStatus("Farm Running", string.format("%s | attacks: %d | %s",
                S.LastFarmResult, S.FarmAttacks,
                S.LastRemoteError ~= "" and S.LastRemoteError or "OK"))
        elseif S.AutoCollect then
            setStatus("Collecting Cores", S.LastRemoteError)
        else
            setStatus("Ready", string.format("%d monster types in area | %d attacks",
                #MonsterOptions, S.FarmAttacks))
        end
        task.wait(1.5)
    end
end)

refreshMonsters(true)
notify("Summon A Monster module loaded - select monsters to begin")
