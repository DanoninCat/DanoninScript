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
local StateManager
pcall(function()
    StateManager = require(ReplicatedStorage:WaitForChild("Omni"):WaitForChild("Utils"):WaitForChild("StateManager"))
end)
local Env = (getgenv and getgenv()) or _G
local LOADER_COMMAND = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Loader/Loader.lua", true))()]]

if type(Env.__CE_GAME106_CLEANUP) == "function" then
    pcall(Env.__CE_GAME106_CLEANUP)
end
Env.__CE_GAME106_LAST_UI_ERROR = nil

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
    FarmTarget = nil,
    FarmTargetTeleported = false,
    FarmTargetEngaged = false,
    FarmTargetKey = nil,
    FarmLastAttack = 0,
    AutoQuestWorlds = false,
    QuestTarget = nil,
    QuestTargetTeleported = false,
    QuestTargetEngaged = false,
    NextQuestAction = 0,
    QuestStartIndex = nil,
    SelectedIsland = nil,
    ReturnPosition = nil,
    AutoReturn = false,
    PendingAutoReturn = false,
    AutoDungeon = false,
    AutoTrial = false,
    AutoLeaveWave = false,
    LeaveWave = 10,
    LeaveTriggeredSession = nil,
    WasInGamemode = false,
    LastJoinCheck = {Dungeon = 0, Trial = 0},
    LastDoorScan = 0,
    SelectedStar = nil,
    AutoStars = false,
    StarRequest = 0,
    NextStarRoll = 0,
    StarNativeRequestedAt = 0,
    SelectedGacha = nil,
    AutoGacha = false,
    GachaRequest = 0,
    NextGachaRoll = 0,
    GachaNativeName = nil,
    AutoEquipBest = false,
    LastBestEquip = 0,
    AntiAFK = false,
    AutoRejoin = false,
    AutoCloseUI = true,
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
    CoreWorkersStarted = false,
}

local Connections = {}
local WindowRef
local ScriptWindowAutoClosed = false
local Controls = {}
local FighterLookup = {}
local ConfigLookup = {}
local LastNPCSignature = ""
local LastFighterSignature = ""
local LastConfigSignature = ""
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
    local maps = Omni.Data and Omni.Data.Maps
    local name = type(maps) == "table" and maps.Current or nil
    if type(name) == "string" and name ~= "" and Omni.Shared.Maps and Omni.Shared.Maps.List and Omni.Shared.Maps.List[name] then
        return name
    end
    return nil
end

local function waitForCurrentMap(timeout)
    local deadline = os.clock() + (timeout or 12)
    repeat
        local name = currentMap()
        if name then
            return name
        end
        task.wait(0.1)
    until not State.Running or os.clock() >= deadline
    return currentMap()
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
    local ok, result = invoke("General", "Maps", "Teleport", name)
    if ok and result == true then
        return true
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

local function ensureMapEnemyDefinitions(mapName)
    if type(mapName) ~= "string" or mapName == "" then
        return
    end
    local sharedEnemies = Omni.Shared.Enemies and Omni.Shared.Enemies.List
    if type(sharedEnemies) == "table" and type(sharedEnemies[mapName]) == "table" and next(sharedEnemies[mapName]) ~= nil then
        return
    end
    pcall(function()
        local omniFolder = ReplicatedStorage:FindFirstChild("Omni")
        local sharedFolder = omniFolder and omniFolder:FindFirstChild("Shared")
        local mapsFolder = sharedFolder and sharedFolder:FindFirstChild("Maps")
        local mapFolder = mapsFolder and mapsFolder:FindFirstChild(mapName)
        local enemiesModule = mapFolder and mapFolder:FindFirstChild("Enemies")
        if enemiesModule and enemiesModule:IsA("ModuleScript") then
            require(enemiesModule)
        end
    end)
end

local function recheckNativeEnemies()
    pcall(function()
        local renderer = Omni.Scripts and Omni.Scripts.Rendering and Omni.Scripts.Rendering.Enemies
        if renderer and type(renderer.Recheck) == "function" then
            renderer.Recheck()
        end
    end)
end

local function refreshNPCs(force)
    local here = currentMap()
    if not here then
        if force then
            task.spawn(function()
                local resolved = waitForCurrentMap(15)
                if resolved and State.Running then
                    ensureMapEnemyDefinitions(resolved)
                    recheckNativeEnemies()
                    task.wait()
                    refreshNPCs(true)
                end
            end)
        end
        return {}
    end

    ensureMapEnemyDefinitions(here)
    if force then
        recheckNativeEnemies()
    end

    local names = {}
    local seen = {}
    local function addName(name)
        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end

    local sharedEnemies = Omni.Shared.Enemies and Omni.Shared.Enemies.List or {}
    local mapEnemies = sharedEnemies[here]
    if type(mapEnemies) == "table" then
        for name, info in pairs(mapEnemies) do
            if type(info) == "table" then
                addName(name)
            end
        end
    end

    local main = Omni.Shared.Quests and Omni.Shared.Quests.List and Omni.Shared.Quests.List.Main
    local questInfo = main and main.List and main.List[here]
    if type(questInfo) == "table" and type(questInfo.Missions) == "table" then
        for _, mission in ipairs(questInfo.Missions) do
            if type(mission) == "table" and mission.Type == "Kill" then
                addName(mission.Name)
            end
        end
    end

    for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
        if enemy:IsA("BasePart") and enemy:GetAttribute("SessionID") == nil and enemy:GetAttribute("MapName") == here then
            addName(enemyName(enemy))
        end
    end

    table.sort(names)
    for name in pairs(State.SelectedNPCs) do
        if not seen[name] then
            State.SelectedNPCs[name] = nil
        end
    end

    local signature = here .. "|" .. table.concat(names, "|")
    if force or signature ~= LastNPCSignature then
        LastNPCSignature = signature
        State.FarmTarget = nil
        State.FarmTargetTeleported = false
        State.FarmTargetEngaged = false
        State.FarmTargetKey = nil
        State.FarmLastAttack = 0
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
                dropdown:SetValue({})
                if next(selected) ~= nil then
                    dropdown:SetValue(selected)
                end
            end)
        end
    end
    return names
end

local function isSelectedNPC(name)
    return next(State.SelectedNPCs) ~= nil and State.SelectedNPCs[name] == true
end

local function syncNPCSelectionFromControl()
    local control = Controls.NPCs
    local value = control and control.Value
    if type(value) ~= "table" and type(value) ~= "string" then
        return
    end
    table.clear(State.SelectedNPCs)
    if type(value) == "string" then
        if value ~= "" then
            State.SelectedNPCs[value] = true
        end
        return
    end
    for key, item in pairs(value) do
        if type(key) == "string" and item == true then
            State.SelectedNPCs[key] = true
        elseif type(item) == "string" then
            State.SelectedNPCs[item] = true
        end
    end
end

local function selectedStarName()
    local control = Controls.Star
    local value = control and control.Value
    if type(value) == "string" and value ~= "" then
        State.SelectedStar = value
    end
    return State.SelectedStar
end

local function selectedGachaName()
    local control = Controls.Gacha
    local value = control and control.Value
    if type(value) == "string" and value ~= "" then
        State.SelectedGacha = value
    end
    return State.SelectedGacha
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

local function enemyValid(enemy, useSelection, wantedName)
    if not enemy or not enemy.Parent or not enemy:IsA("BasePart") or not enemy:IsDescendantOf(workspace) then
        return false
    end
    if enemy:GetAttribute("Died") == true then
        return false
    end
    local data = enemy:FindFirstChild("Data")
    local health = data and data:FindFirstChild("Health")
    if health and tonumber(health.Value) and health.Value <= 0 then
        return false
    end
    local active = Omni.Data.Gamemode
    local session = Omni.Data.GamemodeSession
    if type(active) == "string" and active ~= "" and session ~= nil and session ~= "" then
        if enemy:GetAttribute("SessionID") ~= session or enemy:GetAttribute("Gamemode") ~= active then
            return false
        end
    else
        if enemy:GetAttribute("SessionID") ~= nil or enemy:GetAttribute("MapName") ~= currentMap() then
            return false
        end
    end
    local name = enemyName(enemy)
    if not name then
        return false
    end
    if type(wantedName) == "string" and wantedName ~= "" then
        return name == wantedName
    end
    if useSelection then
        return isSelectedNPC(name)
    end
    return true
end

local function findEnemy(useSelection, wantedName)
    local root = getRoot()
    if not root then
        return nil
    end
    local best, bestDistance
    for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
        if enemyValid(enemy, useSelection, wantedName) then
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
    return best
end

local function fightersAssignedToEnemy(id)
    if type(id) ~= "string" or id == "" then
        return false
    end
    local okTargets, targets = pcall(function()
        return Omni.Utils.PlayerStats.GetFighterTargets(Omni.Data, Omni.Instance)
    end)
    if not okTargets or type(targets) ~= "table" then
        return false
    end
    for _, targetId in pairs(targets) do
        if targetId == id then
            return true
        end
    end
    return false
end

local function attackEnemy(enemy, teleportOnce)
    if not enemyValid(enemy, false, nil) then
        return false
    end
    local id = enemy:GetAttribute("EnemyID")
    if type(id) ~= "string" or id == "" then
        return false
    end
    if enemy:GetAttribute("Shielded") == true then
        return false
    end
    local cf = getEnemyPosition(enemy)
    local root = getRoot()
    if teleportOnce and root and cf then
        root.CFrame = cf * CFrame.new(0, 0, 3)
        task.wait(0.18)
    end
    if fightersAssignedToEnemy(id) then
        return true
    end
    local okAvailable, available = pcall(function()
        return Omni.Utils.PlayerStats.GetAvailableFightersForTarget(id, Omni.Data, Omni.Instance)
    end)
    if not okAvailable or type(available) ~= "table" or next(available) == nil then
        return fightersAssignedToEnemy(id)
    end
    local nativeController
    pcall(function()
        local enemies = Omni.Scripts and Omni.Scripts.Rendering and Omni.Scripts.Rendering.Enemies
        if enemies and type(enemies.Get) == "function" then
            nativeController = enemies.Get(id)
        end
    end)
    if nativeController and type(nativeController.Clicked) == "function" then
        pcall(function()
            nativeController:Clicked()
        end)
    else
        local sending = available
        if not (Omni.Data.Settings and Omni.Data.Settings["Send All Fighters"] == true) then
            sending = {available[1]}
        end
        invoke("General", "Combat", "FighterAttack", id, sending)
    end
    task.wait(0.1)
    if fightersAssignedToEnemy(id) then
        return true
    end
    local sending = available
    if not (Omni.Data.Settings and Omni.Data.Settings["Send All Fighters"] == true) then
        sending = {available[1]}
    end
    invoke("General", "Combat", "FighterAttack", id, sending)
    task.wait(0.1)
    return fightersAssignedToEnemy(id)
end

local function resetFarmTarget()
    State.FarmTarget = nil
    State.FarmTargetTeleported = false
    State.FarmTargetEngaged = false
    State.FarmTargetKey = nil
    State.FarmLastAttack = 0
end

local function farmStep(useSelection, wantedName)
    if useSelection then
        syncNPCSelectionFromControl()
        if next(State.SelectedNPCs) == nil then
            return false
        end
    end
    local key = type(wantedName) == "string" and ("quest:" .. wantedName) or (useSelection and "selected" or "all")
    if State.FarmTargetKey ~= key then
        resetFarmTarget()
        State.FarmTargetKey = key
    end
    local target = State.FarmTarget
    if not enemyValid(target, useSelection, wantedName) then
        local keepKey = State.FarmTargetKey
        resetFarmTarget()
        State.FarmTargetKey = keepKey
        target = findEnemy(useSelection, wantedName)
        if target then
            State.FarmTarget = target
        end
    end
    if not target then
        return false
    end
    local id = target:GetAttribute("EnemyID")
    if State.FarmTargetEngaged then
        if fightersAssignedToEnemy(id) then
            return true
        end
        if os.clock() - State.FarmLastAttack < 1 then
            return true
        end
        State.FarmTargetEngaged = false
    end
    local firstAttack = State.FarmTargetTeleported ~= true
    local attacked = attackEnemy(target, firstAttack)
    if firstAttack then
        State.FarmTargetTeleported = true
    end
    State.FarmLastAttack = os.clock()
    if attacked then
        State.FarmTargetEngaged = true
    end
    if not enemyValid(target, useSelection, wantedName) then
        local keepKey = State.FarmTargetKey
        resetFarmTarget()
        State.FarmTargetKey = keepKey
    end
    return attacked
end

local function orderedWorldQuests()
    local rows = {}
    local main = Omni.Shared.Quests and Omni.Shared.Quests.List and Omni.Shared.Quests.List.Main
    local list = main and main.List
    if type(list) ~= "table" then
        return rows
    end
    for name, info in pairs(list) do
        if type(name) == "string" and type(info) == "table" then
            rows[#rows + 1] = {
                Name = name,
                Info = info,
                Index = tonumber(info.Index) or 9999,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.Index == b.Index then
            return a.Name < b.Name
        end
        return a.Index < b.Index
    end)
    return rows
end

local function getQuestRuntime(name)
    local quests = Omni.Data.Quests
    local classes = type(quests) == "table" and quests.List or nil
    local main = type(classes) == "table" and classes.Main or nil
    local list = type(main) == "table" and main.List or nil
    return type(list) == "table" and list[name] or nil
end

local function resetQuestTarget()
    resetFarmTarget()
end

local function questFarmEnemy(name)
    return farmStep(false, name)
end

local function setAutoQuestWorlds(enabled)
    State.AutoQuestWorlds = enabled == true
    State.NextQuestAction = 0
    State.QuestStartIndex = nil
    resetFarmTarget()
    if not State.AutoQuestWorlds then
        return
    end
    local here = currentMap()
    local mapInfo = here and Omni.Shared.Maps and Omni.Shared.Maps.List and Omni.Shared.Maps.List[here]
    State.QuestStartIndex = mapInfo and tonumber(mapInfo.Index) or nil
    if State.AutoFarm and Controls.AutoFarm and Controls.AutoFarm.SetValue then
        pcall(function()
            Controls.AutoFarm:SetValue(false)
        end)
    end
end

local function autoQuestWorldStep()
    if not State.AutoQuestWorlds or os.clock() < State.NextQuestAction then
        return false
    end
    local here = currentMap()
    if not here then
        State.NextQuestAction = os.clock() + 0.25
        return false
    end
    if not State.QuestStartIndex then
        local info = Omni.Shared.Maps and Omni.Shared.Maps.List and Omni.Shared.Maps.List[here]
        State.QuestStartIndex = info and tonumber(info.Index) or 1
    end
    local quests = orderedWorldQuests()
    local selected
    for _, quest in ipairs(quests) do
        if quest.Index >= (State.QuestStartIndex or 1) then
            local runtime = getQuestRuntime(quest.Name)
            local completed = type(runtime) == "table" and (runtime.Claimed == true or (tonumber(runtime.Completions) or 0) >= 1)
            if not completed then
                selected = quest
                break
            end
        end
    end
    if not selected then
        State.AutoQuestWorlds = false
        if Controls.AutoQuestWorlds and Controls.AutoQuestWorlds.SetValue then
            pcall(function() Controls.AutoQuestWorlds:SetValue(false) end)
        end
        resetFarmTarget()
        return false
    end
    local questName = selected.Name
    if not ownsMap(questName) then
        State.NextQuestAction = os.clock() + 0.5
        return false
    end
    if currentMap() ~= questName then
        if teleportMap(questName) then
            State.NextQuestAction = os.clock() + 0.8
        else
            State.NextQuestAction = os.clock() + 0.4
        end
        resetFarmTarget()
        return false
    end
    local runtime = getQuestRuntime(questName)
    if not (type(runtime) == "table" and runtime.Available == true) then
        local canCollect = false
        pcall(function()
            canCollect = Omni.Shared.Quests.CanCollectQuest(questName, "Main", Omni.Data) == true
        end)
        if canCollect then
            fire("General", "Quests", "Collect", "Main", questName)
            State.NextQuestAction = os.clock() + 0.45
            resetFarmTarget()
            return true
        end
        State.NextQuestAction = os.clock() + 0.3
        return false
    end
    local progress = 0
    local missionProgress = {}
    pcall(function()
        progress, missionProgress = Omni.Shared.Quests.GetQuestProgress(questName, "Main", Omni.Data)
    end)
    if (tonumber(progress) or 0) >= 1 then
        fire("General", "Quests", "Claim", "Main", questName)
        State.NextQuestAction = os.clock() + 0.7
        resetFarmTarget()
        local nextMap
        pcall(function()
            if Omni.Shared.Maps and type(Omni.Shared.Maps.GetNextMapName) == "function" then
                nextMap = Omni.Shared.Maps.GetNextMapName(selected.Name)
            end
        end)
        if type(nextMap) == "string" then
            task.spawn(function()
                local deadline = os.clock() + 8
                while State.Running and State.AutoQuestWorlds and os.clock() < deadline do
                    if ownsMap(nextMap) then
                        teleportMap(nextMap)
                        break
                    end
                    task.wait(0.2)
                end
            end)
        end
        return true
    end
    local missions = selected.Info.Missions
    if type(missions) ~= "table" then
        State.NextQuestAction = os.clock() + 0.5
        return false
    end
    for index, mission in ipairs(missions) do
        local part = tonumber(missionProgress[index]) or 0
        if part < 1 and type(mission) == "table" and mission.Type == "Kill" and type(mission.Name) == "string" then
            return farmStep(false, mission.Name)
        end
    end
    State.NextQuestAction = os.clock() + 0.25
    return false
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

local function gamemodeCandidates(kind)
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
    return candidates
end

local function tryJoinGamemode(kind)
    local lastCheck = State.LastJoinCheck[kind] or 0
    if os.clock() - lastCheck < 2.5 then
        return false
    end
    State.LastJoinCheck[kind] = os.clock()
    local active = Omni.Data.Gamemode
    if type(active) == "string" and active ~= "" then
        return false
    end
    for _, mode in ipairs(gamemodeCandidates(kind)) do
        if not mode.Info.MapName or ownsMap(mode.Info.MapName) then
            local ok, preview = invoke("General", "Gamemodes", "Preview", mode.Name)
            if ok and type(preview) == "table" and preview.GamemodeName == mode.Name and preview.Status == "Opened" then
                local closesAt = tonumber(preview.EntryClosesAt)
                if not closesAt or workspace:GetServerTimeNow() < closesAt then
                    local joinedOk, joined = invoke("General", "Gamemodes", "Join", mode.Name)
                    return joinedOk and joined ~= false
                end
            end
        end
    end
    return false
end

local function gamemodeKind(name)
    local info = name and Omni.Shared.Gamemodes.List[name]
    return info and info.Type or nil
end

local function getGamemodeState()
    if not StateManager then
        return nil
    end
    local name = Omni.Data.Gamemode
    local session = Omni.Data.GamemodeSession
    local info = type(name) == "string" and Omni.Shared.Gamemodes.List[name] or nil
    if not info or type(session) ~= "string" or session == "" then
        return nil
    end
    local client = workspace:FindFirstChild("Client")
    local maps = client and client:FindFirstChild("Maps")
    local map = maps and maps:FindFirstChild(info.MapName or currentMap() or "")
    local sessions = map and map:FindFirstChild("GamemodeSessions")
    local holder = sessions and sessions:FindFirstChild(session)
    if not holder then
        return nil
    end
    local ok, manager = pcall(StateManager.Get, holder)
    if ok then
        return manager
    end
    return nil
end

local function currentGamemodeProgress(kind)
    local manager = getGamemodeState()
    if not manager or type(manager.GetState) ~= "function" then
        return nil
    end
    local key = kind == "Dungeon" and "RoomsCleared" or "CurrentWave"
    local ok, value = pcall(function()
        return manager:GetState(key)
    end)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

local function autoLeaveGamemode(kind)
    if not State.AutoLeaveWave or (tonumber(State.LeaveWave) or 0) <= 0 then
        return false
    end
    local session = Omni.Data.GamemodeSession
    if type(session) ~= "string" or session == "" or State.LeaveTriggeredSession == session then
        return false
    end
    local progress = currentGamemodeProgress(kind)
    if type(progress) == "number" and progress >= State.LeaveWave then
        State.LeaveTriggeredSession = session
        fire("General", "Gamemodes", "Leave")
        return true
    end
    return false
end

local function starController()
    return Omni.Scripts and Omni.Scripts.Interface and Omni.Scripts.Interface.Stars
end

local function stopNativeStars()
    local controller = starController()
    if not controller then
        return
    end
    if type(controller.CancelAutoRoll) == "function" then
        pcall(controller.CancelAutoRoll)
    end
    if type(controller.CloseUI) == "function" then
        pcall(controller.CloseUI)
    end
end

local function requestNativeStars()
    local name = selectedStarName()
    local info = type(name) == "string" and Omni.Shared.Stars.List[name] or nil
    local controller = starController()
    if not info or not controller then
        return false
    end
    local remoteAccess = Omni.Data.Gamepasses and Omni.Data.Gamepasses["Remote Access"] == true
    if not remoteAccess or not ownsMap(info.MapName) then
        return false
    end
    if type(controller.OpenUI) ~= "function" or type(controller.StartAutoRoll) ~= "function" then
        return false
    end
    State.StarNativeRequestedAt = os.clock()
    local ok = pcall(function()
        controller.OpenUI(name, true)
        controller.StartAutoRoll()
    end)
    if not ok then
        return false
    end
    if type(controller.IsAutoRolling) == "function" then
        local checkOk, active = pcall(controller.IsAutoRolling)
        return checkOk and active == true    end
    return true
end

local function starStep()
    local name = selectedStarName()
    if type(name) ~= "string" or not Omni.Shared.Stars.List[name] or os.clock() < State.NextStarRoll then
        return false
    end
    local controller = State.AutoStars and starController() or nil
    if controller and type(controller.IsAutoRolling) == "function" then
        local ok, active = pcall(controller.IsAutoRolling)
        if ok and active == true then
            State.NextStarRoll = os.clock() + 0.5
            return true
        end
    end
    if State.AutoStars and State.StarNativeRequestedAt <= 0 then
        if requestNativeStars() then
            State.NextStarRoll = os.clock() + 0.5
            return true
        end
        State.StarNativeRequestedAt = os.clock()
    end
    local freeSlots = 1
    pcall(function()
        local _, _, free = Omni.Utils.PlayerStats.FightersInventory(Omni.Data, Omni.Instance)
        freeSlots = free
    end)
    if type(freeSlots) == "number" and freeSlots <= 0 then
        return false
    end
    local cooldown = 3.5
    pcall(function()
        local speed = Omni.Utils.PlayerStats.StarOpenSpeed(Omni.Data, Omni.Instance)
        if type(speed) == "number" and speed > 0 then
            cooldown = 3.5 / speed
        end
    end)
    State.StarRequest = State.StarRequest + 1
    fire("General", "Stars", "Roll", name, 1, State.StarRequest)
    State.NextStarRoll = os.clock() + math.max(0.2, cooldown + 0.08)
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

local function gachaController()
    return Omni.Scripts and Omni.Scripts.Interface and Omni.Scripts.Interface.Gacha
end

local function gachaRollOnce()
    local name = selectedGachaName()
    local info = name and Omni.Shared.Gacha.List[name]
    if not info then
        return false
    end
    local cooldown = 2
    pcall(function()
        cooldown = Omni.Utils.PlayerStats.GachaCooldown(Omni.Data, Omni.Instance, name)
    end)
    State.GachaRequest = State.GachaRequest + 1
    fire("General", "Gacha", "Roll", name, nil, State.GachaRequest)
    State.NextGachaRoll = os.clock() + math.max(0.2, (tonumber(cooldown) or 2) + 0.08)
    return true
end

local function gachaStep()
    local name = selectedGachaName()
    local info = name and Omni.Shared.Gacha.List[name]
    if not info or os.clock() < State.NextGachaRoll then
        return false
    end
    if State.AutoGacha then
        local controller = gachaController()
        if controller and type(controller.Resume) == "function" then
            local ok = pcall(controller.Resume, name)
            if ok then
                State.GachaNativeName = name
                State.NextGachaRoll = os.clock() + 2
                return true
            end
        end
    end
    return gachaRollOnce()
end

local function stopNativeGacha()
    State.GachaNativeName = nil
    local controller = gachaController()
    if controller and type(controller.Stop) == "function" then
        pcall(controller.Stop)
    end
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

local function closeScriptWindow()
    if not State.AutoCloseUI or not WindowRef or ScriptWindowAutoClosed then
        return
    end
    if type(WindowRef.Minimize) == "function" then
        local ok = pcall(function()
            WindowRef:Minimize()
        end)
        if ok then
            ScriptWindowAutoClosed = true
        end
    end
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
                Controls.Fighters:SetValue({})
                if next(selectedLabels) ~= nil then
                    Controls.Fighters:SetValue(selectedLabels)
                end
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
local UPGRADE_VALUES = {
    "Player Damage",
    "Fighter Damage",
    "Yen",
    "Player Exp",
    "Drops",
    "Luck",
    "Gacha Luck",
    "Attack Range",
}

local function upgradeControlKey(name)
    return "Upgrade_" .. tostring(name):gsub("[^%w]", "")
end

local function orderedUpgrades()
    local upgrade = Omni.Shared and Omni.Shared.Upgrade
    local list = type(upgrade) == "table" and upgrade.List or nil
    local system = type(list) == "table" and list[UPGRADE_SYSTEM] or nil
    local rows = {}
    if type(system) == "table" and type(system.Upgrades) == "table" then
        for name, info in pairs(system.Upgrades) do
            if type(name) == "string" and type(info) == "table" then
                rows[#rows + 1] = {Name = name, Index = tonumber(info.Index) or 999}
            end
        end
    end
    if #rows == 0 then
        return table.clone(UPGRADE_VALUES)
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
    local upgrade = Omni.Shared and Omni.Shared.Upgrade
    local list = type(upgrade) == "table" and upgrade.List or nil
    local system = type(list) == "table" and list[UPGRADE_SYSTEM] or nil
    if not system then
        return false
    end
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
            level = upgrade.GetCurrentLevel(UPGRADE_SYSTEM, name, Omni.Data)
        end)
        if level < info.MaxLevel then
            local nextInfo
            pcall(function()
                nextInfo = upgrade.GetLevelInformation(UPGRADE_SYSTEM, name, level + 1)
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

local ConfigRoot = "CAT EMPIRE/Anime Legacy"
local ConfigFolder = ConfigRoot .. "/Profiles"
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
        AutoFarm = State.AutoFarm,
        AutoQuestWorlds = State.AutoQuestWorlds,
        SelectedIsland = State.SelectedIsland,
        AutoReturn = State.AutoReturn,
        ReturnPosition = cframeToArray(State.ReturnPosition),
        AutoDungeon = State.AutoDungeon,
        AutoTrial = State.AutoTrial,
        AutoLeaveWave = State.AutoLeaveWave,
        LeaveWave = State.LeaveWave,
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
    if type(data.SelectedNPCs) == "table" then setControl("NPCs", valuesForLabels(data.SelectedNPCs)) end
    if type(data.AutoFarm) == "boolean" then setControl("AutoFarm", data.AutoFarm) end
    if type(data.AutoQuestWorlds) == "boolean" then setControl("AutoQuestWorlds", data.AutoQuestWorlds) end
    if type(data.SelectedIsland) == "string" then setControl("Island", data.SelectedIsland) end
    if type(data.AutoReturn) == "boolean" then setControl("AutoReturn", data.AutoReturn) end
    local cf = arrayToCFrame(data.ReturnPosition)
    if cf then State.ReturnPosition = cf end
    if type(data.AutoDungeon) == "boolean" then setControl("AutoDungeon", data.AutoDungeon) end
    if type(data.AutoTrial) == "boolean" then setControl("AutoTrial", data.AutoTrial) end
    if type(data.AutoLeaveWave) == "boolean" then setControl("AutoLeaveWave", data.AutoLeaveWave) end
    if type(data.LeaveWave) == "number" then setControl("LeaveWave", tostring(data.LeaveWave)) end
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
    if type(data.SelectedUpgrades) == "table" then
        table.clear(State.SelectedUpgrades)
        local wanted = {}
        for _, name in ipairs(data.SelectedUpgrades) do
            if type(name) == "string" then
                wanted[name] = true
                State.SelectedUpgrades[name] = true
            end
        end
        for _, name in ipairs(UPGRADE_VALUES) do
            setControl(upgradeControlKey(name), wanted[name] == true)
        end
    end
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

local function deleteConfig(name)
    if not ensureConfigFolder() or type(delfile) ~= "function" then
        notify("Executor sem suporte para remover profiles")
        return false
    end
    name = cleanProfileName(name or State.ActiveProfile or State.ProfileName)
    local path = configPath(name)
    if not isfile(path) then
        notify("Profile não encontrado: " .. name)
        return false
    end
    local ok = pcall(delfile, path)
    if not ok then
        notify("Falha ao remover profile")
        return false
    end
    if State.ActiveProfile == name then
        State.ActiveProfile = nil
    end
    if isfile(AutoloadPath) then
        local okRead, raw = pcall(readfile, AutoloadPath)
        if okRead and type(raw) == "string" then
            local okDecode, data = pcall(HttpService.JSONDecode, HttpService, raw)
            if okDecode and type(data) == "table" and data.Profile == name then
                pcall(delfile, AutoloadPath)
                State.AutoLoadConfig = false
                setControl("AutoLoadConfig", false)
            end
        end
    end
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


local function uiSafe(section, callback)
    local ok, result = pcall(callback)
    if not ok then
        Env.__CE_GAME106_LAST_UI_ERROR = {Section = section, Error = tostring(result)}
    end
    return ok, result
end

local Window = Fluent:CreateWindow({
    Title = "CAT EMPIRE",
    SubTitle = "Anime Legacy",
    TabWidth = 150,
    Size = UDim2.fromOffset(780, 500),
    Acrylic = true,
    Animated = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
    ScreenGuiName = "CAT_EMPIRE_ANIME_LEGACY",
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
    Configs = Window:AddTab({Title = "Profiles", Icon = "solar/diskette-bold"}),
}

Controls.NPCs = Tabs.Farm:AddDropdown("CE106_NPCs", {
    Title = "NPCs",
    Values = {},
    Multi = true,
    Default = nil,
    DropdownOutsideWindow = false,
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
        resetFarmTarget()
    end,
})
Tabs.Farm:AddButton({
    Title = "Refresh NPCs",
    Icon = "solar/refresh-bold",
    Callback = function()
        refreshNPCs(true)
    end,
})
Controls.AutoFarm = Tabs.Farm:AddToggle("CE106_AutoFarm", {
    Title = "Auto Farm",
    Default = false,
    Callback = function(value)
        State.AutoFarm = value == true
        resetFarmTarget()
        if State.AutoFarm and State.AutoQuestWorlds and Controls.AutoQuestWorlds and Controls.AutoQuestWorlds.SetValue then
            pcall(function()
                Controls.AutoQuestWorlds:SetValue(false)
            end)
        end
        if State.AutoFarm and next(State.SelectedNPCs) == nil then
            notify("Selecione pelo menos um NPC")
        end
    end,
})
Controls.AutoQuestWorlds = Tabs.Farm:AddToggle("CE106_AutoQuestWorlds", {
    Title = "Auto Quest Worlds",
    Default = false,
    Callback = function(value)
        setAutoQuestWorlds(value == true)
    end,
})

local mapValues = orderedMaps()
State.SelectedIsland = nil
Controls.Island = Tabs.Travel:AddDropdown("CE106_Island", {
    Title = "Island",
    Values = mapValues,
    Default = nil,
    DropdownOutsideWindow = false,
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
Tabs.Modes:AddSection("Return")
Tabs.Modes:AddButton({
    Title = "Save Position",
    Icon = "solar/map-point-add-bold",
    Callback = savePosition,
})
Tabs.Modes:AddButton({
    Title = "Return Position",
    Icon = "solar/rewind-back-bold",
    Callback = function()
        if not returnPosition() then
            notify("Nenhuma posição salva")
        end
    end,
})
Controls.AutoReturn = Tabs.Modes:AddToggle("CE106_AutoReturn", {
    Title = "Auto Return Position",
    Default = false,
    Callback = function(value)
        State.AutoReturn = value == true
        if not State.AutoReturn then
            State.PendingAutoReturn = false
        end
    end,
})
Tabs.Modes:AddSection("Auto Leave")
Controls.LeaveWave = Tabs.Modes:AddInput("CE106_LeaveWave", {
    Title = "Leave At Wave / Room",
    Default = tostring(State.LeaveWave),
    Placeholder = "10",
    Numeric = true,
    Finished = true,
    Callback = function(value)
        State.LeaveWave = math.max(1, math.floor(tonumber(value) or 10))
    end,
})
Controls.AutoLeaveWave = Tabs.Modes:AddToggle("CE106_AutoLeaveWave", {
    Title = "Auto Leave Wave",
    Default = false,
    Callback = function(value)
        State.AutoLeaveWave = value == true
        State.LeaveTriggeredSession = nil
    end,
})
local starValues = orderedStars()
State.SelectedStar = nil
Controls.Star = Tabs.Stars:AddDropdown("CE106_Star", {
    Title = "Star",
    Values = starValues,
    Default = nil,
    DropdownOutsideWindow = false,
    Callback = function(value)
        if State.AutoStars then
            stopNativeStars()
        end
        State.SelectedStar = value
        State.NextStarRoll = 0
        State.StarNativeRequestedAt = 0
        if State.AutoStars and type(value) == "string" then
            task.defer(requestNativeStars)
        end
    end,
})
Controls.AutoStars = Tabs.Stars:AddToggle("CE106_AutoStars", {
    Title = "Auto Open Stars",
    Default = false,
    Callback = function(value)
        State.AutoStars = value == true
        selectedStarName()
        State.NextStarRoll = 0
        State.StarNativeRequestedAt = 0
        if State.AutoStars then
            applyAnimationVisibility(true)
            task.defer(requestNativeStars)
        else
            stopNativeStars()
        end
        if State.AutoStars and State.AutoGacha then
            setControl("AutoGacha", false)
        end    end,
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
State.SelectedGacha = nil
Controls.Gacha = Tabs.Gacha:AddDropdown("CE106_Gacha", {
    Title = "Machine",
    Values = gachaValues,
    Default = nil,
    DropdownOutsideWindow = false,
    Callback = function(value)
        if State.AutoGacha then
            stopNativeGacha()
        end
        State.SelectedGacha = value
        State.NextGachaRoll = 0
        if State.AutoGacha and type(value) == "string" then
            task.defer(gachaStep)
        end
    end,
})
Controls.AutoGacha = Tabs.Gacha:AddToggle("CE106_AutoGacha", {
    Title = "Auto Gachas",
    Default = false,
    Callback = function(value)
        State.AutoGacha = value == true
        selectedGachaName()
        State.NextGachaRoll = 0
        if State.AutoGacha then
            applyAnimationVisibility(true)
            task.defer(gachaStep)
        else
            stopNativeGacha()
        end
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
        task.spawn(gachaRollOnce)
    end,
})

local function startCoreWorkers()
    if State.CoreWorkersStarted then
        return
    end
    State.CoreWorkersStarted = true

    pcall(function()
        local connection = Omni:OnDataChanged({"Maps"}, function()
            task.defer(function()
                resetFarmTarget()
                refreshNPCs(true)
            end)
        end)
        if connection then
            Connections[#Connections + 1] = connection
        end
    end)

    pcall(function()
        local connection = Omni:OnDataChanged({"Quests"}, function()
            if State.AutoQuestWorlds then
                State.NextQuestAction = 0
            end
        end)
        if connection then
            Connections[#Connections + 1] = connection
        end
    end)

    task.spawn(function()
        local mapName = waitForCurrentMap(15)
        if mapName and State.Running then
            ensureMapEnemyDefinitions(mapName)
            recheckNativeEnemies()
            task.wait(0.15)
            refreshNPCs(true)
        end
    end)

    task.spawn(function()
        local lastNPCRefresh = 0
        while State.Running do
            local now = os.clock()
            if now - lastNPCRefresh >= 1 then
                lastNPCRefresh = now
                pcall(refreshNPCs, false)
            end
            task.wait(0.1)
        end
    end)

    task.spawn(function()
        while State.Running do
            local active = Omni.Data.Gamemode
            local kind = gamemodeKind(active)
            local inHandledMode = kind == "Dungeon" or kind == "Trial"
            if inHandledMode then
                State.WasInGamemode = true
                State.PendingAutoReturn = false
                pcall(autoLeaveGamemode, kind)
                if kind == "Dungeon" and State.AutoDungeon then
                    pcall(openNearbyDungeonDoors)
                end
                local enabled = (kind == "Dungeon" and State.AutoDungeon)
                    or (kind == "Trial" and State.AutoTrial)
                if enabled then
                    pcall(farmStep, false)
                end
            else
                if State.WasInGamemode then
                    State.WasInGamemode = false
                    State.LeaveTriggeredSession = nil
                    resetFarmTarget()
                    State.PendingAutoReturn = State.AutoReturn and typeof(State.ReturnPosition) == "CFrame"
                end
                if State.PendingAutoReturn and State.AutoReturn and not Omni.Data.Gamemode then
                    if returnPosition() then
                        State.PendingAutoReturn = false
                    end
                end
                if State.AutoDungeon then
                    pcall(tryJoinGamemode, "Dungeon")
                end
                if State.AutoTrial then
                    pcall(tryJoinGamemode, "Trial")
                end
                if State.AutoQuestWorlds then
                    pcall(autoQuestWorldStep)
                elseif State.AutoFarm and not State.AutoStars and not State.AutoGacha then
                    pcall(farmStep, true)
                end
            end
            task.wait(0.08)
        end
    end)

    task.spawn(function()
        while State.Running do
            if State.AutoStars then
                pcall(starStep)
            end
            task.wait(0.08)
        end
    end)

    task.spawn(function()
        while State.Running do
            if State.AutoGacha and os.clock() >= State.NextGachaRoll then
                pcall(gachaStep)
            end
            task.wait(0.2)
        end
    end)
end

startCoreWorkers()

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

Controls.Fighters = Tabs.Traits:AddDropdown("CE106_Fighters", {
    Title = "Fighters",
    Values = {},
    Multi = true,
    Default = nil,
    DropdownOutsideWindow = false,
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
    Default = nil,
    DropdownOutsideWindow = false,
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

uiSafe("Upgrades", function()
    Tabs.Upgrade:AddSection("Adventurer Upgrades")
    for _, name in ipairs(UPGRADE_VALUES) do
        local key = upgradeControlKey(name)
        Controls[key] = Tabs.Upgrade:AddToggle("CE106_" .. key, {
            Title = name,
            Default = false,
            Callback = function(value)
                if value == true then
                    State.SelectedUpgrades[name] = true
                else
                    State.SelectedUpgrades[name] = nil
                end
                State.NextUpgrade = 0
            end,
        })
    end
    Tabs.Upgrade:AddButton({
        Title = "Select All Upgrades",
        Icon = "solar/checklist-minimalistic-bold",
        Callback = function()
            for _, name in ipairs(UPGRADE_VALUES) do
                setControl(upgradeControlKey(name), true)
            end
        end,
    })
    Tabs.Upgrade:AddButton({
        Title = "Clear Upgrades",
        Icon = "solar/close-circle-bold",
        Callback = function()
            for _, name in ipairs(UPGRADE_VALUES) do
                setControl(upgradeControlKey(name), false)
            end
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
end)

uiSafe("Rewards", function()
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
end)

uiSafe("Settings", function()
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
        Default = true,
        Callback = function(value)
            State.AutoCloseUI = value == true
            if not State.AutoCloseUI then
                ScriptWindowAutoClosed = false
            else
                task.defer(closeScriptWindow)
            end
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
        DropdownOutsideWindow = false,
        Callback = function(value)
            pcall(function() Fluent:SetTheme(value) end)
        end,
    })
end)

uiSafe("Profiles", function()
    Tabs.Configs:AddSection("Profiles")
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
        DropdownOutsideWindow = false,
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
        Callback = function() refreshConfigs(true) end,
    })
    Tabs.Configs:AddButton({
        Title = "Create Profile",
        Icon = "solar/add-circle-bold",
        Callback = function()
            local name = cleanProfileName(State.ProfileName)
            if isfile and isfile(configPath(name)) then
                notify("Profile já existe: " .. name)
                return
            end
            if saveConfig(name) then refreshConfigs(true) end
        end,
    })
    Tabs.Configs:AddButton({
        Title = "Save Profile",
        Icon = "solar/diskette-bold",
        Callback = function()
            if saveConfig(State.ActiveProfile or State.ProfileName) then refreshConfigs(true) end
        end,
    })
    Tabs.Configs:AddButton({
        Title = "Load Profile",
        Icon = "solar/folder-open-bold",
        Callback = function() loadConfig(State.ActiveProfile or State.ProfileName, false) end,
    })
    Tabs.Configs:AddButton({
        Title = "Delete Profile",
        Icon = "solar/trash-bin-trash-bold",
        Callback = function()
            if deleteConfig(State.ActiveProfile or State.ProfileName) then refreshConfigs(true) end
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
end)

local function cleanup()
    State.Running = false
    State.AutoFarm = false
    State.AutoQuestWorlds = false
    State.AutoDungeon = false
    State.AutoTrial = false
    State.AutoStars = false
    pcall(stopNativeStars)
    State.AutoGacha = false
    pcall(stopNativeGacha)
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
    local lastFighterRefresh = 0
    while State.Running do
        local now = os.clock()
        if now - lastFighterRefresh >= 3 then
            lastFighterRefresh = now
            pcall(refreshFighters, false)
        end
        task.wait(0.1)
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
            pcall(traitStep)
        end
        task.wait(0.08)
    end
end)

task.spawn(function()
    while State.Running do
        if State.AutoUpgrade then
            pcall(upgradeStep)
        end
        task.wait(0.1)
    end
end)

if State.AutoCloseUI then
    task.defer(closeScriptWindow)
end