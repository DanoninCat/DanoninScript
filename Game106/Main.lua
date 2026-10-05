if game.PlaceId ~= 106198175232796 then
    return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local LocalPlayer = Players.LocalPlayer
local Env = (getgenv and getgenv()) or _G
local LOADER_COMMAND = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Loader/Loader.lua", true))()]]

if type(Env.__CE_GAME106_CLEANUP) == "function" then
    pcall(Env.__CE_GAME106_CLEANUP)
end

local FluentSource = Env["__CE_F_91A7"]
if type(FluentSource) ~= "string" or FluentSource == "" then
    return
end

local okFluent, Fluent = pcall(function()
    return loadstring(FluentSource)()
end)
if not okFluent or not Fluent then
    return
end

local okOmni, Omni = pcall(require, ReplicatedStorage:WaitForChild("Omni"))
if not okOmni or type(Omni) ~= "table" then
    return
end
if not Omni.Loaded and type(Omni.Init) == "function" then
    pcall(function()
        Omni:Init()
    end)
end
if type(Omni.WaitInitialization) == "function" then
    pcall(function()
        Omni:WaitInitialization()
    end)
end

local deadline = os.clock() + 15
while (type(Omni.Data) ~= "table" or not Omni.Instance) and os.clock() < deadline do
    task.wait(0.1)
end
if type(Omni.Data) ~= "table" then
    return
end

local State = {
    Running = true,
    SelectedNPCs = {},
    AutoFarm = false,
    FarmHeight = 5,
    FarmOffset = 2,
    SelectedIsland = nil,
    ReturnPosition = nil,
    AutoReturn = false,
    AutoDungeon = false,
    AutoTrial = false,
    WasInGamemode = false,
    LastJoinCheck = {Dungeon = 0, Trial = 0},
    LastDoorScan = 0,
    SelectedStar = nil,
    AutoStars = false,
    StarRequest = 0,
    NextStarRoll = 0,
    SelectedGacha = nil,
    AutoGacha = false,
    GachaRequest = 0,
    NextGachaRoll = 0,
    AutoEquipBest = false,
    LastBestEquip = 0,
    AntiAFK = false,
    AutoRejoin = false,
    AutoCloseUI = false,
    AutoExecute = false,
    RejoinQueued = false,
    AutoClaimLevel = false,
    LastRewardClaim = 0,
    SelectedFighters = {},
    TraitTargets = {},
    AutoTraits = false,
    TraitRequest = 0,
    TraitCursor = 0,
    NextTraitRoll = 0,
    SelectedUpgrades = {},
    AutoUpgrade = false,
    UpgradeCursor = 0,
    NextUpgrade = 0,
    ProfileName = tostring(LocalPlayer.UserId),
    ActiveProfile = nil,
    AutoLoadConfig = false,
}

local Connections = {}
local WindowRef
local Controls = {}
local NPCLookup = {}
local NPCMapLookup = {}
local FighterLookup = {}
local ConfigLookup = {}
local LastNPCSignature = ""
local LastFighterSignature = ""
local LastConfigSignature = ""
local LastStatus = {}
local OriginalAnimationSettings = {
    Star = Omni.Data.Settings and Omni.Data.Settings["Hide Star Animation"] == true,
    Gacha = Omni.Data.Settings and Omni.Data.Settings["Hide Gacha Animation"] == true,
}

local function connect(signal, callback)
    if not signal then
        return nil
    end
    local connection = signal:Connect(callback)
    Connections[#Connections + 1] = connection
    return connection
end

local function notify(text, duration)
    pcall(function()
        Fluent:Notify({
            Title = "CAT EMPIRE",
            Content = tostring(text or ""),
            Duration = duration or 3,
        })
    end)
end

local function setParagraph(target, title, content)
    if not target then
        return
    end
    if target.SetTitle then
        pcall(function() target:SetTitle(title) end)
    end
    if target.SetDesc then
        pcall(function() target:SetDesc(content or "") end)
    end
end

local function status(key, paragraph, title, text)
    text = tostring(text or "")
    if LastStatus[key] == text then
        return
    end
    LastStatus[key] = text
    setParagraph(paragraph, title, text)
end

local function fire(...)
    local args = table.pack(...)
    return pcall(function()
        Omni.Signal:Fire(table.unpack(args, 1, args.n))
    end)
end

local function invoke(...)
    local args = table.pack(...)
    local ok, result = pcall(function()
        return Omni.Signal:Invoke(table.unpack(args, 1, args.n))
    end)
    return ok, result
end

local function getRoot()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function currentMap()
    return Omni.Data.Maps and Omni.Data.Maps.Current
end

local function ownsMap(name)
    local ok, result = pcall(function()
        return Omni.Utils.PlayerStats.OwnsMap(name, Omni.Data)
    end)
    return ok and result == true
end

local function teleportMap(name)
    if type(name) ~= "string" or not Omni.Shared.Maps.List[name] then
        return false
    end
    if currentMap() == name then
        return true
    end
    if not ownsMap(name) then
        notify("Island ainda não liberada: " .. name)
        return false
    end
    fire("General", "Maps", "Teleport", name)
    return true
end

local function waitForMap(name, timeout)
    local untilTime = os.clock() + (timeout or 8)
    while State.Running and os.clock() < untilTime do
        if currentMap() == name then
            return true
        end
        task.wait(0.15)
    end
    return currentMap() == name
end

local function cframeToArray(cf)
    if typeof(cf) ~= "CFrame" then
        return nil
    end
    return {cf:GetComponents()}
end

local function arrayToCFrame(value)
    if type(value) ~= "table" or #value < 12 then
        return nil
    end
    local ok, cf = pcall(function()
        return CFrame.new(table.unpack(value, 1, 12))
    end)
    return ok and cf or nil
end

local function savePosition()
    local root = getRoot()
    if not root then
        notify("Personagem ainda não carregou")
        return false
    end
    State.ReturnPosition = root.CFrame
    notify("Posição salva")
    return true
end

local function returnPosition()
    local root = getRoot()
    if not root or typeof(State.ReturnPosition) ~= "CFrame" then
        return false
    end
    root.CFrame = State.ReturnPosition
    return true
end

local function orderedMaps()
    local values = {}
    for name, info in pairs(Omni.Shared.Maps.List or {}) do
        if type(name) == "string" and type(info) == "table" and info.Hidden ~= true then
            values[#values + 1] = {Name = name, Index = tonumber(info.Index) or 9999}
        end
    end
    table.sort(values, function(a, b)
        if a.Index == b.Index then
            return a.Name < b.Name
        end
        return a.Index < b.Index
    end)
    local out = {}
    for _, item in ipairs(values) do
        out[#out + 1] = item.Name
    end
    return out
end

local function enemyName(instance)
    local value = instance and instance:GetAttribute("EnemyName")
    if type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

local function refreshNPCs(force)
    local names = {}
    local seen = {}
    local mapLookup = {}
    local sharedEnemies = Omni.Shared.Enemies and Omni.Shared.Enemies.List or {}
    for mapName, mapEnemies in pairs(sharedEnemies) do
        if type(mapName) == "string" and type(mapEnemies) == "table" then
            for name, info in pairs(mapEnemies) do
                if type(name) == "string" and type(info) == "table" then
                    mapLookup[name] = mapName
                    if not seen[name] then
                        seen[name] = true
                        names[#names + 1] = name
                    end
                end
            end
        end
    end
    for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
        if enemy and enemy.Parent and enemy:GetAttribute("Died") ~= true then
            local name = enemyName(enemy)
            if name and not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
    end
    table.sort(names)
    local signature = table.concat(names, "|")
    if force or signature ~= LastNPCSignature then
        NPCLookup = seen
        NPCMapLookup = mapLookup
        LastNPCSignature = signature
        local dropdown = Controls.NPCs
        if dropdown and dropdown.SetValues then
            local selected = {}
            for _, name in ipairs(names) do
                if State.SelectedNPCs[name] then
                    selected[name] = true
                end
            end
            pcall(function()
                dropdown:SetValues(names)
                dropdown:SetValue(selected)
            end)
        end
    end
    return names
end

local function isSelectedNPC(name)
    if next(State.SelectedNPCs) == nil then
        return false
    end
    return State.SelectedNPCs[name] == true
end

local function getEnemyPosition(enemy)
    local id = enemy:GetAttribute("EnemyID")
    if type(id) == "string" and Omni.Utils and Omni.Utils.Enemies then
        local ok, cf = pcall(function()
            return Omni.Utils.Enemies.GetPosition(id)
        end)
        if ok and typeof(cf) == "CFrame" then
            return cf
        end
    end
    if enemy:IsA("BasePart") then
        return enemy.CFrame
    end
    return nil
end

local function findEnemy(useSelection)
    local root = getRoot()
    if not root then
        return nil
    end
    local best, bestDistance
    for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
        if enemy and enemy.Parent and enemy:GetAttribute("Died") ~= true and enemy:GetAttribute("Shielded") ~= true then
            local name = enemyName(enemy)
            if name and (not useSelection or isSelectedNPC(name)) then
                local cf = getEnemyPosition(enemy)
                if cf then
                    local distance = (root.Position - cf.Position).Magnitude
                    if not bestDistance or distance < bestDistance then
                        best = enemy
                        bestDistance = distance
                    end
                end
            end
        end
    end
    return best
end

local function attackEnemy(enemy)
    if not enemy or not enemy.Parent then
        return false
    end
    local id = enemy:GetAttribute("EnemyID")
    if type(id) ~= "string" or id == "" then
        return false
    end
    local cf = getEnemyPosition(enemy)
    local root = getRoot()
    if root and cf then
        root.CFrame = cf * CFrame.new(0, State.FarmHeight, State.FarmOffset)
    end
    local fighterIds = {}
    local okFighters, available = pcall(function()
        return Omni.Utils.PlayerStats.GetAvailableFightersForTarget(id, Omni.Data, Omni.Instance)
    end)
    if okFighters and type(available) == "table" then
        fighterIds = available
    end
    if #fighterIds > 0 then
        invoke("General", "Combat", "FighterAttack", id, fighterIds)
    end
    fire("General", "Combat", "PlayerAttack")
    return true
end

local function farmStep(useSelection)
    local target = findEnemy(useSelection)
    if not target then
        if useSelection and next(State.SelectedNPCs) ~= nil then
            local here = currentMap()
            local hasSelectedHere = false
            local destination
            for name, enabled in pairs(State.SelectedNPCs) do
                if enabled then
                    local mapName = NPCMapLookup[name]
                    if mapName == here then
                        hasSelectedHere = true
                        break
                    elseif not destination and type(mapName) == "string" then
                        destination = mapName
                    end
                end
            end
            if not hasSelectedHere and destination and destination ~= here then
                teleportMap(destination)
            end
        end
        return false
    end
    return attackEnemy(target)
end

local function openNearbyDungeonDoors()
    if os.clock() - State.LastDoorScan < 0.9 then
        return
    end
    State.LastDoorScan = os.clock()
    for _, item in ipairs(workspace:GetDescendants()) do
        if item:IsA("ProximityPrompt") then
            local room = item:GetAttribute("RoomIndex") or (item.Parent and item.Parent:GetAttribute("RoomIndex"))
            local child = item:GetAttribute("ChildIndex") or (item.Parent and item.Parent:GetAttribute("ChildIndex"))
            if type(room) == "number" and type(child) == "number" then
                invoke("General", "Gamemodes", "OpenDoor", room, child)
            end
        end
    end
end

local function findGamemode(kind)
    local candidates = {}
    for name, info in pairs(Omni.Shared.Gamemodes.List or {}) do
        if type(info) == "table" and info.Type == kind then
            candidates[#candidates + 1] = {Name = name, Info = info}
        end
    end
    table.sort(candidates, function(a, b)
        local order = {Easy = 1, Medium = 2, Hard = 3, Insane = 4, Boss = 5, Secret = 6}
        local av = order[a.Info.Difficulty] or 99
        local bv = order[b.Info.Difficulty] or 99
        if av == bv then
            return a.Name < b.Name
        end
        return av < bv
    end)
    return candidates[1]
end

local function tryJoinGamemode(kind)
    local lastCheck = State.LastJoinCheck[kind] or 0
    if os.clock() - lastCheck < 2.5 then
        return false
    end
    State.LastJoinCheck[kind] = os.clock()
    local mode = findGamemode(kind)
    if not mode then
        return false
    end
    local active = Omni.Data.Gamemode
    if active == mode.Name then
        return true
    end
    if type(active) == "string" and active ~= "" then
        return false
    end
    if mode.Info.MapName and currentMap() ~= mode.Info.MapName then
        teleportMap(mode.Info.MapName)
        return false
    end
    local ok, preview = invoke("General", "Gamemodes", "Preview", mode.Name)
    if ok and type(preview) == "table" and preview.Status == "Opened" then
        local closesAt = tonumber(preview.EntryClosesAt)
        if not closesAt or workspace:GetServerTimeNow() < closesAt then
            local joinedOk, joined = invoke("General", "Gamemodes", "Join", mode.Name)
            return joinedOk and joined ~= false
        end
    end
    return false
end

local function gamemodeKind(name)
    local info = name and Omni.Shared.Gamemodes.List[name]
    return info and info.Type or nil
end

local function findTaggedByName(tag, name)
    for _, instance in ipairs(CollectionService:GetTagged(tag)) do
        if instance and instance.Parent and instance.Name == name then
            return instance
        end
    end
    return nil
end

local function moveNear(instance, distance)
    if not instance then
        return false
    end
    local root = getRoot()
    if not root then
        return false
    end
    local part
    if instance:IsA("BasePart") then
        part = instance
    elseif instance:IsA("Model") then
        part = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
    else
        part = instance:FindFirstChildWhichIsA("BasePart", true)
    end
    if not part then
        return false
    end
    root.CFrame = part.CFrame * CFrame.new(0, 2.5, distance or 5)
    return true
end

local function findPromptFor(name)
    for _, prompt in ipairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            if prompt.ObjectText == name or prompt:GetAttribute("ObjectText") == name then
                return prompt
            end
            local parent = prompt.Parent
            if parent and (parent.Name == name or parent:GetAttribute("Name") == name) then
                return prompt
            end
        end
    end
    return nil
end

local function ensureAtStar(name)
    local info = Omni.Shared.Stars.List[name]
    if not info then
        return false
    end
    if info.MapName and currentMap() ~= info.MapName then
        if not teleportMap(info.MapName) then
            return false
        end
        if not waitForMap(info.MapName, 7) then
            return false
        end
        task.wait(0.6)
    end
    local model = findTaggedByName("StarModel", name)
    if model then
        moveNear(model, 6)
        task.wait(0.15)
    end
    return true
end

local function starStep()
    local name = State.SelectedStar
    if type(name) ~= "string" or not Omni.Shared.Stars.List[name] then
        return false
    end
    if os.clock() < State.NextStarRoll then
        return false
    end
    if not ensureAtStar(name) then
        State.NextStarRoll = os.clock() + 1
        return false
    end
    local freeSlots = 1
    pcall(function()
        local _, _, free = Omni.Utils.PlayerStats.FightersInventory(Omni.Data, Omni.Instance)
        freeSlots = free
    end)
    if type(freeSlots) == "number" and freeSlots <= 0 then
        State.AutoStars = false
        if Controls.AutoStars and Controls.AutoStars.SetValue then
            pcall(function() Controls.AutoStars:SetValue(false) end)
        end
        notify("Inventário cheio; Auto Stars foi parado")
        return false
    end
    local amount = 1
    local cooldown = 3.5
    pcall(function()
        amount = math.max(1, math.floor(Omni.Utils.PlayerStats.MaxStarOpens(Omni.Data, Omni.Instance)))
        local speed = Omni.Utils.PlayerStats.StarOpenSpeed(Omni.Data, Omni.Instance)
        if type(speed) == "number" and speed > 0 then
            cooldown = 3.5 / speed
        end
    end)
    State.StarRequest = State.StarRequest + 1
    fire("General", "Stars", "Roll", name, amount, State.StarRequest)
    State.NextStarRoll = os.clock() + math.max(0.15, cooldown + 0.08)
    return true
end

local function orderedStars()
    local rows = {}
    for name, info in pairs(Omni.Shared.Stars.List or {}) do
        rows[#rows + 1] = {Name = name, Map = info.MapName or ""}
    end
    table.sort(rows, function(a, b)
        local am = Omni.Shared.Maps.List[a.Map]
        local bm = Omni.Shared.Maps.List[b.Map]
        local ai = am and am.Index or 999
        local bi = bm and bm.Index or 999
        if ai == bi then
            return a.Name < b.Name
        end
        return ai < bi
    end)
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = row.Name
    end
    return out
end

local function orderedGachas()
    local rows = {}
    for name, info in pairs(Omni.Shared.Gacha.List or {}) do
        rows[#rows + 1] = {Name = name, Map = info.Map or ""}
    end
    table.sort(rows, function(a, b)
        local am = Omni.Shared.Maps.List[a.Map]
        local bm = Omni.Shared.Maps.List[b.Map]
        local ai = am and am.Index or 999
        local bi = bm and bm.Index or 999
        if ai == bi then
            return a.Name < b.Name
        end
        return ai < bi
    end)
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = row.Name
    end
    return out
end

local function ensureAtGacha(name)
    local info = Omni.Shared.Gacha.List[name]
    if not info then
        return false
    end
    if info.Map and currentMap() ~= info.Map then
        if not teleportMap(info.Map) then
            return false
        end
        if not waitForMap(info.Map, 7) then
            return false
        end
        task.wait(0.6)
    end
    local prompt = findPromptFor(name)
    if prompt and prompt.Parent then
        moveNear(prompt.Parent, 5)
        task.wait(0.15)
    end
    return true
end

local function canPay(price)
    if type(price) ~= "table" then
        return true
    end
    local economy = Omni.Shared.Economy
    local policy = Omni.Shared.MonetizationPolicy
    if type(economy) == "table" and type(economy.CanSpendRandom) == "function" then
        local ok, allowed = pcall(function()
            local playerPolicy = type(policy) == "table"
                and type(policy.FromPlayer) == "function"
                and policy.FromPlayer(Omni.Instance)
                or nil
            return economy.CanSpendRandom(Omni.Data, price, playerPolicy)
        end)
        if ok then
            return allowed == true
        end
    end
    local amount = 0
    if price.Type == "Item" or price.Type == "Items" then
        amount = Omni.Data.Items and Omni.Data.Items.List and Omni.Data.Items.List[price.Name] or 0
    else
        amount = Omni.Data[price.Name] or 0
    end
    return (tonumber(amount) or 0) >= (tonumber(price.Amount) or 0)
end

local function gachaStep()
    local name = State.SelectedGacha
    local info = name and Omni.Shared.Gacha.List[name]
    if not info or os.clock() < State.NextGachaRoll then
        return false
    end
    if not ensureAtGacha(name) then
        State.NextGachaRoll = os.clock() + 1
        return false
    end
    if not canPay(info.Price) then
        State.AutoGacha = false
        if Controls.AutoGacha and Controls.AutoGacha.SetValue then
            pcall(function() Controls.AutoGacha:SetValue(false) end)
        end
        notify("Saldo insuficiente; Auto Gacha foi parado")
        return false
    end
    local cooldown = 2
    pcall(function()
        cooldown = Omni.Utils.PlayerStats.GachaCooldown(Omni.Data, Omni.Instance, name)
    end)
    State.GachaRequest = State.GachaRequest + 1
    fire("General", "Gacha", "Roll", name, nil, State.GachaRequest)
    State.NextGachaRoll = os.clock() + math.max(0.12, (tonumber(cooldown) or 2) + 0.08)
    return true
end

local function equipBest()
    fire("General", "Fighters", "EquipBest")
    task.wait(0.08)
    fire("General", "Weapons", "EquipBest")
end

local function queueLoader()
    local queueFn = rawget(Env, "queue_on_teleport") or rawget(Env, "queueonteleport")
    local syn = rawget(Env, "syn")
    local fluxus = rawget(Env, "fluxus")
    if type(queueFn) ~= "function" and type(syn) == "table" then
        queueFn = syn.queue_on_teleport
    end
    if type(queueFn) ~= "function" and type(fluxus) == "table" then
        queueFn = fluxus.queue_on_teleport
    end
    if type(queueFn) ~= "function" then
        return false
    end
    return pcall(queueFn, LOADER_COMMAND)
end

local function requestReconnect()
    if not State.AutoRejoin or State.RejoinQueued then
        return
    end
    State.RejoinQueued = true
    if State.AutoExecute then
        pcall(queueLoader)
    end
    task.delay(0.8, function()
        if not State.Running then
            return
        end
        local ok = pcall(function()
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        end)
        if not ok then
            State.RejoinQueued = false
        end
    end)
end

local function applyAnimationVisibility(enabled)
    invoke("General", "Settings", "Set", "Hide Star Animation", enabled == true)
    invoke("General", "Settings", "Set", "Hide Gacha Animation", enabled == true)
end

local function closeGameFrames()
    if not State.AutoCloseUI then
        return
    end
    pcall(function()
        Omni.Frame:Close("Star")
    end)
    pcall(function()
        Omni.Frame:Close("Gacha")
    end)
    pcall(function()
        Omni.Frame:Close("Traits")
    end)
    pcall(function()
        Omni.Frame:Close("Upgrade")
    end)
end

local function claimLevelRewards()
    local levelData = Omni.Data.Level
    local shared = Omni.Shared.PlayerLevel and Omni.Shared.PlayerLevel.List
    if type(levelData) ~= "table" or type(shared) ~= "table" or type(shared.Rewards) ~= "table" then
        return
    end
    local current = tonumber(levelData.Amount) or 0
    local claimed = levelData.Rewards or {}
    for _, reward in ipairs(shared.Rewards) do
        local level = tonumber(reward.Level)
        if level and level <= current and claimed["Level" .. level] ~= true then
            fire("General", "PlayerLevel", "ClaimReward", level)
            task.wait(0.08)
        end
    end
end

local function fighterDisplayName(fighter)
    if type(fighter) ~= "table" then
        return "Fighter"
    end
    local name = fighter.Name or "Fighter"
    local ok, display = pcall(function()
        return Omni.Shared.Fighters.GetDisplayName(name)
    end)
    if ok and type(display) == "string" and display ~= "" then
        return display
    end
    return tostring(name)
end

local function currentTrait(fighter)
    local ok, info = pcall(function()
        return Omni.Shared.Traits.Get(fighter)
    end)
    return ok and type(info) == "table" and info.Name or nil
end

local function refreshFighters(force)
    local values = {}
    local lookup = {}
    local counts = {}
    local fighters = Omni.Data.Fighters and Omni.Data.Fighters.List or {}
    local ordered = {}
    for id, fighter in pairs(fighters) do
        if type(id) == "string" and type(fighter) == "table" then
            ordered[#ordered + 1] = {ID = id, Fighter = fighter, Name = fighterDisplayName(fighter)}
        end
    end
    table.sort(ordered, function(a, b)
        if a.Name == b.Name then
            return a.ID < b.ID
        end
        return a.Name < b.Name
    end)
    for _, row in ipairs(ordered) do
        counts[row.Name] = (counts[row.Name] or 0) + 1
        local label = row.Name
        if counts[row.Name] > 1 then
            label = string.format("%s #%d", row.Name, counts[row.Name])
        end
        local trait = currentTrait(row.Fighter)
        if trait then
            label = label .. " • " .. trait
        end
        values[#values + 1] = label
        lookup[label] = row.ID
    end
    local signature = table.concat(values, "|")
    if force or signature ~= LastFighterSignature then
        local old = {}
        for id in pairs(State.SelectedFighters) do
            old[id] = true
        end
        FighterLookup = lookup
        LastFighterSignature = signature
        if Controls.Fighters and Controls.Fighters.SetValues then
            local selectedLabels = {}
            for label, id in pairs(lookup) do
                if old[id] then
                    selectedLabels[label] = true
                end
            end
            pcall(function()
                Controls.Fighters:SetValues(values)
                Controls.Fighters:SetValue(selectedLabels)
            end)
        end
    end
    return values
end

local function orderedTraits()
    local rows = {}
    for name, info in pairs(Omni.Shared.Traits.List or {}) do
        rows[#rows + 1] = {
            Name = name,
            Rarity = info.Rarity or "Common",
            Chance = tonumber(info.Chance) or 0,
        }
    end
    local rarityOrder = {Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythical = 6, Secret = 7}
    table.sort(rows, function(a, b)
        local ar = rarityOrder[a.Rarity] or 99
        local br = rarityOrder[b.Rarity] or 99
        if ar == br then
            if a.Chance == b.Chance then
                return a.Name < b.Name
            end
            return a.Chance > b.Chance
        end
        return ar < br
    end)
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = row.Name
    end
    return out
end

local function selectedFighterIds()
    local out = {}
    for id, enabled in pairs(State.SelectedFighters) do
        if enabled and Omni.Data.Fighters and Omni.Data.Fighters.List and Omni.Data.Fighters.List[id] then
            out[#out + 1] = id
        end
    end
    table.sort(out)
    return out
end

local function traitStep()
    if os.clock() < State.NextTraitRoll then
        return false
    end
    local ids = selectedFighterIds()
    if #ids == 0 or next(State.TraitTargets) == nil then
        return false
    end
    for _ = 1, #ids do
        State.TraitCursor = (State.TraitCursor % #ids) + 1
        local id = ids[State.TraitCursor]
        local fighter = Omni.Data.Fighters.List[id]
        local trait = currentTrait(fighter)
        if not trait or State.TraitTargets[trait] ~= true then
            local price = Omni.Shared.Traits.Price
            if not canPay(price) then
                State.AutoTraits = false
                if Controls.AutoTraits and Controls.AutoTraits.SetValue then
                    pcall(function() Controls.AutoTraits:SetValue(false) end)
                end
                notify("Trait Shards insuficientes; Auto Traits foi parado")
                return false
            end
            local cooldown = 2
            pcall(function()
                cooldown = Omni.Utils.PlayerStats.TraitsCooldown(Omni.Data, Omni.Instance)
            end)
            State.TraitRequest = State.TraitRequest + 1
            fire("General", "Traits", "Spin", id, State.TraitRequest)
            State.NextTraitRoll = os.clock() + math.max(0.2, (tonumber(cooldown) or 2) + 0.08)
            return true
        end
    end
    State.AutoTraits = false
    if Controls.AutoTraits and Controls.AutoTraits.SetValue then
        pcall(function() Controls.AutoTraits:SetValue(false) end)
    end
    notify("Todos os Fighters selecionados chegaram no Trait desejado")
    return false
end

local UPGRADE_SYSTEM = "Adventurer Upgrades"

local function orderedUpgrades()
    local system = Omni.Shared.Upgrade.List[UPGRADE_SYSTEM]
    local rows = {}
    if system and type(system.Upgrades) == "table" then
        for name, info in pairs(system.Upgrades) do
            rows[#rows + 1] = {Name = name, Index = tonumber(info.Index) or 999}
        end
    end
    table.sort(rows, function(a, b)
        if a.Index == b.Index then
            return a.Name < b.Name
        end
        return a.Index < b.Index
    end)
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = row.Name
    end
    return out
end

local function upgradeStep()
    if os.clock() < State.NextUpgrade then
        return false
    end
    local system = Omni.Shared.Upgrade.List[UPGRADE_SYSTEM]
    if not system then
        return false    end
    local selected = {}
    for name, enabled in pairs(State.SelectedUpgrades) do
        if enabled and system.Upgrades[name] then
            selected[#selected + 1] = name
        end
    end
    table.sort(selected, function(a, b)
        local ai = system.Upgrades[a].Index or 999
        local bi = system.Upgrades[b].Index or 999
        if ai == bi then
            return a < b
        end
        return ai < bi
    end)
    if #selected == 0 then
        return false
    end
    for _ = 1, #selected do
        State.UpgradeCursor = (State.UpgradeCursor % #selected) + 1
        local name = selected[State.UpgradeCursor]
        local info = system.Upgrades[name]
        local level = 0
        pcall(function()
            level = Omni.Shared.Upgrade.GetCurrentLevel(UPGRADE_SYSTEM, name, Omni.Data)
        end)
        if level < info.MaxLevel then
            local nextInfo
            pcall(function()
                nextInfo = Omni.Shared.Upgrade.GetLevelInformation(UPGRADE_SYSTEM, name, level + 1)
            end)
            if nextInfo and canPay(nextInfo.Price) then
                fire("General", "Upgrade", "Upgrade", UPGRADE_SYSTEM, name)
                State.NextUpgrade = os.clock() + 0.18
                return true
            end
        end
    end
    State.NextUpgrade = os.clock() + 0.8
    return false
end

local ConfigRoot = "CAT EMPIRE/106198175232796"
local ConfigFolder = ConfigRoot .. "/Configs"
local AutoloadPath = ConfigRoot .. "/autoload.json"

local function hasFileApi()
    return type(writefile) == "function"
        and type(readfile) == "function"
        and type(isfile) == "function"
        and type(makefolder) == "function"
end

local function ensureConfigFolder()
    if not hasFileApi() then
        return false
    end
    if type(isfolder) == "function" then
        if not isfolder("CAT EMPIRE") then pcall(makefolder, "CAT EMPIRE") end
        if not isfolder(ConfigRoot) then pcall(makefolder, ConfigRoot) end
        if not isfolder(ConfigFolder) then pcall(makefolder, ConfigFolder) end
    else
        pcall(makefolder, "CAT EMPIRE")
        pcall(makefolder, ConfigRoot)
        pcall(makefolder, ConfigFolder)
    end
    return true
end

local function cleanProfileName(value)
    value = tostring(value or "Profile")
    value = value:gsub("[^%w%-%_ ]", "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        value = "Profile"
    end
    return value:sub(1, 48)
end

local function configPath(name)
    return ConfigFolder .. "/" .. cleanProfileName(name) .. ".json"
end

local function encodeSelection(set)
    local out = {}
    for key, enabled in pairs(set or {}) do
        if enabled then
            out[#out + 1] = key
        end
    end
    table.sort(out)
    return out
end

local function configSnapshot()
    return {
        SelectedNPCs = encodeSelection(State.SelectedNPCs),
        FarmHeight = State.FarmHeight,
        FarmOffset = State.FarmOffset,
        AutoFarm = State.AutoFarm,
        SelectedIsland = State.SelectedIsland,
        AutoReturn = State.AutoReturn,
        ReturnPosition = cframeToArray(State.ReturnPosition),
        AutoDungeon = State.AutoDungeon,
        AutoTrial = State.AutoTrial,
        SelectedStar = State.SelectedStar,
        AutoStars = State.AutoStars,
        SelectedGacha = State.SelectedGacha,
        AutoGacha = State.AutoGacha,
        AutoEquipBest = State.AutoEquipBest,
        AntiAFK = State.AntiAFK,
        AutoRejoin = State.AutoRejoin,
        AutoCloseUI = State.AutoCloseUI,
        AutoExecute = State.AutoExecute,
        AutoClaimLevel = State.AutoClaimLevel,
        SelectedFighters = encodeSelection(State.SelectedFighters),
        TraitTargets = encodeSelection(State.TraitTargets),
        AutoTraits = State.AutoTraits,
        SelectedUpgrades = encodeSelection(State.SelectedUpgrades),
        AutoUpgrade = State.AutoUpgrade,
        AutoLoadConfig = State.AutoLoadConfig,
    }
end

local function setFromArray(target, values)
    table.clear(target)
    if type(values) ~= "table" then
        return
    end
    for _, value in ipairs(values) do
        if type(value) == "string" then
            target[value] = true
        end
    end
end

local function valuesForLabels(values)
    local out = {}
    if type(values) == "table" then
        for _, value in ipairs(values) do
            if type(value) == "string" then
                out[value] = true
            end
        end
    end
    return out
end

local function setControl(key, value)
    local control = Controls[key]
    if control and control.SetValue then
        pcall(function()
            control:SetValue(value)
        end)
    end
end

local function applyConfig(data)
    if type(data) ~= "table" then
        return false
    end
    if type(data.FarmHeight) == "number" then setControl("FarmHeight", data.FarmHeight) end
    if type(data.FarmOffset) == "number" then setControl("FarmOffset", data.FarmOffset) end
    if type(data.SelectedNPCs) == "table" then setControl("NPCs", valuesForLabels(data.SelectedNPCs)) end
    if type(data.AutoFarm) == "boolean" then setControl("AutoFarm", data.AutoFarm) end
    if type(data.SelectedIsland) == "string" then setControl("Island", data.SelectedIsland) end
    if type(data.AutoReturn) == "boolean" then setControl("AutoReturn", data.AutoReturn) end
    local cf = arrayToCFrame(data.ReturnPosition)
    if cf then State.ReturnPosition = cf end
    if type(data.AutoDungeon) == "boolean" then setControl("AutoDungeon", data.AutoDungeon) end
    if type(data.AutoTrial) == "boolean" then setControl("AutoTrial", data.AutoTrial) end
    if type(data.SelectedStar) == "string" then setControl("Star", data.SelectedStar) end
    if type(data.AutoStars) == "boolean" then setControl("AutoStars", data.AutoStars) end
    if type(data.SelectedGacha) == "string" then setControl("Gacha", data.SelectedGacha) end
    if type(data.AutoGacha) == "boolean" then setControl("AutoGacha", data.AutoGacha) end
    if type(data.AutoEquipBest) == "boolean" then setControl("AutoEquipBest", data.AutoEquipBest) end
    if type(data.AntiAFK) == "boolean" then setControl("AntiAFK", data.AntiAFK) end
    if type(data.AutoRejoin) == "boolean" then setControl("AutoRejoin", data.AutoRejoin) end
    if type(data.AutoCloseUI) == "boolean" then setControl("AutoCloseUI", data.AutoCloseUI) end
    if type(data.AutoExecute) == "boolean" then setControl("AutoExecute", data.AutoExecute) end
    if type(data.AutoClaimLevel) == "boolean" then setControl("AutoClaimLevel", data.AutoClaimLevel) end
    if type(data.TraitTargets) == "table" then setControl("TraitTargets", valuesForLabels(data.TraitTargets)) end
    if type(data.SelectedFighters) == "table" then
        local selectedLabels = {}
        for label, id in pairs(FighterLookup) do
            for _, selectedId in ipairs(data.SelectedFighters) do
                if id == selectedId then
                    selectedLabels[label] = true
                    break
                end
            end
        end
        setControl("Fighters", selectedLabels)
    end
    if type(data.AutoTraits) == "boolean" then setControl("AutoTraits", data.AutoTraits) end
    if type(data.SelectedUpgrades) == "table" then setControl("Upgrades", valuesForLabels(data.SelectedUpgrades)) end
    if type(data.AutoUpgrade) == "boolean" then setControl("AutoUpgrade", data.AutoUpgrade) end
    if type(data.AutoLoadConfig) == "boolean" then setControl("AutoLoadConfig", data.AutoLoadConfig) end
    return true
end

local function saveConfig(name)
    if not ensureConfigFolder() then
        notify("Executor sem suporte a arquivos de configuração")
        return false
    end
    name = cleanProfileName(name or State.ProfileName)
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, configSnapshot())
    if not ok then
        notify("Falha ao montar configuração")
        return false
    end
    local wrote = pcall(writefile, configPath(name), encoded)
    if not wrote then
        notify("Falha ao salvar configuração")
        return false
    end
    State.ActiveProfile = name
    State.ProfileName = name
    if State.AutoLoadConfig then
        pcall(writefile, AutoloadPath, HttpService:JSONEncode({Profile = name}))
    end
    notify("Configuração salva: " .. name)
    return true
end

local function loadConfig(name, silent)
    if not ensureConfigFolder() then
        if not silent then notify("Executor sem suporte a arquivos de configuração") end
        return false
    end
    name = cleanProfileName(name or State.ProfileName)
    local path = configPath(name)
    if not isfile(path) then
        if not silent then notify("Configuração não encontrada: " .. name) end
        return false
    end
    local okRead, raw = pcall(readfile, path)
    if not okRead or type(raw) ~= "string" then
        if not silent then notify("Falha ao ler configuração") end
        return false
    end
    local okDecode, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not okDecode or type(data) ~= "table" then
        if not silent then notify("Configuração inválida") end
        return false
    end
    applyConfig(data)
    State.ActiveProfile = name
    State.ProfileName = name
    if Controls.ProfileName and Controls.ProfileName.SetValue then
        pcall(function() Controls.ProfileName:SetValue(name) end)
    end
    if not silent then notify("Configuração carregada: " .. name) end
    return true
end

local function listConfigs()
    local names = {}
    if ensureConfigFolder() and type(listfiles) == "function" then
        local ok, files = pcall(listfiles, ConfigFolder)
        if ok and type(files) == "table" then
            for _, path in ipairs(files) do
                local normalized = tostring(path):gsub("\\", "/")
                local name = normalized:match("/([^/]+)%.json$")
                if name then
                    names[#names + 1] = name
                end
            end
        end
    end
    table.sort(names)
    return names
end

local function refreshConfigs(force)
    local names = listConfigs()
    local signature = table.concat(names, "|")
    if force or signature ~= LastConfigSignature then
        LastConfigSignature = signature
        ConfigLookup = {}
        for _, name in ipairs(names) do ConfigLookup[name] = true end
        if Controls.ConfigProfiles and Controls.ConfigProfiles.SetValues then
            pcall(function()
                Controls.ConfigProfiles:SetValues(names)
                if State.ActiveProfile and ConfigLookup[State.ActiveProfile] then
                    Controls.ConfigProfiles:SetValue(State.ActiveProfile)
                end
            end)
        end
    end
    return names
end

local FarmStatus
local GamemodeStatus
local StarsStatus
local GachaStatus
local TraitsStatus
local UpgradeStatus
local ConfigStatus

local Window = Fluent:CreateWindow({
    Title = "CAT EMPIRE",
    SubTitle = "Automation",
    TabWidth = 150,
    Size = UDim2.fromOffset(780, 500),
    Acrylic = true,
    Animated = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
    ScreenGuiName = "CAT_EMPIRE_GAME_106",
})
WindowRef = Window

local Tabs = {
    Farm = Window:AddTab({Title = "Farm", Icon = "solar/target-bold"}),
    Travel = Window:AddTab({Title = "Travel", Icon = "solar/map-point-bold"}),
    Modes = Window:AddTab({Title = "Dungeons", Icon = "solar/shield-bold"}),
    Stars = Window:AddTab({Title = "Stars", Icon = "solar/stars-bold"}),
    Gacha = Window:AddTab({Title = "Gachas", Icon = "solar/widget-4-bold"}),
    Team = Window:AddTab({Title = "Team", Icon = "solar/users-group-rounded-bold"}),
    Traits = Window:AddTab({Title = "Traits", Icon = "solar/magic-stick-3-bold"}),
    Upgrade = Window:AddTab({Title = "Upgrades", Icon = "solar/graph-up-bold"}),
    Rewards = Window:AddTab({Title = "Rewards", Icon = "solar/gift-bold"}),
    Settings = Window:AddTab({Title = "Settings", Icon = "solar/settings-bold"}),
    Configs = Window:AddTab({Title = "Configs", Icon = "solar/diskette-bold"}),
}

FarmStatus = Tabs.Farm:AddParagraph({Title = "Auto Farm", Content = "Selecione os NPCs"})
Controls.NPCs = Tabs.Farm:AddDropdown("CE106_NPCs", {
    Title = "NPCs",
    Values = {},
    Multi = true,
    Default = {},
    DropdownOutsideWindow = true,
    Callback = function(value)
        table.clear(State.SelectedNPCs)
        if type(value) == "table" then
            for key, item in pairs(value) do
                if type(key) == "string" and item == true then
                    State.SelectedNPCs[key] = true
                elseif type(item) == "string" then
                    State.SelectedNPCs[item] = true
                end
            end
        elseif type(value) == "string" then
            State.SelectedNPCs[value] = true
        end
    end,
})
Tabs.Farm:AddButton({
    Title = "Refresh NPCs",
    Icon = "solar/refresh-bold",
    Callback = function()
        local values = refreshNPCs(true)
        notify(string.format("%d NPCs disponíveis", #values))
    end,
})
Controls.FarmHeight = Tabs.Farm:AddSlider("CE106_FarmHeight", {
    Title = "Farm Height",
    Default = 5,
    Min = 0,
    Max = 15,
    Rounding = 1,
    Callback = function(value)
        State.FarmHeight = tonumber(value) or 5
    end,
})
Controls.FarmOffset = Tabs.Farm:AddSlider("CE106_FarmOffset", {
    Title = "Farm Distance",
    Default = 2,
    Min = -8,
    Max = 8,
    Rounding = 1,
    Callback = function(value)
        State.FarmOffset = tonumber(value) or 2
    end,
})
Controls.AutoFarm = Tabs.Farm:AddToggle("CE106_AutoFarm", {
    Title = "Auto Farm",
    Default = false,
    Callback = function(value)
        State.AutoFarm = value == true
        if State.AutoFarm and next(State.SelectedNPCs) == nil then
            notify("Selecione pelo menos um NPC")
        end
    end,
})

local mapValues = orderedMaps()
State.SelectedIsland = mapValues[1]
Controls.Island = Tabs.Travel:AddDropdown("CE106_Island", {
    Title = "Island",
    Values = mapValues,
    Default = State.SelectedIsland,
    DropdownOutsideWindow = true,
    Callback = function(value)
        State.SelectedIsland = value
    end,
})
Tabs.Travel:AddButton({
    Title = "Teleport Island",
    Icon = "solar/map-arrow-right-bold",
    Callback = function()
        if State.SelectedIsland then
            teleportMap(State.SelectedIsland)
        end
    end,
})
Tabs.Travel:AddSection("Position")
Tabs.Travel:AddButton({
    Title = "Set Position",
    Icon = "solar/map-point-add-bold",
    Callback = savePosition,
})
Tabs.Travel:AddButton({
    Title = "Return Position",
    Icon = "solar/rewind-back-bold",
    Callback = function()
        if not returnPosition() then
            notify("Nenhuma posição salva")
        end
    end,
})
Controls.AutoReturn = Tabs.Travel:AddToggle("CE106_AutoReturn", {
    Title = "Auto Return Position",
    Default = false,
    Callback = function(value)
        State.AutoReturn = value == true
    end,
})

GamemodeStatus = Tabs.Modes:AddParagraph({Title = "Dungeons / Trial", Content = "Aguardando"})
Controls.AutoDungeon = Tabs.Modes:AddToggle("CE106_AutoDungeon", {
    Title = "Auto Dungeons",
    Default = false,
    Callback = function(value)
        State.AutoDungeon = value == true
        State.LastJoinCheck.Dungeon = 0
    end,
})
Controls.AutoTrial = Tabs.Modes:AddToggle("CE106_AutoTrial", {
    Title = "Auto Trial",
    Default = false,
    Callback = function(value)
        State.AutoTrial = value == true
        State.LastJoinCheck.Trial = 0
    end,
})
Tabs.Modes:AddParagraph({
    Title = "Combat",
    Content = "Quando entrar, o script teleporta nos NPCs e executa o combate automaticamente.",
})

local starValues = orderedStars()
State.SelectedStar = starValues[1]
StarsStatus = Tabs.Stars:AddParagraph({Title = "Stars", Content = "Selecione uma Star"})
Controls.Star = Tabs.Stars:AddDropdown("CE106_Star", {
    Title = "Star",
    Values = starValues,
    Default = State.SelectedStar,
    DropdownOutsideWindow = true,
    Callback = function(value)
        State.SelectedStar = value
        State.NextStarRoll = 0
    end,
})
Controls.AutoStars = Tabs.Stars:AddToggle("CE106_AutoStars", {
    Title = "Auto Open Stars",
    Default = false,
    Callback = function(value)
        State.AutoStars = value == true
        State.NextStarRoll = 0
        if State.AutoStars and State.AutoGacha then
            setControl("AutoGacha", false)
        end
    end,
})
Tabs.Stars:AddButton({
    Title = "Open Now",
    Icon = "solar/stars-bold",
    Callback = function()
        State.NextStarRoll = 0
        task.spawn(starStep)
    end,
})

local gachaValues = orderedGachas()
State.SelectedGacha = gachaValues[1]
GachaStatus = Tabs.Gacha:AddParagraph({Title = "Power Gachas", Content = "Selecione a máquina"})
Controls.Gacha = Tabs.Gacha:AddDropdown("CE106_Gacha", {
    Title = "Machine",
    Values = gachaValues,
    Default = State.SelectedGacha,
    DropdownOutsideWindow = true,
    Callback = function(value)
        State.SelectedGacha = value
        State.NextGachaRoll = 0
    end,
})
Controls.AutoGacha = Tabs.Gacha:AddToggle("CE106_AutoGacha", {
    Title = "Auto Gachas",
    Default = false,
    Callback = function(value)
        State.AutoGacha = value == true
        State.NextGachaRoll = 0
        if State.AutoGacha and State.AutoStars then
            setControl("AutoStars", false)
        end
    end,
})
Tabs.Gacha:AddButton({
    Title = "Roll Now",
    Icon = "solar/refresh-bold",
    Callback = function()
        State.NextGachaRoll = 0
        task.spawn(gachaStep)
    end,
})

Tabs.Team:AddParagraph({
    Title = "Best Team",
    Content = "Mantém os melhores Fighters e a melhor Weapon equipados.",
})
Tabs.Team:AddButton({
    Title = "Equip Best Now",
    Icon = "solar/cup-star-bold",
    Callback = function()
        task.spawn(equipBest)
    end,
})
Controls.AutoEquipBest = Tabs.Team:AddToggle("CE106_AutoEquipBest", {
    Title = "Auto Equip Best Fighters And Weapons",
    Default = false,
    Callback = function(value)
        State.AutoEquipBest = value == true
        State.LastBestEquip = 0
    end,
})

TraitsStatus = Tabs.Traits:AddParagraph({Title = "Auto Traits", Content = "Selecione Fighters e Traits"})
Controls.Fighters = Tabs.Traits:AddDropdown("CE106_Fighters", {
    Title = "Fighters",
    Values = {},
    Multi = true,
    Default = {},
    DropdownOutsideWindow = true,
    Callback = function(value)
        table.clear(State.SelectedFighters)
        if type(value) == "table" then
            for key, item in pairs(value) do
                local label
                local enabled = true
                if type(key) == "string" then
                    label = key
                    enabled = item == true
                elseif type(item) == "string" then
                    label = item
                end
                local id = enabled and label and FighterLookup[label]
                if id then State.SelectedFighters[id] = true end
            end
        elseif type(value) == "string" and FighterLookup[value] then
            State.SelectedFighters[FighterLookup[value]] = true
        end
        State.NextTraitRoll = 0
    end,
})
Tabs.Traits:AddButton({
    Title = "Refresh Fighters",
    Icon = "solar/refresh-bold",
    Callback = function()
        refreshFighters(true)
    end,
})
Controls.TraitTargets = Tabs.Traits:AddDropdown("CE106_TraitTargets", {
    Title = "Wanted Traits",
    Values = orderedTraits(),
    Multi = true,
    Default = {},
    DropdownOutsideWindow = true,
    Callback = function(value)
        table.clear(State.TraitTargets)
        if type(value) == "table" then
            for key, item in pairs(value) do
                if type(key) == "string" and item == true then
                    State.TraitTargets[key] = true
                elseif type(item) == "string" then
                    State.TraitTargets[item] = true
                end
            end
        elseif type(value) == "string" then
            State.TraitTargets[value] = true
        end
        State.NextTraitRoll = 0
    end,
})
Controls.AutoTraits = Tabs.Traits:AddToggle("CE106_AutoTraits", {
    Title = "Auto Traits",
    Default = false,
    Callback = function(value)
        State.AutoTraits = value == true
        State.NextTraitRoll = 0
        State.TraitCursor = 0
    end,
})

UpgradeStatus = Tabs.Upgrade:AddParagraph({Title = "Adventures Upgrade", Content = "Selecione os upgrades"})
Controls.Upgrades = Tabs.Upgrade:AddDropdown("CE106_Upgrades", {
    Title = "Upgrades",
    Values = orderedUpgrades(),
    Multi = true,
    Default = {},
    DropdownOutsideWindow = true,
    Callback = function(value)
        table.clear(State.SelectedUpgrades)
        if type(value) == "table" then
            for key, item in pairs(value) do
                if type(key) == "string" and item == true then
                    State.SelectedUpgrades[key] = true
                elseif type(item) == "string" then
                    State.SelectedUpgrades[item] = true
                end
            end
        elseif type(value) == "string" then
            State.SelectedUpgrades[value] = true
        end
        State.NextUpgrade = 0
    end,
})
Tabs.Upgrade:AddButton({
    Title = "Select All Upgrades",
    Icon = "solar/checklist-minimalistic-bold",
    Callback = function()
        local values = orderedUpgrades()
        local selected = {}
        for _, name in ipairs(values) do selected[name] = true end
        setControl("Upgrades", selected)
    end,
})
Controls.AutoUpgrade = Tabs.Upgrade:AddToggle("CE106_AutoUpgrade", {
    Title = "Auto Adventures Upgrade",
    Default = false,
    Callback = function(value)
        State.AutoUpgrade = value == true
        State.NextUpgrade = 0
    end,
})

Controls.AutoClaimLevel = Tabs.Rewards:AddToggle("CE106_AutoClaimLevel", {
    Title = "Auto Claim Rewards Level",
    Default = false,
    Callback = function(value)
        State.AutoClaimLevel = value == true
        State.LastRewardClaim = 0
    end,
})
Tabs.Rewards:AddButton({
    Title = "Claim Available Now",
    Icon = "solar/gift-bold",
    Callback = function()
        task.spawn(claimLevelRewards)
    end,
})

Tabs.Settings:AddSection("Session")
Controls.AntiAFK = Tabs.Settings:AddToggle("CE106_AntiAFK", {
    Title = "Anti AFK",
    Default = false,
    Callback = function(value)
        State.AntiAFK = value == true
    end,
})
Controls.AutoRejoin = Tabs.Settings:AddToggle("CE106_AutoRejoin", {
    Title = "Auto Rejoin",
    Default = false,
    Callback = function(value)
        State.AutoRejoin = value == true
        if not value then State.RejoinQueued = false end
    end,
})
Controls.AutoCloseUI = Tabs.Settings:AddToggle("CE106_AutoCloseUI", {
    Title = "Auto Close UI",
    Default = false,
    Callback = function(value)
        State.AutoCloseUI = value == true
        applyAnimationVisibility(State.AutoCloseUI)
        if State.AutoCloseUI then closeGameFrames() end
    end,
})
Controls.AutoExecute = Tabs.Settings:AddToggle("CE106_AutoExecute", {
    Title = "Auto Execute",
    Default = false,
    Callback = function(value)
        State.AutoExecute = value == true
        if value then pcall(queueLoader) end
    end,
})
Tabs.Settings:AddSection("Interface")
Tabs.Settings:AddDropdown("CE106_Theme", {
    Title = "Theme",
    Values = Fluent.Themes,
    Default = "Dark",
    DropdownOutsideWindow = true,
    Callback = function(value)
        pcall(function() Fluent:SetTheme(value) end)
    end,
})

ConfigStatus = Tabs.Configs:AddParagraph({Title = "Profiles", Content = "Salve e carregue suas configurações"})
Controls.ProfileName = Tabs.Configs:AddInput("CE106_ProfileName", {
    Title = "Profile Name",
    Default = State.ProfileName,
    Placeholder = "Profile",
    Numeric = false,
    Finished = true,
    Callback = function(value)
        State.ProfileName = cleanProfileName(value)
    end,
})
Controls.ConfigProfiles = Tabs.Configs:AddDropdown("CE106_ConfigProfiles", {
    Title = "Saved Profiles",
    Values = {},
    Default = nil,
    DropdownOutsideWindow = true,
    Callback = function(value)
        if type(value) == "string" and value ~= "" then
            State.ActiveProfile = value
            State.ProfileName = value
            if Controls.ProfileName and Controls.ProfileName.SetValue then
                pcall(function() Controls.ProfileName:SetValue(value) end)
            end
        end
    end,
})
Tabs.Configs:AddButton({
    Title = "Refresh Profiles",
    Icon = "solar/refresh-bold",
    Callback = function()
        refreshConfigs(true)
    end,
})
Tabs.Configs:AddButton({
    Title = "Save Config",
    Icon = "solar/diskette-bold",
    Callback = function()
        if saveConfig(State.ProfileName) then refreshConfigs(true) end
    end,
})
Tabs.Configs:AddButton({
    Title = "Load Profile Config",
    Icon = "solar/folder-open-bold",
    Callback = function()
        loadConfig(State.ActiveProfile or State.ProfileName, false)
    end,
})
Controls.AutoLoadConfig = Tabs.Configs:AddToggle("CE106_AutoLoadConfig", {
    Title = "Auto Load Config",
    Default = false,
    Callback = function(value)
        State.AutoLoadConfig = value == true
        if not ensureConfigFolder() then return end
        if State.AutoLoadConfig then
            local name = State.ActiveProfile or State.ProfileName
            pcall(writefile, AutoloadPath, HttpService:JSONEncode({Profile = cleanProfileName(name)}))
        else
            if type(delfile) == "function" and isfile(AutoloadPath) then
                pcall(delfile, AutoloadPath)
            elseif isfile(AutoloadPath) then
                pcall(writefile, AutoloadPath, HttpService:JSONEncode({}))
            end
        end
    end,
})
Tabs.Configs:AddButton({
    Title = "Unload CAT EMPIRE",
    Icon = "solar/power-bold",
    Callback = function()
        if type(Env.__CE_GAME106_CLEANUP) == "function" then
            Env.__CE_GAME106_CLEANUP()
        end
    end,
})

local function cleanup()
    State.Running = false
    State.AutoFarm = false
    State.AutoDungeon = false
    State.AutoTrial = false
    State.AutoStars = false
    State.AutoGacha = false
    State.AutoTraits = false
    State.AutoUpgrade = false
    pcall(function()
        invoke("General", "Settings", "Set", "Hide Star Animation", OriginalAnimationSettings.Star)
        invoke("General", "Settings", "Set", "Hide Gacha Animation", OriginalAnimationSettings.Gacha)
    end)
    for _, connection in ipairs(Connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(Connections)
    if WindowRef and WindowRef.Destroy then
        pcall(function() WindowRef:Destroy() end)
    elseif Fluent and Fluent.Destroy then
        pcall(function() Fluent:Destroy() end)
    end
    Env.__CE_GAME106_CLEANUP = nil
end
Env.__CE_GAME106_CLEANUP = cleanup

connect(LocalPlayer.Idled, function()
    if not State.AntiAFK then
        return
    end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end)

local errorSignal
pcall(function() errorSignal = GuiService.ErrorMessageChanged end)
if errorSignal then
    connect(errorSignal, function(message)
        if not State.AutoRejoin then return end
        local lower = tostring(message or ""):lower()
        if lower:find("disconnect", 1, true)
            or lower:find("desconect", 1, true)
            or lower:find("connection", 1, true)
            or lower:find("conex", 1, true)
            or lower:find("idle", 1, true)
            or lower:find("inatividade", 1, true)
            or lower:find("error code: 267", 1, true)
            or lower:find("error code: 277", 1, true)
            or lower:find("error code: 279", 1, true)
        then
            requestReconnect()
        end
    end)
end

local promptOverlay
pcall(function()
    local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
    promptOverlay = promptGui and promptGui:FindFirstChild("promptOverlay")
end)
if promptOverlay then
    connect(promptOverlay.ChildAdded, function(child)
        task.delay(0.1, function()
            if not State.AutoRejoin then return end
            local name = tostring(child and child.Name or ""):lower()
            if name:find("errorprompt", 1, true) then requestReconnect() end
        end)
    end)
end

refreshNPCs(true)
refreshFighters(true)
refreshConfigs(true)

if ensureConfigFolder() and isfile(AutoloadPath) then
    local okRead, raw = pcall(readfile, AutoloadPath)
    if okRead and type(raw) == "string" then
        local okDecode, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if okDecode and type(data) == "table" and type(data.Profile) == "string" and data.Profile ~= "" then
            State.AutoLoadConfig = true
            setControl("AutoLoadConfig", true)
            task.defer(function()
                refreshFighters(true)
                loadConfig(data.Profile, true)
                refreshConfigs(true)
                notify("Configuração automática carregada: " .. cleanProfileName(data.Profile))
            end)
        end
    end
end

task.spawn(function()
    local lastNPCRefresh = 0
    local lastFighterRefresh = 0
    local lastClose = 0
    while State.Running do
        local now = os.clock()
        if now - lastNPCRefresh >= 2 then
            lastNPCRefresh = now
            pcall(refreshNPCs, false)
        end
        if now - lastFighterRefresh >= 3 then
            lastFighterRefresh = now
            pcall(refreshFighters, false)
        end
        if State.AutoCloseUI and now - lastClose >= 0.4 then
            lastClose = now
            pcall(closeGameFrames)
        end
        task.wait(0.15)
    end
end)

task.spawn(function()
    while State.Running do
        local active = Omni.Data.Gamemode
        local kind = gamemodeKind(active)
        local inHandledMode = kind == "Dungeon" or kind == "Trial"
        if inHandledMode then
            State.WasInGamemode = true
            pcall(openNearbyDungeonDoors)
            pcall(farmStep, false)
            if kind == "Dungeon" then
                status("mode", GamemodeStatus, "Dungeons / Trial", "Dungeon em execução")
            else
                status("mode", GamemodeStatus, "Dungeons / Trial", "Trial em execução")
            end
        else
            if State.WasInGamemode then
                State.WasInGamemode = false
                if State.AutoReturn and State.ReturnPosition then
                    task.delay(0.5, returnPosition)
                end
            end
            if State.AutoDungeon then
                pcall(tryJoinGamemode, "Dungeon")
                status("mode", GamemodeStatus, "Dungeons / Trial", "Auto Dungeon aguardando entrada")
            end
            if State.AutoTrial then
                pcall(tryJoinGamemode, "Trial")
                if not State.AutoDungeon then
                    status("mode", GamemodeStatus, "Dungeons / Trial", "Auto Trial aguardando entrada")
                end
            end
            if not State.AutoDungeon and not State.AutoTrial then
                status("mode", GamemodeStatus, "Dungeons / Trial", "Aguardando")
            end
            if State.AutoFarm and not State.AutoStars and not State.AutoGacha then
                local ok = pcall(farmStep, true)
                if next(State.SelectedNPCs) == nil then
                    status("farm", FarmStatus, "Auto Farm", "Selecione os NPCs")
                elseif ok then
                    status("farm", FarmStatus, "Auto Farm", "Farm ativo")
                end
            elseif not State.AutoFarm then
                status("farm", FarmStatus, "Auto Farm", "Parado")
            end
        end
        task.wait(0.08)
    end
end)

task.spawn(function()
    while State.Running do
        if State.AutoStars then
            local ok, did = pcall(starStep)
            if ok and did then
                status("stars", StarsStatus, "Stars", "Auto Stars ativo: " .. tostring(State.SelectedStar or ""))
            end
        else
            status("stars", StarsStatus, "Stars", "Selecione uma Star")
        end
        task.wait(0.08)
    end
end)

task.spawn(function()
    while State.Running do
        if State.AutoGacha then
            local ok, did = pcall(gachaStep)
            if ok and did then
                status("gacha", GachaStatus, "Power Gachas", "Auto Gacha ativo: " .. tostring(State.SelectedGacha or ""))
            end
        else
            status("gacha", GachaStatus, "Power Gachas", "Selecione a máquina")
        end
        task.wait(0.08)
    end
end)

task.spawn(function()
    while State.Running do
        local now = os.clock()
        if State.AutoEquipBest and now - State.LastBestEquip >= 4 then
            State.LastBestEquip = now
            pcall(equipBest)
        end
        if State.AutoClaimLevel and now - State.LastRewardClaim >= 3 then
            State.LastRewardClaim = now
            pcall(claimLevelRewards)
        end
        task.wait(0.2)
    end
end)

task.spawn(function()
    while State.Running do
        if State.AutoTraits then
            local ok, did = pcall(traitStep)
            if ok and did then
                status("traits", TraitsStatus, "Auto Traits", "Procurando Trait selecionado")
            elseif next(State.TraitTargets) == nil then
                status("traits", TraitsStatus, "Auto Traits", "Selecione pelo menos um Trait")            elseif #selectedFighterIds() == 0 then
                status("traits", TraitsStatus, "Auto Traits", "Selecione pelo menos um Fighter")
            end
        else
            status("traits", TraitsStatus, "Auto Traits", "Parado")
        end
        task.wait(0.08)
    end
end)

task.spawn(function()
    while State.Running do
        if State.AutoUpgrade then
            local ok, did = pcall(upgradeStep)
            if ok and did then
                status("upgrade", UpgradeStatus, "Adventures Upgrade", "Upgrade automático ativo")
            elseif next(State.SelectedUpgrades) == nil then
                status("upgrade", UpgradeStatus, "Adventures Upgrade", "Selecione os upgrades")
            end
        else
            status("upgrade", UpgradeStatus, "Adventures Upgrade", "Parado")
        end
        task.wait(0.1)
    end
end)

Fluent:Notify({
    Title = "CAT EMPIRE",
    Content = "Automation loaded",
    Duration = 3,
})