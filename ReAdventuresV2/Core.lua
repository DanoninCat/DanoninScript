-- Re Adventures V2 runtime core
-- UI remains separate; actions use the game endpoints through a replaceable adapter.
-- Designed to be embedded or wired into the existing Loader/UI.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local CollectionService = game:GetService("CollectionService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

local Core = {}
Core.VERSION = "2.4.0"
Core.LOADER_COMMAND = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/DanoninCat/DanoninScript/re-adventures-v2-core/Loader/Loader.lua", true))()]]

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok then
        return value
    end
    return fallback
end

local function cloneArray(t)
    local out = {}
    for i = 1, #t do
        out[i] = t[i]
    end
    return out
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local out = {}
    seen[value] = out

    for k, v in pairs(value) do
        out[deepCopy(k, seen)] = deepCopy(v, seen)
    end

    return out
end

local function cframeToArray(cf)
    if typeof(cf) ~= "CFrame" then
        return nil
    end
    return { cf:GetComponents() }
end

local function vectorToArray(v)
    if typeof(v) ~= "Vector3" then
        return nil
    end
    return { v.X, v.Y, v.Z }
end

local function parseNumber(text)
    if type(text) ~= "string" then
        return nil
    end

    local cleaned = text:gsub(",", ""):gsub("%s+", "")
    local found = cleaned:match("%-?%d+%.?%d*")
    if not found then
        return nil
    end

    return tonumber(found)
end

local function parseHealth(text)
    if type(text) ~= "string" then
        return nil, nil
    end

    local a, b = text:match("([%d,%.]+)%s*/%s*([%d,%.]+)")
    if not a or not b then
        return nil, nil
    end

    return tonumber((a:gsub(",", ""))), tonumber((b:gsub(",", "")))
end

local UNIT_DISPLAY_NAMES = {}
local UNIT_NAMES_SCANNED = false

local function scanUnitDisplayNames()
    if UNIT_NAMES_SCANNED then
        return
    end

    local srcRoot = ReplicatedStorage:FindFirstChild("src")
    local dataRoot = srcRoot and srcRoot:FindFirstChild("Data")
    local unitsRoot = dataRoot and dataRoot:FindFirstChild("Units")

    if not unitsRoot then
        return
    end

    UNIT_NAMES_SCANNED = true

    for _, module in ipairs(unitsRoot:GetDescendants()) do
        if module:IsA("ModuleScript") then
            local ok, value = pcall(require, module)

            if ok and type(value) == "table" then
                for key, unit in pairs(value) do
                    if type(unit) == "table" then
                        local id = type(unit.id) == "string" and unit.id
                            or (type(key) == "string" and key or nil)

                        local displayName = unit.name
                            or unit.display_name
                            or unit.displayName

                        if id and type(displayName) == "string" and displayName ~= "" then
                            UNIT_DISPLAY_NAMES[id] = displayName
                        end
                    end
                end
            end
        end
    end
end

local function getUnitDisplayName(unitId)
    if type(unitId) ~= "string" or unitId == "" then
        return nil
    end

    if not UNIT_NAMES_SCANNED then
        scanUnitDisplayNames()
    end

    return UNIT_DISPLAY_NAMES[unitId]
end

local function readText(instance)
    if instance and (
        instance:IsA("TextLabel")
        or instance:IsA("TextButton")
        or instance:IsA("TextBox")
    ) then
        return instance.Text
    end

    return nil
end

local function findPath(root, ...)
    local current = root

    for index = 1, select("#", ...) do
        if not current then
            return nil
        end

        -- select(index, ...) returns ALL remaining varargs when used as the
        -- last function argument. Store it first so FindFirstChild receives
        -- only the child name; otherwise the next string is treated as the
        -- recursive boolean and Roblox throws "Unable to cast string to bool".
        local childName = select(index, ...)
        if type(childName) ~= "string" or childName == "" then
            return nil
        end

        current = current:FindFirstChild(childName)
    end

    return current
end

local function normalizeRewardName(name)
    name = tostring(name or "Reward")
    name = name:gsub("Reward$", "")
    name = name:gsub("_", " ")
    name = name:gsub("(%l)(%u)", "%1 %2")

    if name == "Gem" then
        return "Gems"
    elseif name == "Gold" then
        return "Gold"
    elseif name == "XP" then
        return "EXP"
    end

    return name
end

local function parsePlayerProgress(text)
    if type(text) ~= "string" then
        return nil
    end

    local level, current, required = text:match(
        "Level%s+(%d+)%s*%[%s*([%d,]+)%s*/%s*([%d,]+)%s*%]"
    )

    if not level then
        return nil
    end

    return {
        level = tonumber(level),
        current = tonumber((current:gsub(",", ""))),
        required = tonumber((required:gsub(",", ""))),
    }
end

local WEBHOOK_EMOJIS = {
    victory = "<:victory:1529957193569407064>",
    defeat = "<:defeat:1529975410928914486>",
    arrow = "<:arrow:1529932375339827271>",
    clock = "<:clock:1531389528021925918>",
    person = "<:person:1529967343193817089>",
    playerExp = "<:player_exp:1531391369178910720>",
    unitExp = "<:unit_exp:1531391443975930036>",
    rewards = "<:Rewards:1531389702756634654>",
    gold = "<:Gold:1321451928864952361>",
    gems = "<:Gems:1321452136508166277>",
    expeditionCoin = "<:expedition_coin:1531389815147462848>",
}

local WEBHOOK_REWARD_EMOJIS = {
    gold = WEBHOOK_EMOJIS.gold,
    gems = WEBHOOK_EMOJIS.gems,
    gem = WEBHOOK_EMOJIS.gems,
    expeditioncoin = WEBHOOK_EMOJIS.expeditionCoin,
}

local function rewardEmoji(name)
    local key = tostring(name or ""):lower():gsub("[^%w]", "")
    return WEBHOOK_REWARD_EMOJIS[key]
end

local function detectMode(level)
    level = tostring(level or ""):lower()

    if level:find("infinite", 1, true) then
        return "Infinite"
    elseif level:find("legend", 1, true) then
        return "Legend"
    elseif level:find("raid", 1, true) then
        return "Raid"
    elseif level:find("portal", 1, true) then
        return "Portal"
    elseif level:find("tournament", 1, true) then
        return "Tournament"
    elseif level:find("expedition", 1, true) then
        return "Expedition"
    end

    return "Story"
end

local function getValue(parent, name)
    if not parent then
        return nil
    end

    local obj = parent:FindFirstChild(name)
    if obj and obj:IsA("ValueBase") then
        return obj.Value
    end

    return nil
end

local function fullName(instance)
    if not instance then
        return nil
    end

    return safe(function()
        return instance:GetFullName()
    end, instance.Name)
end

local function findDescendantByName(root, name)
    if not root then
        return nil
    end

    for _, item in ipairs(root:GetDescendants()) do
        if item.Name == name then
            return item
        end
    end

    return nil
end

local EventBus = {}
EventBus.__index = EventBus

function EventBus.new()
    return setmetatable({
        listeners = {},
        nextId = 0,
    }, EventBus)
end

function EventBus:on(name, callback)
    assert(type(callback) == "function", "callback must be a function")

    self.nextId = self.nextId + 1
    local id = self.nextId

    if not self.listeners[name] then
        self.listeners[name] = {}
    end

    self.listeners[name][id] = callback

    local disconnected = false
    return function()
        if disconnected then
            return
        end
        disconnected = true

        local bucket = self.listeners[name]
        if bucket then
            bucket[id] = nil
        end
    end
end

function EventBus:emit(name, payload)
    local bucket = self.listeners[name]
    if not bucket then
        return
    end

    for _, callback in pairs(bucket) do
        task.spawn(function()
            local ok, err = pcall(callback, payload)
            if not ok then
                warn("[ReAdventuresV2] listener error:", err)
            end
        end)
    end
end

local StateTracker = {}
StateTracker.__index = StateTracker

function StateTracker.new(options)
    options = options or {}

    local self = setmetatable({}, StateTracker)

    self.options = options
    self.events = EventBus.new()
    self.running = false
    self.connections = {}
    self.unitConnections = {}
    self.enemyConnections = {}

    self.state = {
        placeId = game.PlaceId,
        gameId = game.GameId,

        map = {
            area = nil,
            level = nil,
            isLobby = nil,
            mapLoaded = nil,
        },

        match = {
            phase = "UNKNOWN",
            started = false,
            finished = false,
            serverReady = false,
            wavesStarted = false,
            isLastWave = false,
            wave = 0,
            waveTime = 0,
            voteCount = 0,
            votingFinished = false,
        },

        player = {
            name = LocalPlayer and LocalPlayer.Name or nil,
            userId = LocalPlayer and LocalPlayer.UserId or nil,
            money = nil,
            baseLife = nil,
            baseMaxLife = nil,
        },

        units = {},
        enemies = {},

        counters = {
            unitsPlaced = 0,
            enemiesAlive = 0,
        },
    }

    return self
end

function StateTracker:on(name, callback)
    return self.events:on(name, callback)
end

function StateTracker:_connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(self.connections, connection)
    return connection
end

function StateTracker:_disconnectBucket(bucket)
    for _, connection in ipairs(bucket) do
        safe(function()
            connection:Disconnect()
        end)
    end
    table.clear(bucket)
end

function StateTracker:_computePhase()
    local match = self.state.match
    local newPhase

    if match.finished then
        newPhase = "FINISHED"
    elseif not match.started then
        if match.votingFinished then
            newPhase = "STARTING"
        elseif match.voteCount > 0 then
            newPhase = "READY_VOTE"
        else
            newPhase = "WAITING"
        end
    elseif match.wavesStarted then
        newPhase = "PLAYING"
    else
        newPhase = "STARTING"
    end

    if newPhase ~= match.phase then
        local previous = match.phase
        match.phase = newPhase
        self.events:emit("matchPhaseChanged", {
            from = previous,
            to = newPhase,
        })
    end
end

function StateTracker:_bindValue(instance, callback)
    if not instance or not instance:IsA("ValueBase") then
        return
    end

    callback(instance.Value)

    self:_connect(instance.Changed, function(value)
        callback(value)
    end)
end

function StateTracker:_bindMap()
    local config = Workspace:FindFirstChild("_MAP_CONFIG")
    if not config then
        return
    end

    local function updateMap()
        local beforeArea = self.state.map.area
        local beforeLevel = self.state.map.level

        self.state.map.area = getValue(config, "Area")
        self.state.map.level = getValue(config, "Level")
        self.state.map.isLobby = getValue(config, "IsLobby")
        self.state.map.mapLoaded = getValue(config, "MapLoaded")

        if beforeArea ~= self.state.map.area or beforeLevel ~= self.state.map.level then
            self.events:emit("mapChanged", deepCopy(self.state.map))
        end
    end

    updateMap()

    for _, name in ipairs({ "Area", "Level", "IsLobby", "MapLoaded" }) do
        local valueObj = config:FindFirstChild(name)
        if valueObj and valueObj:IsA("ValueBase") then
            self:_connect(valueObj.Changed, updateMap)
        end
    end
end

function StateTracker:_bindMatchState()
    local data = Workspace:FindFirstChild("_DATA")

    local gameStarted = data and data:FindFirstChild("GameStarted")
    local gameFinished = data and data:FindFirstChild("GameFinished")

    self:_bindValue(gameStarted, function(value)
        self.state.match.started = value == true
        self:_computePhase()
    end)

    self:_bindValue(gameFinished, function(value)
        self.state.match.finished = value == true
        self:_computePhase()
    end)

    self:_bindValue(Workspace:FindFirstChild("SERVER_READY"), function(value)
        self.state.match.serverReady = value == true
    end)

    self:_bindValue(Workspace:FindFirstChild("_waves_started"), function(value)
        self.state.match.wavesStarted = value == true
        self:_computePhase()
    end)

    self:_bindValue(Workspace:FindFirstChild("_is_last_wave"), function(value)
        self.state.match.isLastWave = value == true
    end)

    self:_bindValue(Workspace:FindFirstChild("_wave_num"), function(value)
        local old = self.state.match.wave
        self.state.match.wave = tonumber(value) or 0

        if old ~= self.state.match.wave then
            self.events:emit("waveChanged", {
                from = old,
                to = self.state.match.wave,
            })
        end
    end)

    self:_bindValue(Workspace:FindFirstChild("_wave_time"), function(value)
        self.state.match.waveTime = tonumber(value) or 0
    end)

    local voteStart = data and data:FindFirstChild("VoteStart")
    if voteStart then
        self:_bindValue(voteStart:FindFirstChild("Votes"), function(value)
            self.state.match.voteCount = tonumber(value) or 0
            self:_computePhase()
        end)

        self:_bindValue(voteStart:FindFirstChild("VotingFinished"), function(value)
            self.state.match.votingFinished = value == true
            self:_computePhase()
        end)
    end

    -- Match dumps confirm these server_to_client RemoteEvents. Treat them as
    -- lightweight state signals so automation still tracks a match when one
    -- of the mirrored Workspace Value objects is missing or updates late.
    local endpoints = ReplicatedStorage:FindFirstChild("endpoints")
    local serverToClient = endpoints and endpoints:FindFirstChild("server_to_client")

    local function bindRemote(name, callback)
        local remote = serverToClient and serverToClient:FindFirstChild(name)
        if remote and remote:IsA("RemoteEvent") then
            self:_connect(remote.OnClientEvent, callback)
        end
    end

    bindRemote("wave_started", function()
        self.state.match.started = true
        self.state.match.wavesStarted = true
        self.state.match.finished = false
        self:_computePhase()
    end)

    bindRemote("game_finished", function()
        self.state.match.finished = true
        self:_computePhase()
    end)

    bindRemote("replay_started", function()
        self.state.match.finished = false
        self.state.match.started = true
        self.state.match.wavesStarted = false
        self.state.match.isLastWave = false
        self.state.match.voteCount = 0
        self.state.match.votingFinished = false
        self:_computePhase()
    end)
end

function StateTracker:_unitSnapshot(model)
    if not model or not model.Parent then
        return nil
    end

    local stats = model:FindFirstChild("_stats")
    if not stats then
        return nil
    end

    local uuid = getValue(stats, "uuid")
    if type(uuid) ~= "string" or uuid == "" then
        return nil
    end

    local owner = stats:FindFirstChild("player")
    local ownerValue = owner and owner:IsA("ObjectValue") and owner.Value or nil

    local pivot = safe(function()
        return model:GetPivot()
    end)

    return {
        uuid = uuid,
        unitId = getValue(stats, "id") or model.Name,
        name = model.Name,
        ownerName = ownerValue and ownerValue.Name or nil,
        ownerUserId = ownerValue and ownerValue.UserId or nil,
        upgrade = tonumber(getValue(stats, "upgrade")) or 0,
        upgradeLevel = tonumber(getValue(stats, "upgrade_level")) or 0,
        maxUpgrade = tonumber(getValue(stats, "max_upgrade")) or 0,
        spent = tonumber(getValue(stats, "spent")) or tonumber(getValue(stats, "total_spent")) or 0,
        priority = getValue(stats, "priority"),
        health = tonumber(getValue(stats, "health")),
        maxHealth = tonumber(getValue(stats, "max_health")),
        damage = tonumber(getValue(stats, "damage")),
        range = tonumber(getValue(stats, "range")),
        cooldown = tonumber(getValue(stats, "attack_cooldown")),
        cframe = pivot and cframeToArray(pivot) or nil,
        position = pivot and vectorToArray(pivot.Position) or nil,
        path = fullName(model),
    }
end

function StateTracker:_trackUnit(model, initial)
    task.defer(function()
        if not self.running or not model or not model.Parent then
            return
        end

        local stats = model:FindFirstChild("_stats") or model:WaitForChild("_stats", 5)
        if not stats then
            return
        end

        local uuidObj = stats:FindFirstChild("uuid") or stats:WaitForChild("uuid", 5)
        if not uuidObj or not uuidObj:IsA("ValueBase") then
            return
        end

        local snapshot = self:_unitSnapshot(model)
        if not snapshot then
            return
        end

        local uuid = snapshot.uuid
        self.state.units[uuid] = snapshot

        local bucket = {}
        self.unitConnections[uuid] = bucket

        local function addConnection(connection)
            table.insert(bucket, connection)
        end

        local upgradeObj = stats:FindFirstChild("upgrade")
        if upgradeObj and upgradeObj:IsA("ValueBase") then
            addConnection(upgradeObj.Changed:Connect(function(newValue)
                local current = self.state.units[uuid]
                if not current then
                    return
                end

                local old = current.upgrade
                current.upgrade = tonumber(newValue) or 0
                current.upgradeLevel = tonumber(getValue(stats, "upgrade_level")) or current.upgradeLevel
                current.spent = tonumber(getValue(stats, "spent")) or tonumber(getValue(stats, "total_spent")) or current.spent

                if old ~= current.upgrade then
                    self.events:emit("unitUpgradeChanged", {
                        uuid = uuid,
                        from = old,
                        to = current.upgrade,
                        unit = deepCopy(current),
                    })
                end
            end))
        end

        for _, name in ipairs({ "priority", "health", "max_health", "damage", "range", "attack_cooldown", "spent", "total_spent" }) do
            local obj = stats:FindFirstChild(name)
            if obj and obj:IsA("ValueBase") then
                addConnection(obj.Changed:Connect(function()
                    local refreshed = self:_unitSnapshot(model)
                    if refreshed then
                        self.state.units[uuid] = refreshed
                    end
                end))
            end
        end

        self.state.counters.unitsPlaced = 0
        for _, unit in pairs(self.state.units) do
            if unit.ownerUserId == self.state.player.userId then
                self.state.counters.unitsPlaced = self.state.counters.unitsPlaced + 1
            end
        end

        if not initial and snapshot.ownerUserId == self.state.player.userId then
            self.events:emit("unitAdded", {
                unit = deepCopy(snapshot),
            })
        end
    end)
end

function StateTracker:_removeUnit(model)
    local foundUuid

    for uuid, unit in pairs(self.state.units) do
        if unit.path == fullName(model) or unit.name == model.Name then
            foundUuid = uuid
            break
        end
    end

    if not foundUuid then
        return
    end

    local previous = self.state.units[foundUuid]
    self.state.units[foundUuid] = nil

    local bucket = self.unitConnections[foundUuid]
    if bucket then
        self:_disconnectBucket(bucket)
        self.unitConnections[foundUuid] = nil
    end

    self.state.counters.unitsPlaced = 0
    for _, unit in pairs(self.state.units) do
        if unit.ownerUserId == self.state.player.userId then
            self.state.counters.unitsPlaced = self.state.counters.unitsPlaced + 1
        end
    end

    if previous and previous.ownerUserId == self.state.player.userId then
        self.events:emit("unitRemoved", {
            unit = deepCopy(previous),
        })
    end
end

function StateTracker:_bindUnits()
    local folder = Workspace:FindFirstChild("_UNITS")
    if not folder then
        return
    end

    for _, child in ipairs(folder:GetChildren()) do
        self:_trackUnit(child, true)
    end

    self:_connect(folder.ChildAdded, function(child)
        self:_trackUnit(child, false)
    end)

    self:_connect(folder.ChildRemoved, function(child)
        self:_removeUnit(child)
    end)
end

function StateTracker:_enemySnapshot(model)
    if not model or not model.Parent then
        return nil
    end

    local stats = model:FindFirstChild("_stats")
    if not stats then
        return nil
    end

    local pivot = safe(function()
        return model:GetPivot()
    end)

    return {
        key = fullName(model),
        id = getValue(stats, "id") or model.Name,
        name = model.Name,
        health = tonumber(getValue(stats, "health")),
        maxHealth = tonumber(getValue(stats, "max_health")),
        position = pivot and vectorToArray(pivot.Position) or nil,
        path = fullName(model),
    }
end

function StateTracker:_trackEnemy(model)
    task.defer(function()
        if not self.running or not model or not model.Parent then
            return
        end

        local stats = model:FindFirstChild("_stats") or model:WaitForChild("_stats", 5)
        if not stats then
            return
        end

        local snapshot = self:_enemySnapshot(model)
        if not snapshot then
            return
        end

        local key = snapshot.key
        self.state.enemies[key] = snapshot
        self.state.counters.enemiesAlive = self.state.counters.enemiesAlive + 1

        local bucket = {}
        self.enemyConnections[key] = bucket

        local health = stats:FindFirstChild("health")
        if health and health:IsA("ValueBase") then
            table.insert(bucket, health.Changed:Connect(function(value)
                local current = self.state.enemies[key]
                if current then
                    current.health = tonumber(value)
                end
            end))
        end

        self.events:emit("enemyAdded", {
            enemy = deepCopy(snapshot),
            count = self.state.counters.enemiesAlive,
        })
    end)
end

function StateTracker:_removeEnemy(model)
    local path = fullName(model)
    local key

    for candidate, enemy in pairs(self.state.enemies) do
        if enemy.path == path or enemy.name == model.Name then
            key = candidate
            break
        end
    end

    if not key then
        return
    end

    local previous = self.state.enemies[key]
    self.state.enemies[key] = nil
    self.state.counters.enemiesAlive = math.max(0, self.state.counters.enemiesAlive - 1)

    local bucket = self.enemyConnections[key]
    if bucket then
        self:_disconnectBucket(bucket)
        self.enemyConnections[key] = nil
    end

    self.events:emit("enemyRemoved", {
        enemy = deepCopy(previous),
        count = self.state.counters.enemiesAlive,
    })
end

function StateTracker:_bindEnemies()
    local folder = Workspace:FindFirstChild("_PATH_UNITS")
    if not folder then
        return
    end

    for _, child in ipairs(folder:GetChildren()) do
        self:_trackEnemy(child)
    end

    self:_connect(folder.ChildAdded, function(child)
        self:_trackEnemy(child)
    end)

    self:_connect(folder.ChildRemoved, function(child)
        self:_removeEnemy(child)
    end)
end

function StateTracker:_findMoneyFrame()
    if not LocalPlayer then
        return nil
    end

    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not gui then
        return nil
    end

    local spawnUnits = gui:FindFirstChild("spawn_units")
    local lives = spawnUnits and spawnUnits:FindFirstChild("Lives")
    local frame = lives and lives:FindFirstChild("Frame")
    local resource = frame and frame:FindFirstChild("Resource")
    return resource and resource:FindFirstChild("Money")
end

function StateTracker:_readMoney(frame)
    if not frame then
        return nil
    end

    local best

    for _, item in ipairs(frame:GetDescendants()) do
        if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
            local lower = item.Name:lower()
            local insideChange = item:FindFirstAncestor("MoneyChange") ~= nil
            local value = parseNumber(item.Text)

            if value ~= nil and not insideChange and lower ~= "symbol" then
                local score = 1
                if lower == "level" or lower == "amount" or lower == "value" or lower == "text" then
                    score = score + 3
                end
                if item:IsA("GuiObject") and item.Visible then
                    score = score + 2
                end

                if not best or score > best.score then
                    best = {
                        score = score,
                        value = value,
                    }
                end
            end
        end
    end

    return best and best.value or nil
end

function StateTracker:_bindMoney()
    local frame = self:_findMoneyFrame()
    if not frame then
        return
    end

    local function refresh()
        local value = self:_readMoney(frame)
        if value == nil then
            return
        end

        local old = self.state.player.money
        self.state.player.money = value

        if old ~= value then
            self.events:emit("moneyChanged", {
                from = old,
                to = value,
            })
        end
    end

    refresh()

    for _, item in ipairs(frame:GetDescendants()) do
        if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
            self:_connect(item:GetPropertyChangedSignal("Text"), refresh)
        end
    end

    self:_connect(frame.DescendantAdded, function(item)
        if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
            self:_connect(item:GetPropertyChangedSignal("Text"), refresh)
            refresh()
        end
    end)
end

function StateTracker:_findHealthDisplay()
    if not LocalPlayer then
        return nil
    end

    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local waves = gui and gui:FindFirstChild("Waves")
    local healthBar = waves and waves:FindFirstChild("HealthBar")
    return healthBar and healthBar:FindFirstChild("HPDisplay")
end

function StateTracker:_bindBaseLife()
    local display = self:_findHealthDisplay()
    if not display or not (display:IsA("TextLabel") or display:IsA("TextButton")) then
        return
    end

    local function refresh()
        local life, maxLife = parseHealth(display.Text)
        if life == nil then
            return
        end

        local old = self.state.player.baseLife
        self.state.player.baseLife = life
        self.state.player.baseMaxLife = maxLife

        if old ~= life then
            self.events:emit("baseLifeChanged", {
                from = old,
                to = life,
                max = maxLife,
            })
        end
    end

    refresh()
    self:_connect(display:GetPropertyChangedSignal("Text"), refresh)
end

function StateTracker:getSnapshot()
    return deepCopy(self.state)
end

function StateTracker:getMapIdentity()
    return {
        placeId = self.state.placeId,
        area = self.state.map.area,
        level = self.state.map.level,
    }
end

function StateTracker:start()
    if self.running then
        return self:getSnapshot()
    end

    self.running = true

    self:_bindMap()
    self:_bindMatchState()
    self:_bindUnits()
    self:_bindEnemies()
    self:_bindMoney()
    self:_bindBaseLife()
    self:_computePhase()

    self.events:emit("started", self:getSnapshot())
    return self:getSnapshot()
end

function StateTracker:stop()
    if not self.running then
        return
    end

    self.running = false
    self:_disconnectBucket(self.connections)

    for uuid, bucket in pairs(self.unitConnections) do
        self:_disconnectBucket(bucket)
        self.unitConnections[uuid] = nil
    end

    for key, bucket in pairs(self.enemyConnections) do
        self:_disconnectBucket(bucket)
        self.enemyConnections[key] = nil
    end

    self.events:emit("stopped", self:getSnapshot())
end

local MapProfiles = {}

MapProfiles.KNOWN = {
    marineford = {
        displayName = "Marineford",
        thumbnail = "https://i.imgur.com/gbeJ8KD.png",
        defaultLevel = "marineford_level_1",
        profileQuality = "complete",
    },
    aot = {
        displayName = "Walled City",
        thumbnail = "https://i.imgur.com/sYQ7FLf.png",
        defaultLevel = "aot_level_1",
        profileQuality = "complete",
    },
    demonslayer = {
        displayName = "Snowy Town",
        thumbnail = "https://i.imgur.com/XPLChYo.png",
        defaultLevel = "demonslayer_level_1",
        profileQuality = "partial_workspace_limit",
    },
    naruto = {
        displayName = "Sand Village",
        thumbnail = "https://i.imgur.com/kcvbhpF.png",
        defaultLevel = "naruto_level_1",
        profileQuality = "complete",
    },
    namek = {
        displayName = "Namek",
        thumbnail = "https://i.imgur.com/pDDDOGQ.png",
        defaultLevel = "namek_level_1",
        profileQuality = "complete",
    },
}

function MapProfiles.resolve(area, level)
    local known = area and MapProfiles.KNOWN[area] or nil

    return {
        area = area,
        level = level,
        displayName = known and known.displayName or area or "Unknown",
        thumbnail = known and known.thumbnail or nil,
        profileQuality = known and known.profileQuality or "runtime_only",
        known = known ~= nil,
    }
end

local function partSort(a, b)
    local an = tonumber(a.Name)
    local bn = tonumber(b.Name)

    if an and bn then
        return an < bn
    elseif an then
        return true
    elseif bn then
        return false
    end

    return a.Name < b.Name
end

function MapProfiles.captureRuntimeGeometry(maxPointsPerLane)
    maxPointsPerLane = tonumber(maxPointsPerLane) or 160

    local config = Workspace:FindFirstChild("_MAP_CONFIG")
    local area = getValue(config, "Area")
    local level = getValue(config, "Level")

    local profile = MapProfiles.resolve(area, level)
    profile.placeId = game.PlaceId
    profile.capturedAt = os.time()
    profile.lanes = {}
    profile.bases = {}

    local basesRoot = Workspace:FindFirstChild("_BASES")
    if not basesRoot then
        return profile
    end

    local laneFolders = {}
    for _, item in ipairs(basesRoot:GetDescendants()) do
        if item.Name == "LANES" then
            table.insert(laneFolders, item)
        end
    end

    for _, lanesRoot in ipairs(laneFolders) do
        for _, lane in ipairs(lanesRoot:GetChildren()) do
            local points = {}
            local parts = {}

            if lane:IsA("BasePart") then
                table.insert(parts, lane)
            else
                for _, item in ipairs(lane:GetChildren()) do
                    if item:IsA("BasePart") then
                        table.insert(parts, item)
                    end
                end
            end

            table.sort(parts, partSort)

            for index, part in ipairs(parts) do
                if index > maxPointsPerLane then
                    break
                end

                table.insert(points, {
                    name = part.Name,
                    position = vectorToArray(part.Position),
                    cframe = cframeToArray(part.CFrame),
                })
            end

            table.insert(profile.lanes, {
                path = fullName(lane),
                name = lane.Name,
                points = points,
            })
        end
    end

    for _, item in ipairs(basesRoot:GetDescendants()) do
        if item:IsA("Model") and item.Name:lower():find("base", 1, true) then
            local pivot = safe(function()
                return item:GetPivot()
            end)

            table.insert(profile.bases, {
                path = fullName(item),
                name = item.Name,
                cframe = pivot and cframeToArray(pivot) or nil,
            })
        end
    end

    profile.laneCount = #profile.lanes
    profile.baseCount = #profile.bases

    return profile
end

local Serializer = {}

function Serializer.encode(value)
    return HttpService:JSONEncode(value)
end

function Serializer.decode(text)
    assert(type(text) == "string" and text ~= "", "macro JSON must be a non-empty string")

    local decoded = HttpService:JSONDecode(text)
    assert(type(decoded) == "table", "macro JSON must decode to a table")
    assert(decoded.schema == "re-adventures-macro", "unsupported macro schema")
    assert(decoded.version == 2, "unsupported macro version")
    assert(type(decoded.events) == "table", "macro events are missing")
    assert(type(decoded.snapshots) == "table", "macro snapshots are missing")

    return decoded
end

local MacroRecorder = {}
MacroRecorder.__index = MacroRecorder

function MacroRecorder.new(tracker, options)
    options = options or {}

    return setmetatable({
        tracker = tracker,
        options = {
            snapshotInterval = tonumber(options.snapshotInterval) or 2,
            maxSnapshots = tonumber(options.maxSnapshots) or 7200,
        },
        recording = false,
        startedClock = nil,
        macro = nil,
        disconnectors = {},
        generation = 0,
    }, MacroRecorder)
end

function MacroRecorder:_now()
    if not self.startedClock then
        return 0
    end
    return os.clock() - self.startedClock
end

function MacroRecorder:_context()
    local state = self.tracker.state

    return {
        wave = state.match.wave,
        waveTime = state.match.waveTime,
        phase = state.match.phase,
        money = state.player.money,
        baseLife = state.player.baseLife,
        baseMaxLife = state.player.baseMaxLife,
        unitsPlaced = state.counters.unitsPlaced,
        enemiesAlive = state.counters.enemiesAlive,
    }
end

function MacroRecorder:_record(kind, data)
    if not self.recording or not self.macro then
        return
    end

    table.insert(self.macro.events, {
        t = self:_now(),
        type = kind,
        data = deepCopy(data or {}),
        context = self:_context(),
    })
end

function MacroRecorder:_addSnapshot()
    if not self.recording or not self.macro then
        return
    end

    if #self.macro.snapshots >= self.options.maxSnapshots then
        return
    end

    local state = self.tracker.state
    local units = {}

    for uuid, unit in pairs(state.units) do
        if unit.ownerUserId == state.player.userId then
            units[uuid] = {
                unitId = unit.unitId,
                upgrade = unit.upgrade,
                spent = unit.spent,
                position = cloneArray(unit.position or {}),
            }
        end
    end

    table.insert(self.macro.snapshots, {
        t = self:_now(),
        wave = state.match.wave,
        waveTime = state.match.waveTime,
        phase = state.match.phase,
        money = state.player.money,
        baseLife = state.player.baseLife,
        baseMaxLife = state.player.baseMaxLife,
        enemiesAlive = state.counters.enemiesAlive,
        units = units,
    })
end

function MacroRecorder:_bind()
    local function listen(name, callback)
        table.insert(self.disconnectors, self.tracker:on(name, callback))
    end

    listen("unitAdded", function(payload)
        if not payload.unit or not LocalPlayer or payload.unit.ownerUserId ~= LocalPlayer.UserId then return end
        self:_record("PLACE_DETECTED", {
            unit = payload.unit,
        })
    end)

    listen("unitUpgradeChanged", function(payload)
        if not payload.unit or not LocalPlayer or payload.unit.ownerUserId ~= LocalPlayer.UserId then return end
        self:_record("UPGRADE_DETECTED", {
            uuid = payload.uuid,
            from = payload.from,
            to = payload.to,
            unit = payload.unit,
        })
    end)

    listen("unitRemoved", function(payload)
        if not payload.unit or not LocalPlayer or payload.unit.ownerUserId ~= LocalPlayer.UserId then return end
        self:_record("UNIT_REMOVED", {
            unit = payload.unit,
        })
    end)

    listen("waveChanged", function(payload)
        self:_record("WAVE_CHANGED", {
            from = payload.from,
            to = payload.to,
        })
    end)

    listen("baseLifeChanged", function(payload)
        self:_record("BASE_LIFE_CHANGED", {
            from = payload.from,
            to = payload.to,
            max = payload.max,
        })
    end)

    listen("matchPhaseChanged", function(payload)
        self:_record("MATCH_PHASE_CHANGED", {
            from = payload.from,
            to = payload.to,
        })
    end)
end

function MacroRecorder:start(name)
    if self.recording then
        return false, "already recording"
    end

    if not self.tracker.running then
        self.tracker:start()
    end

    self.recording = true
    self.startedClock = os.clock()
    self.generation = self.generation + 1

    local state = self.tracker.state

    self.macro = {
        schema = "re-adventures-macro",
        version = 2,
        coreVersion = Core.VERSION,
        name = name or ("Macro " .. os.date("%Y-%m-%d %H:%M:%S")),
        createdAt = os.time(),

        game = {
            placeId = game.PlaceId,
            gameId = game.GameId,
        },

        map = {
            area = state.map.area,
            level = state.map.level,
            profile = MapProfiles.resolve(state.map.area, state.map.level),
        },

        initialState = {
            wave = state.match.wave,
            phase = state.match.phase,
            money = state.player.money,
            baseLife = state.player.baseLife,
            baseMaxLife = state.player.baseMaxLife,
        },

        events = {},
        snapshots = {},
    }

    self:_bind()
    self:_addSnapshot()

    local myGeneration = self.generation
    task.spawn(function()
        while self.recording and self.generation == myGeneration do
            task.wait(self.options.snapshotInterval)

            if self.recording and self.generation == myGeneration then
                self:_addSnapshot()
            end
        end
    end)

    return true, deepCopy(self.macro)
end

function MacroRecorder:stop()
    if not self.recording then
        return false, self.macro and deepCopy(self.macro) or nil
    end

    self:_addSnapshot()
    self.recording = false
    self.generation = self.generation + 1

    for _, disconnect in ipairs(self.disconnectors) do
        safe(disconnect)
    end
    table.clear(self.disconnectors)

    if self.macro then
        self.macro.duration = self:_now()
        self.macro.finishedAt = os.time()
    end

    return true, deepCopy(self.macro)
end

function MacroRecorder:getMacro()
    return self.macro and deepCopy(self.macro) or nil
end

-- In-memory macro library used by the existing UI integration.
-- Persistent storage is intentionally left to the Loader/application layer.
local MacroLibrary = {}
MacroLibrary.__index = MacroLibrary

function MacroLibrary.new()
    return setmetatable({
        items = {},
        order = {},
        selectedId = nil,
    }, MacroLibrary)
end

function MacroLibrary:_newId()
    local generated = safe(function()
        return HttpService:GenerateGUID(false)
    end)

    if type(generated) == "string" and generated ~= "" then
        return generated
    end

    local base = tostring(os.time()) .. "-" .. tostring(#self.order + 1)
    return base
end

function MacroLibrary:add(macro, overrideName)
    assert(type(macro) == "table", "macro must be a table")
    assert(macro.schema == "re-adventures-macro", "unsupported macro schema")
    assert(type(macro.events) == "table", "macro events are missing")
    assert(type(macro.snapshots) == "table", "macro snapshots are missing")

    local stored = deepCopy(macro)
    local id = stored.libraryId

    if type(id) ~= "string" or id == "" or self.items[id] ~= nil then
        id = self:_newId()
    end

    stored.libraryId = id

    if type(overrideName) == "string" and overrideName ~= "" then
        stored.name = overrideName
    elseif type(stored.name) ~= "string" or stored.name == "" then
        stored.name = "Macro " .. tostring(#self.order + 1)
    end

    local isNew = self.items[id] == nil
    self.items[id] = stored

    if isNew then
        table.insert(self.order, id)
    end

    self.selectedId = id
    return id, deepCopy(stored)
end

function MacroLibrary:list()
    local out = {}

    for index, id in ipairs(self.order) do
        local macro = self.items[id]

        if macro then
            table.insert(out, {
                index = index,
                id = id,
                name = macro.name,
                selected = id == self.selectedId,
                createdAt = macro.createdAt,
                finishedAt = macro.finishedAt,
                duration = macro.duration,
                area = macro.map and macro.map.area or nil,
                level = macro.map and macro.map.level or nil,
                eventCount = type(macro.events) == "table" and #macro.events or 0,
                snapshotCount = type(macro.snapshots) == "table" and #macro.snapshots or 0,
            })
        end
    end

    return out
end

function MacroLibrary:count()
    local count = 0

    for _, id in ipairs(self.order) do
        if self.items[id] then
            count = count + 1
        end
    end

    return count
end

function MacroLibrary:select(id)
    if type(id) ~= "string" or not self.items[id] then
        return false, "macro not found"
    end

    self.selectedId = id
    return true, deepCopy(self.items[id])
end

function MacroLibrary:get(id)
    id = id or self.selectedId

    if not id or not self.items[id] then
        return nil
    end

    return deepCopy(self.items[id])
end

function MacroLibrary:getSelectedId()
    return self.selectedId
end

function MacroLibrary:rename(id, newName)
    assert(type(newName) == "string", "new macro name must be a string")

    newName = newName:match("^%s*(.-)%s*$")

    if newName == "" then
        return false, "macro name cannot be empty"
    end

    local macro = self.items[id]
    if not macro then
        return false, "macro not found"
    end

    macro.name = newName
    return true, deepCopy(macro)
end

function MacroLibrary:remove(id)
    if not self.items[id] then
        return false, "macro not found"
    end

    self.items[id] = nil

    for index, candidate in ipairs(self.order) do
        if candidate == id then
            table.remove(self.order, index)
            break
        end
    end

    if self.selectedId == id then
        self.selectedId = self.order[#self.order]
    end

    return true
end

function MacroLibrary:clear()
    table.clear(self.items)
    table.clear(self.order)
    self.selectedId = nil
end

function MacroLibrary:importJson(json, overrideName)
    local macro = Serializer.decode(json)
    return self:add(macro, overrideName)
end

function MacroLibrary:exportJson(id)
    local macro = self:get(id)
    assert(macro, "macro not found")
    return Serializer.encode(macro)
end

local MacroReplay = {}
MacroReplay.__index = MacroReplay

function MacroReplay.new()
    return setmetatable({
        running = false,
        generation = 0,
        macro = nil,
        startedClock = nil,
        currentIndex = 0,
    }, MacroReplay)
end

function MacroReplay:start(macro, callback)
    if self.running then
        self:stop()
    end

    if type(macro) ~= "table" or type(macro.events) ~= "table" then
        return false, "invalid macro"
    end

    self.running = true
    self.lastError = nil
    self.generation = self.generation + 1
    self.macro = deepCopy(macro)
    self.startedClock = os.clock()
    self.currentIndex = 0

    local generation = self.generation
    local events = deepCopy(macro.events)

    task.spawn(function()
        for index, event in ipairs(events) do
            if not self.running or self.generation ~= generation then
                break
            end

            local targetTime = math.max(0, tonumber(event.t) or 0)

            while self.running and self.generation == generation do
                local elapsed = os.clock() - self.startedClock
                local remaining = targetTime - elapsed

                if remaining <= 0 then
                    break
                end

                task.wait(math.min(remaining, 0.05))
            end

            if not self.running or self.generation ~= generation then
                break
            end

            self.currentIndex = index

            if type(callback) == "function" then
                local ok, success, err = pcall(callback, deepCopy(event), index, #events)
                if not ok or success == false then
                    if self.generation ~= generation then return end
                    self.running = false
                    self.lastError = tostring(ok and err or success)
                    pcall(callback, nil, nil, #events, true, self.lastError)
                    return
                end
            end
        end

        if self.running and self.generation == generation then
            self.running = false
            self.currentIndex = #events

            if type(callback) == "function" then
                pcall(callback, nil, nil, #events, true)
            end
        end
    end)

    return true
end

function MacroReplay:stop()
    self.running = false
    self.generation = self.generation + 1
end

function MacroReplay:getStatus()
    return {
        running = self.running,
        error = self.lastError,
        currentIndex = self.currentIndex,
        eventCount = self.macro and #self.macro.events or 0,
        name = self.macro and self.macro.name or nil,
    }
end

local Controller = {}
Controller.__index = Controller

function Controller.new(options)
    options = options or {}

    local tracker = StateTracker.new(options.tracker)
    local recorder = MacroRecorder.new(tracker, options.recorder)

    return setmetatable({
        tracker = tracker,
        recorder = recorder,
        macros = MacroLibrary.new(),
        replay = MacroReplay.new(),
        placementMarkers = {},
        actionAdapter = options.actionAdapter,
        running = false,
        generation = 0,
        replayUnits = {},
        lastPostMatchAction = nil,
        lastReadyAttempt = 0,
        readySubmitted = false,
        readyWindowActive = false,
        importedMacro = nil,
        webhookTransport = nil,
        webhookBound = false,
        webhookDisconnectors = {},
        lastWebhookResultKey = nil,
        runtimeConnections = {},
        reconnectQueued = false,
        autoExecuteQueued = false,
        lastChallengeAttempt = 0,
        lastChallengeNotice = 0,
        challengePendingType = nil,
        challengePendingAt = 0,
        challengeJoinCooldownUntil = 0,
        lastChallengeType = nil,
        autoMapMacroStartedFor = nil,
        lastInfiniteSellWave = nil,
        session = {
            wins = 0,
            losses = 0,
        },
        challenger = {
            enabled = false,
            types = {
                Normal = true,
                Daily = false,
            },
            priority = "Normal",
            autoLoadMacro = true,
            autoReturnLobby = true,
        },
        runtimeSettings = {
            antiAfk = false,
            autoReconnect = false,
            autoExecute = false,
        },
        autoStory = {
            autoReady = false,
            autoPlace = false,
            placeSlots = {},
            autoUpgrade = false,
            upgradeSlots = {},
            autoNext = false,
            autoReplay = false,
            autoReturnLobby = false,
        },
        autoInfinite = {
            enabled = false,
            autoReady = false,
            autoPlace = false,
            placeSlots = {},
            autoUpgrade = false,
            upgradeSlots = {},
            autoReplay = false,
            autoReturnLobby = false,
            autoSellAll = false,
            sellWave = 50,
        },
        webhook = {
            enabled = false,
            url = "",
        },
    }, Controller)
end

function Controller:Start()
    if self.running then return self:GetState() end
    self.running = true
    self.generation = self.generation + 1
    local generation = self.generation

    if not self.webhookBound then
        self.webhookBound = true

        table.insert(self.webhookDisconnectors, self.tracker:on("matchPhaseChanged", function(payload)
            if payload.to == "PLAYING" then
                self.lastWebhookResultKey = nil
                self.lastPostMatchAction = nil
                self.lastReadyAttempt = 0
                self.readySubmitted = false
                self.lastInfiniteSellWave = nil
            elseif payload.to == "FINISHED" then
                self.lastReadyAttempt = 0
                self.readySubmitted = false
                task.spawn(function()
                    self:_handleFinishedMatch()
                end)
            end
        end))
    end

    table.insert(self.runtimeConnections, self.tracker:on("mapChanged", function()
        self.autoMapMacroStartedFor = nil
    end))

    if LocalPlayer then
        table.insert(self.runtimeConnections, LocalPlayer.Idled:Connect(function()
            if not self.runtimeSettings.antiAfk then return end

            local env = (getgenv and getgenv()) or _G
            local getConnections = rawget(env, "getconnections")
            if type(getConnections) == "function" then
                pcall(function()
                    for _, connection in ipairs(getConnections(LocalPlayer.Idled)) do
                        if type(connection.Disable) == "function" then
                            connection:Disable()
                        elseif type(connection.Disconnect) == "function" then
                            connection:Disconnect()
                        end
                    end
                end)
            end

            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)
        end))
    end

    local function requestReconnect(reason)
        if not self.runtimeSettings.autoReconnect or self.reconnectQueued then return end
        self.reconnectQueued = true

        self.tracker.events:emit("reconnectTriggered", {
            reason = tostring(reason or "Disconnected"),
        })

        task.delay(1.25, function()
            if not self.running then return end

            if self.runtimeSettings.autoExecute then
                self:_queueAutoExecute()
            end

            local ok, err = pcall(function()
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            end)

            if not ok then
                self.reconnectQueued = false
                self.tracker.events:emit("actionError", {
                    message = "Auto Reconnect failed: " .. tostring(err),
                })
            end
        end)
    end

    local errorSignal = safe(function()
        return GuiService.ErrorMessageChanged
    end)

    if errorSignal then
        table.insert(self.runtimeConnections, errorSignal:Connect(function(message)
            if not self.runtimeSettings.autoReconnect or self.reconnectQueued then return end
            local lower = tostring(message or ""):lower()
            if lower == "" then return end

            local reconnectable = lower:find("disconnect", 1, true)
                or lower:find("desconect", 1, true)
                or lower:find("connection", 1, true)
                or lower:find("conex", 1, true)
                or lower:find("idle", 1, true)
                or lower:find("inatividade", 1, true)
                or lower:find("error code: 267", 1, true)
                or lower:find("error code: 277", 1, true)
                or lower:find("error code: 279", 1, true)

            if not reconnectable then return end
            requestReconnect(message)
        end))
    end

    -- Roblox's disconnect screen is normally an ErrorPrompt under
    -- CoreGui.RobloxPromptGui.promptOverlay. This is more reliable than
    -- GuiService.ErrorMessageChanged on executors where that signal is silent.
    local promptOverlay = safe(function()
        local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
        return promptGui and promptGui:FindFirstChild("promptOverlay")
    end)

    if promptOverlay then
        table.insert(self.runtimeConnections, promptOverlay.ChildAdded:Connect(function(child)
            task.delay(0.1, function()
                if not self.runtimeSettings.autoReconnect then return end
                local name = tostring(child and child.Name or ""):lower()
                local title = child and child:FindFirstChild("ErrorTitle", true)
                local messageArea = child and child:FindFirstChild("ErrorMessage", true)
                local text = tostring(readText(title) or "") .. " " .. tostring(readText(messageArea) or "")
                local lower = text:lower()

                if name:find("errorprompt", 1, true)
                    or lower:find("disconnected", 1, true)
                    or lower:find("disconnect", 1, true)
                    or lower:find("desconect", 1, true)
                    or lower:find("connection", 1, true)
                    or lower:find("conex", 1, true)
                    or lower:find("idle", 1, true)
                    or lower:find("inatividade", 1, true)
                then
                    requestReconnect(text ~= " " and text or child.Name)
                end
            end)
        end))
    end

    local snapshot = self.tracker:start()
    task.spawn(function()
        while self.running and self.generation == generation do
            local ok, err = pcall(function() self:_automationStep() end)
            if not ok then self.tracker.events:emit("actionError", {message = tostring(err)}) end
            task.wait(1)
        end
    end)
    if snapshot.match.finished then
        task.spawn(function() self:_handleFinishedMatch() end)
    end
    return snapshot
end

function Controller:Stop()
    self.running = false
    self.generation = self.generation + 1
    if self.recorder.recording then
        self:StopRecording()
    end

    self.replay:stop()

    for _, disconnect in ipairs(self.webhookDisconnectors) do
        safe(disconnect)
    end
    table.clear(self.webhookDisconnectors)
    self.webhookBound = false

    for _, connection in ipairs(self.runtimeConnections or {}) do
        if typeof(connection) == "RBXScriptConnection" then
            safe(function() connection:Disconnect() end)
        elseif type(connection) == "function" then
            safe(connection)
        end
    end
    table.clear(self.runtimeConnections)

    for _, connection in ipairs(self.uiConnections or {}) do connection:Disconnect() end
    for _, disconnect in ipairs(self.uiDisconnectors or {}) do disconnect() end
    self.uiConnections, self.uiDisconnectors = {}, {}
    self.tracker:stop()
end

function Controller:On(eventName, callback)
    return self.tracker:on(eventName, callback)
end

function Controller:GetState()
    return self.tracker:getSnapshot()
end

function Controller:GetCurrentMapProfile()
    return MapProfiles.captureRuntimeGeometry()
end

function Controller:GetEquippedUnits()
    local result = {}

    if not LocalPlayer then
        return result
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local spawnUnits = playerGui and playerGui:FindFirstChild("spawn_units")
    local lives = spawnUnits and spawnUnits:FindFirstChild("Lives")
    local frame = lives and lives:FindFirstChild("Frame")
    local unitsRoot = frame and frame:FindFirstChild("Units")

    for slot = 1, 6 do
        local slotFrame = unitsRoot and unitsRoot:FindFirstChild(tostring(slot))
        local entry = {
            slot = slot,
            name = "Empty",
            equipped = false,
            locked = false,
        }

        if slotFrame then
            local uuid = safe(function()
                return slotFrame:GetAttribute("_equipped_frame_unit_uuid")
            end)

            entry.uuid = uuid
            entry.equipped = type(uuid) == "string" and uuid ~= ""

            local locked = slotFrame:FindFirstChild("locked")
            if locked and locked:IsA("GuiObject") then
                entry.locked = locked.Visible == true
            end

            local internalId
            local main = slotFrame:FindFirstChild("Main")
            local view = main and main:FindFirstChild("View")
            local worldModel = view and view:FindFirstChildOfClass("WorldModel")

            if worldModel then
                for _, model in ipairs(worldModel:GetChildren()) do
                    if model:IsA("Model") then
                        internalId = model.Name
                        break
                    end
                end
            end

            entry.unitId = internalId
            if entry.equipped and internalId then
                entry.name = getUnitDisplayName(internalId)
                    or ("Unit " .. tostring(slot))
            elseif not entry.equipped then
                entry.name = "Empty"
            end

            local costFrame = slotFrame:FindFirstChild("Cost")
            local text = costFrame and costFrame:FindFirstChild("text")
            if text and text:IsA("TextLabel") then
                entry.cost = parseNumber(text.Text)
            end
        end

        table.insert(result, entry)
    end

    return result
end

function Controller:SetPlacementMarker(slot, cframe, unitName)
    slot = tonumber(slot)

    if not slot or slot % 1 ~= 0 or slot < 1 or slot > 6 then
        return false, "invalid slot"
    end

    if typeof(cframe) ~= "CFrame" then
        return false, "invalid position"
    end

    self.placementMarkers[slot] = {
        slot = slot,
        unitName = tostring(unitName or ("Unit " .. tostring(slot))),
        cframe = cframeToArray(cframe),
        position = vectorToArray(cframe.Position),
        savedAt = os.time(),
    }

    return true, deepCopy(self.placementMarkers[slot])
end

function Controller:GetPlacementMarkers()
    return deepCopy(self.placementMarkers)
end

function Controller:ClearPlacementMarker(slot)
    slot = tonumber(slot)

    if slot then
        self.placementMarkers[slot] = nil
    else
        table.clear(self.placementMarkers)
    end

    return true
end

function Controller:GetAutoStoryPlan()
    local plan = deepCopy(self.autoStory)
    plan.markers = deepCopy(self.placementMarkers)
    return plan
end

-- Endpoint names are grounded in the supplied match dump. Server argument
-- contracts must also be checked in a live game when its version changes.
function Controller:_invoke(name, ...)
    local endpoints = ReplicatedStorage:FindFirstChild("endpoints")
    local clientToServer = endpoints and endpoints:FindFirstChild("client_to_server")
    local endpoint = clientToServer and clientToServer:FindFirstChild(name)
    if not endpoint then return false, "Game action unavailable: " .. name end
    local args = table.pack(...)
    local ok, result = pcall(function()
        if endpoint:IsA("RemoteFunction") then
            return endpoint:InvokeServer(table.unpack(args, 1, args.n))
        elseif endpoint:IsA("RemoteEvent") then
            endpoint:FireServer(table.unpack(args, 1, args.n))
            return true
        end
        error("Unsupported endpoint type")
    end)
    if not ok then return false, tostring(result) end
    if result == false then return false, "Game rejected action: " .. name end
    return true, result
end

function Controller:_ownModels()
    local result = {}
    local root = Workspace:FindFirstChild("_UNITS")
    if not root or not LocalPlayer then return result end
    for _, model in ipairs(root:GetChildren()) do
        local stats = model:FindFirstChild("_stats")
        local owner = stats and stats:FindFirstChild("player")
        if owner and owner:IsA("ObjectValue") and owner.Value == LocalPlayer then
            table.insert(result, model)
        end
    end
    return result
end

function Controller:_matchingModel(unit, position)
    local nearest, distance
    for _, model in ipairs(self:_ownModels()) do
        local stats = model:FindFirstChild("_stats")
        local id = getValue(stats, "id") or model.Name
        if (unit.uuid and getValue(stats, "uuid") == unit.uuid) or (unit.unitId and id == unit.unitId) then
            local d = position and (model:GetPivot().Position - position).Magnitude or 0
            if not distance or d < distance then nearest, distance = model, d end
        end
    end
    if position and (not distance or distance > 3) then return nil end
    return nearest
end

function Controller:_readReadyUI()
    if not LocalPlayer then
        return nil
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local voteGui = playerGui and playerGui:FindFirstChild("VoteStart")
    local holder = voteGui and voteGui:FindFirstChild("Holder")

    if not voteGui or not holder then
        return nil
    end

    if voteGui:IsA("ScreenGui") and voteGui.Enabled == false then
        return nil
    end

    if holder:IsA("GuiObject") and holder.Visible == false then
        return nil
    end

    local title = readText(holder:FindFirstChild("Title"))
    local description = readText(holder:FindFirstChild("Description"))
    local button = findPath(holder, "ButtonHolder", "Yes")
    local buttonText = readText(findPath(button, "Main", "text"))
    local locked = button and button:FindFirstChild("Locked")

    if title ~= "Ready?" or buttonText ~= "Start" then
        return nil
    end

    if not button or (button:IsA("GuiObject") and button.Visible == false) then
        return nil
    end

    if locked and locked:IsA("GuiObject") and locked.Visible == true then
        return nil
    end

    local votes, required
    if type(description) == "string" then
        local a, b = description:match("(%d+)%s*/%s*(%d+)")
        votes = tonumber(a)
        required = tonumber(b)
    end

    return {
        visible = true,
        votes = votes,
        required = required,
        complete = required ~= nil and required > 0 and votes ~= nil and votes >= required,
    }
end

function Controller:_executorFunction(...)
    local env = (getgenv and getgenv()) or _G

    for index = 1, select("#", ...) do
        local name = select(index, ...)
        local value = rawget(env, name)
        if type(value) == "function" then
            return value
        end
    end

    local syn = rawget(env, "syn")
    if type(syn) == "table" and type(syn.queue_on_teleport) == "function" then
        return syn.queue_on_teleport
    end

    local fluxus = rawget(env, "fluxus")
    if type(fluxus) == "table" and type(fluxus.queue_on_teleport) == "function" then
        return fluxus.queue_on_teleport
    end

    return nil
end

function Controller:_queueAutoExecute()
    if self.autoExecuteQueued then
        return true, "already queued"
    end

    local queueFn = self:_executorFunction("queue_on_teleport", "queueonteleport")
    if type(queueFn) ~= "function" then
        return false, "queue_on_teleport unavailable"
    end

    local ok, err = pcall(queueFn, Core.LOADER_COMMAND)
    if not ok then
        return false, tostring(err)
    end

    self.autoExecuteQueued = true
    return true
end

function Controller:SetRuntimeConfig(config)
    assert(type(config) == "table", "Runtime config must be a table")

    for key, value in pairs(config) do
        if self.runtimeSettings[key] ~= nil then
            self.runtimeSettings[key] = value == true
        end
    end

    if config.autoExecute == true then
        local ok, err = self:_queueAutoExecute()
        if not ok then
            self.tracker.events:emit("actionError", {
                message = "Auto Execute unavailable: " .. tostring(err),
            })
        end
    end

    self.tracker.events:emit("runtimeConfigChanged", deepCopy(self.runtimeSettings))
    return deepCopy(self.runtimeSettings)
end

function Controller:GetRuntimeConfig()
    return deepCopy(self.runtimeSettings)
end

function Controller:SetChallengerConfig(config)
    assert(type(config) == "table", "Challenger config must be a table")

    if type(config.types) == "table" then
        local nextTypes = {
            Normal = false,
            Daily = false,
        }

        for key, value in pairs(config.types) do
            if key == "Normal" or key == "Daily" then
                nextTypes[key] = value == true
            elseif type(value) == "string" and (value == "Normal" or value == "Daily") then
                nextTypes[value] = true
            end
        end

        self.challenger.types = nextTypes
    elseif config.kind ~= nil then
        -- Backward compatibility with the previous single-select setting.
        local kind = tostring(config.kind) == "Daily" and "Daily" or "Normal"
        self.challenger.types = {
            Normal = kind == "Normal",
            Daily = kind == "Daily",
        }
        self.challenger.priority = kind
    end

    if config.priority ~= nil then
        local priority = tostring(config.priority)
        if priority == "Normal" or priority == "Daily" then
            self.challenger.priority = priority
        end
    end

    for _, key in ipairs({"enabled", "autoLoadMacro", "autoReturnLobby"}) do
        if config[key] ~= nil then
            self.challenger[key] = config[key] == true
        end
    end

    self.tracker.events:emit("challengerConfigChanged", deepCopy(self.challenger))
    return deepCopy(self.challenger)
end

function Controller:GetChallengerConfig()
    return deepCopy(self.challenger)
end

local function normalizedGuiText(value)
    if type(value) ~= "string" then return "" end
    return value
        :gsub("<.->", "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
        :lower()
end

function Controller:_readChallengeBoard(kind)
    if not LocalPlayer then return nil end
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil end

    local wantedTitle = kind == "Daily" and "daily challenge" or "current challenge"
    local best

    for _, surface in ipairs(playerGui:GetDescendants()) do
        if surface:IsA("SurfaceGui") and surface.Enabled ~= false then
            local title = surface:FindFirstChild("LevelTitle", true)
            if normalizedGuiText(readText(title)) == wantedTitle then
                local levelInfo = surface:FindFirstChild("LevelInfo", true)
                local data = {
                    kind = kind,
                    surface = surface,
                    mapName = normalizedGuiText(readText(levelInfo and levelInfo:FindFirstChild("MapName"))),
                    levelName = normalizedGuiText(readText(levelInfo and levelInfo:FindFirstChild("LevelName"))),
                    difficulty = normalizedGuiText(readText(levelInfo and levelInfo:FindFirstChild("Difficulty"))),
                }

                if data.mapName ~= "" or data.levelName ~= "" or data.difficulty ~= "" then
                    best = data
                    break
                end
            end
        end
    end

    return best
end

function Controller:_doorMetadata(door)
    if not door or not door:IsA("BasePart") then return nil end
    local surface = door:FindFirstChild("Surface")
        or door:FindFirstChildWhichIsA("SurfaceGui")

    if not surface then
        surface = door:FindFirstChild("Surface", true)
    end

    return {
        door = door,
        mapName = normalizedGuiText(readText(surface and surface:FindFirstChild("MapName", true))),
        levelName = normalizedGuiText(readText(surface and surface:FindFirstChild("LevelName", true))),
        difficulty = normalizedGuiText(readText(surface and surface:FindFirstChild("Difficulty", true))),
        state = normalizedGuiText(readText(surface and surface:FindFirstChild("State", true))),
    }
end

function Controller:_dailyTaggedDoor()
    local tagged = CollectionService:GetTagged("_daily_challenge_lobby_models")

    for _, model in ipairs(tagged) do
        if model and model.Parent then
            local fallback

            for _, obj in ipairs(model:GetDescendants()) do
                if obj:IsA("BasePart") then
                    local lower = obj.Name:lower()
                    if lower == "door" then
                        return obj
                    end
                    fallback = fallback or obj
                end
            end

            if model:IsA("Model") and model.PrimaryPart then
                return model.PrimaryPart
            end

            if fallback then
                return fallback
            end
        end
    end

    -- Dump-confirmed fallback path if CollectionService tagging is unavailable.
    local challenges = Workspace:FindFirstChild("_CHALLENGES")
    local daily = challenges and challenges:FindFirstChild("DailyChallenge")

    if daily then
        for _, obj in ipairs(daily:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name:lower() == "door" then
                return obj
            end
        end
    end

    return nil
end

function Controller:_findChallengeDoor(kind)
    local board = self:_readChallengeBoard(kind)

    if kind == "Daily" then
        local tagged = self:_dailyTaggedDoor()
        if tagged then
            return tagged, board
        end
    end

    local lobbies = Workspace:FindFirstChild("_LOBBIES")
    local story = lobbies and lobbies:FindFirstChild("Story")
    if not story then
        return nil, board
    end

    local best, bestScore
    local dailyBoard = kind == "Normal" and self:_readChallengeBoard("Daily") or nil

    for _, obj in ipairs(story:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name:lower() == "door" then
            local meta = self:_doorMetadata(obj)

            if meta then
                local score = 0
                if board then
                    if board.mapName ~= "" and meta.mapName == board.mapName then score += 8 end
                    if board.levelName ~= "" and meta.levelName == board.levelName then score += 5 end
                    if board.difficulty ~= "" and meta.difficulty == board.difficulty then score += 10 end
                end

                local isPlainStory = meta.difficulty == ""
                    or meta.difficulty == "normal"
                    or meta.difficulty == "hard"

                local isDailyMatch = dailyBoard
                    and dailyBoard.mapName ~= ""
                    and meta.mapName == dailyBoard.mapName
                    and (dailyBoard.levelName == "" or meta.levelName == dailyBoard.levelName)
                    and (dailyBoard.difficulty == "" or meta.difficulty == dailyBoard.difficulty)

                if kind == "Normal" and not isPlainStory and not isDailyMatch then
                    score += 2
                elseif kind == "Daily" and isDailyMatch then
                    score += 20
                end

                if score > 0 and (not best or score > bestScore) then
                    best = obj
                    bestScore = score
                end
            end
        end
    end

    return best, board
end

function Controller:_teleportIntoChallengeDoor(door, kind)
    if not LocalPlayer or not LocalPlayer.Character then
        return false, "character unavailable"
    end

    local root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then
        return false, "character unavailable"
    end

    if not door or not door:IsA("BasePart") then
        return false, "challenge door unavailable"
    end

    local ok, err = pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero

        -- Put the character immediately inside the actual Door trigger rather
        -- than teleporting to the reward board or a destination marker.
        root.CFrame = door.CFrame * CFrame.new(0, 0, math.max(0.35, door.Size.Z * 0.15))
        task.wait(0.12)
        root.CFrame = door.CFrame
        task.wait(0.35)
    end)

    if not ok then
        return false, tostring(err)
    end

    self.tracker.events:emit("challengerPortalActivated", {
        method = "DoorTeleport",
        kind = kind,
        target = fullName(door),
    })

    return true
end

function Controller:_matchmakingVisible()
    if not LocalPlayer then return nil end
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local gui = playerGui and playerGui:FindFirstChild("MatchmakingUI")
    if not gui then return nil end
    if gui:IsA("ScreenGui") and gui.Enabled == false then return nil end
    return gui
end

function Controller:_buttonText(button)
    if not button then return "" end
    local chunks = {}

    local own = readText(button)
    if own and own ~= "" then table.insert(chunks, own) end

    for _, child in ipairs(button:GetDescendants()) do
        local text = readText(child)
        if text and text ~= "" then
            table.insert(chunks, text)
        end
    end

    return normalizedGuiText(table.concat(chunks, " "))
end

function Controller:_activatePlayHere()
    local gui = self:_matchmakingVisible()
    if not gui then
        return false, "waiting for matchmaking choice"
    end

    local exact
    local candidates = {}

    for _, item in ipairs(gui:GetDescendants()) do
        if item:IsA("GuiButton") and item.Visible and item.Active ~= false then
            local text = self:_buttonText(item)
            local compact = text:gsub("%s+", "")

            if compact:find("playhere", 1, true) then
                exact = item
                break
            end

            local size = item.AbsoluteSize
            local area = size.X * size.Y
            if area >= 7000 then
                table.insert(candidates, item)
            end
        end
    end

    local button = exact

    if not button and #candidates > 0 then
        -- The popup shown by Daily has Play Here on the left and Find Match on
        -- the right. Exclude any candidate explicitly labelled Find Match,
        -- then pick the left-most large action button.
        local filtered = {}
        for _, candidate in ipairs(candidates) do
            local text = self:_buttonText(candidate)
            if not text:find("find match", 1, true)
                and not text:find("matchmaking", 1, true)
            then
                table.insert(filtered, candidate)
            end
        end

        candidates = #filtered > 0 and filtered or candidates

        table.sort(candidates, function(a, b)
            return a.AbsolutePosition.X < b.AbsolutePosition.X
        end)

        button = candidates[1]
    end

    if not button then
        return false, "Play Here button not found"
    end

    local ok = pcall(function()
        button:Activate()
    end)

    if not ok then
        local center = button.AbsolutePosition + (button.AbsoluteSize / 2)
        ok = pcall(function()
            VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
        end)
    end

    if not ok then
        return false, "could not activate Play Here"
    end

    self.tracker.events:emit("dailyPlayHereActivated", {})
    return true
end

function Controller:_challengeOrder()
    local selected = self.challenger.types or {}
    local priority = self.challenger.priority == "Daily" and "Daily" or "Normal"
    local other = priority == "Daily" and "Normal" or "Daily"
    local order = {}

    -- Priority decides which selected type is attempted first. Once one type
    -- has successfully started, alternate to the other selected type on the
    -- next lobby return instead of starving it forever.
    if selected.Normal and selected.Daily and self.lastChallengeType then
        local nextType = self.lastChallengeType == "Daily" and "Normal" or "Daily"
        table.insert(order, nextType)
        table.insert(order, self.lastChallengeType)
        return order
    end

    if selected[priority] then table.insert(order, priority) end
    if selected[other] then table.insert(order, other) end

    return order
end

function Controller:RunChallengerStep(force)
    if not self.challenger.enabled and not force then
        return false, "Auto Challengers disabled"
    end

    local isLobby = game.PlaceId == 94823097601547 or self.tracker.state.map.isLobby == true
    if not isLobby then
        return false, "not in lobby"
    end

    local now = os.clock()

    if self.challengePendingType == "Daily" then
        local clicked, clickErr = self:_activatePlayHere()
        if clicked then
            self.challengePendingType = nil
            self.lastChallengeType = "Daily"
            self.challengeJoinCooldownUntil = now + 8
            return true
        end

        if now - (self.challengePendingAt or 0) < 8 then
            return false, clickErr
        end

        self.challengePendingType = nil
    end

    if not force and now < (self.challengeJoinCooldownUntil or 0) then
        return false, "waiting"
    end

    if not force and now - (self.lastChallengeAttempt or 0) < 2 then
        return false, "waiting"
    end

    self.lastChallengeAttempt = now

    local order = self:_challengeOrder()
    if #order == 0 then
        return false, "select at least one Challenger type"
    end

    local lastError = "challenge door not found"

    for _, kind in ipairs(order) do
        local door = self:_findChallengeDoor(kind)

        if door then
            local ok, err = self:_teleportIntoChallengeDoor(door, kind)

            if ok then
                self.tracker.events:emit("challengerJoinAttempt", {
                    kind = kind,
                })

                if kind == "Daily" then
                    self.challengePendingType = "Daily"
                    self.challengePendingAt = os.clock()
                    self.challengeJoinCooldownUntil = os.clock() + 1
                else
                    self.lastChallengeType = "Normal"
                    self.challengeJoinCooldownUntil = os.clock() + 8
                end

                return true
            end

            lastError = err or lastError
        end
    end

    if now - (self.lastChallengeNotice or 0) >= 15 then
        self.lastChallengeNotice = now
        self.tracker.events:emit("actionError", {
            message = tostring(lastError),
        })
    end

    return false, lastError
end

function Controller:_findMacroForCurrentMap()
    local state = self.tracker.state
    local area = state.map.area
    local level = state.map.level
    local items = self.macros:list()

    for index = #items, 1, -1 do
        local item = items[index]
        if level and item.level == level and (not area or not item.area or item.area == area) then
            return item.id
        end
    end

    for index = #items, 1, -1 do
        local item = items[index]
        if area and item.area == area then
            return item.id
        end
    end

    return nil
end

function Controller:AutoLoadCurrentMapMacro()
    if self.recorder.recording or self.replay.running then
        return false, "macro busy"
    end

    local state = self.tracker.state
    local level = state.map.level
    local area = state.map.area
    if not level and not area then
        return false, "map not ready"
    end

    local id = self:_findMacroForCurrentMap()
    if not id then
        return false, "no saved macro for this map"
    end

    local ok, err = self:SelectMacro(id)
    if not ok then return false, err end

    local started, replayErr = self:StartSelectedMacroReplay()
    if started then
        self.autoMapMacroStartedFor = tostring(area or "") .. "|" .. tostring(level or "")
        self.tracker.events:emit("mapMacroLoaded", {
            id = id,
            area = area,
            level = level,
        })
    end

    return started, replayErr
end

function Controller:_autoLoadMapMacroStep()
    if not self.challenger.enabled or not self.challenger.autoLoadMacro then return end
    if self.recorder.recording or self.replay.running then return end

    local state = self.tracker.state
    if state.match.phase ~= "STARTING" and state.match.phase ~= "PLAYING" then return end

    local key = tostring(state.map.area or "") .. "|" .. tostring(state.map.level or "")
    if key == "|" or self.autoMapMacroStartedFor == key then return end

    local ok = self:AutoLoadCurrentMapMacro()
    if ok then
        self.autoMapMacroStartedFor = key
    end
end

function Controller:_dispatch(action)
    if self.actionAdapter then return self.actionAdapter(action) end
    if action.kind == "ready" then
        return self:_invoke("vote_start")
    elseif action.kind == "place" then
        return self:_invoke("spawn_unit", action.unit.uuid, action.cframe)
    elseif action.kind == "upgrade" then
        return self:_invoke("upgrade_unit_ingame", action.model)
    elseif action.kind == "sell" then
        return self:_invoke("sell_unit_ingame", action.model)
    elseif action.kind == "next" then
        return self:_invoke("set_game_finished_vote", "next_story")
    elseif action.kind == "replay" then
        return self:_invoke("set_game_finished_vote", "replay")
    elseif action.kind == "lobby" then
        if self.runtimeSettings.autoExecute then
            self:_queueAutoExecute()
        end
        return self:_invoke("teleport_back_to_lobby")
    end
    return false, "Unsupported action"
end

function Controller:_automationStep()
    local state = self.tracker.state
    if not self.running then return end

    local isLobby = game.PlaceId == 94823097601547 or state.map.isLobby == true
    if isLobby then
        if self.challenger.enabled then
            self:RunChallengerStep(false)
        end
        return
    end

    self:_autoLoadMapMacroStep()

    local mode = detectMode(state.map.level)
    local infiniteActive = mode == "Infinite" and self.autoInfinite.enabled
    local config = infiniteActive and self.autoInfinite or self.autoStory

    -- The game's own VoteStart GUI is the authoritative Ready signal.
    -- Replay and Next can reuse the same server and recreate/show this GUI
    -- while Workspace values from the previous round are still stale.
    local readyInfo = self:_readReadyUI()
    local readyWindow = readyInfo ~= nil

    if readyWindow and not self.readyWindowActive then
        self.readyWindowActive = true
        self.readySubmitted = readyInfo.complete == true
        self.lastReadyAttempt = 0
        self.lastPostMatchAction = nil
    elseif not readyWindow then
        self.readyWindowActive = false
        self.readySubmitted = false
    elseif readyInfo.complete then
        self.readySubmitted = true
    end

    -- Vote only while the visible Ready?/Start UI exists. A temporary server
    -- rejection is expected during transitions and is retried silently.
    if config.autoReady and readyWindow and not self.readySubmitted then
        local now = os.clock()
        if now - (self.lastReadyAttempt or 0) >= 1 then
            self.lastReadyAttempt = now
            local ok = self:_dispatch({kind = "ready"})
            if ok then
                self.readySubmitted = true
            end
            return
        end
    end

    if self.replay.running or self.recorder.recording then return end

    -- The visible Ready GUI wins over a stale GameFinished value after
    -- same-server Replay/Next transitions.
    if state.match.finished and not readyWindow then
        local shouldReturnLobby = config.autoReturnLobby
            or (self.challenger.enabled and self.challenger.autoReturnLobby)
        local kind = shouldReturnLobby and "lobby"
            or config.autoReplay and "replay"
            or (not infiniteActive and config.autoNext) and "next"
        if not kind or self.lastPostMatchAction == kind then return end
        local result = self:_readResult()
        if not result or (kind == "next" and result.outcome ~= "victory") then return end
        -- Give the result handler time to read rewards before leaving.
        if not self.lastWebhookResultKey or self.webhookBusy then return end
        local ok, err = self:_dispatch({kind = kind})
        if ok then
            self.lastPostMatchAction = kind
            -- Replay/Next may remain in this server. The next VoteStart window
            -- will clear this again and submit a fresh Ready vote.
            if kind == "replay" or kind == "next" then
                self.readyWindowActive = false
                self.readySubmitted = false
                self.lastReadyAttempt = 0
            end
        else
            error(err or "Post-match action failed")
        end
        return
    end
    if state.match.phase ~= "PLAYING" and state.match.phase ~= "STARTING" then return end

    if infiniteActive
        and config.autoSellAll
        and state.match.phase == "PLAYING"
        and tonumber(state.match.wave)
        and state.match.wave >= (tonumber(config.sellWave) or 50)
    then
        local models = self:_ownModels()

        for _, model in ipairs(models) do
            local ok, err = self:_dispatch({
                kind = "sell",
                model = model,
            })

            if not ok then
                self.tracker.events:emit("actionError", {
                    message = "Sell All failed: " .. tostring(err),
                })
            end

            task.wait(0.08)
        end

        self.lastInfiniteSellWave = state.match.wave
        return
    end

    local equipped = self:GetEquippedUnits()
    if config.autoPlace then
        for _, slot in ipairs(config.placeSlots) do
            if not self.running then return end
            local unit, marker = equipped[slot], self.placementMarkers[slot]
            if unit and unit.equipped and not unit.locked and marker then
                local cf = CFrame.new(table.unpack(marker.cframe))
                if not self:_matchingModel(unit, cf.Position) and (not unit.cost or not state.player.money or state.player.money >= unit.cost) then
                    local ok, err = self:_dispatch({kind = "place", unit = unit, cframe = cf, slot = slot})
                    if not ok then error(err or "Placement failed") end
                    return -- At most one placement per tick; wait for replication.
                end
            end
        end
    end
    if config.autoUpgrade then
        for _, model in ipairs(self:_ownModels()) do
            if not self.running then return end
            local stats = model:FindFirstChild("_stats")
            local id, uuid = getValue(stats, "id") or model.Name, getValue(stats, "uuid")
            for _, slot in ipairs(config.upgradeSlots) do
                local unit = equipped[slot]
                local level = tonumber(getValue(stats, "upgrade")) or 0
                local maximum = tonumber(getValue(stats, "max_upgrade"))
                if unit and unit.equipped and (uuid == unit.uuid or id == unit.unitId) and (not maximum or maximum <= 0 or level < maximum) then
                    local ok, err = self:_dispatch({kind = "upgrade", model = model, slot = slot})
                    if not ok then error(err or "Upgrade failed") end
                    task.wait(0.25)
                    break
                end
            end
        end
    end
end

function Controller:_executeReplay(payload)
    local event = payload.event
    if not event or (event.type ~= "PLACE_DETECTED" and event.type ~= "UPGRADE_DETECTED") then
        -- UNIT_REMOVED can also mean death or cleanup: never infer a sale.
        return true
    end
    local recorded = event.data and event.data.unit
    if not recorded then return false, "Macro is missing unit data" end
    local generation = self.replay.generation
    local deadline = os.clock() + 60
    local model = self.replayUnits[recorded.uuid]
    local cf = recorded.cframe and CFrame.new(table.unpack(recorded.cframe))
    if not cf then return false, "Macro is missing placement coordinates" end
    local lastError = "Action was not confirmed by game state"
    local nextAttempt = 0
    while self.running and self.replay.running and self.replay.generation == generation and os.clock() < deadline do
        local state = self.tracker.state
        if state.match.finished then return false, "Match ended during replay" end
        if state.match.phase == "PLAYING" or state.match.phase == "STARTING" then
            if not model or not model.Parent then model = self:_matchingModel(recorded, cf.Position) end
            if event.type == "PLACE_DETECTED" and model then
                self.replayUnits[recorded.uuid] = model
                return true
            end
            if event.type == "UPGRADE_DETECTED" and model then
                local current = tonumber(getValue(model:FindFirstChild("_stats"), "upgrade")) or 0
                if current >= (tonumber(event.data.to) or tonumber(recorded.upgrade) or 0) then return true end
            end
            if os.clock() >= nextAttempt then
                nextAttempt = os.clock() + 1
                local action
                if event.type == "PLACE_DETECTED" then
                    local candidates = {}
                    for _, unit in ipairs(self:GetEquippedUnits()) do
                        if unit.equipped and not unit.locked then
                            if unit.uuid == recorded.uuid then candidates = {unit}; break end
                            if unit.unitId == recorded.unitId then table.insert(candidates, unit) end
                        end
                    end
                    if #candidates ~= 1 then return false, "Recorded unit is missing or ambiguous in equipped slots" end
                    local unit = candidates[1]
                    if not unit.cost or not state.player.money or state.player.money >= unit.cost then
                        action = {kind = "place", unit = unit, cframe = cf, slot = unit.slot, event = event}
                    end
                elseif model then
                    action = {kind = "upgrade", model = model, event = event}
                end
                if action then
                    local ok, err = self:_dispatch(action)
                    if not ok then lastError = tostring(err or lastError) end
                end
            end
        end
        task.wait(0.1)
    end
    return false, self.replay.generation ~= generation and "Replay cancelled" or lastError
end

function Controller:SetActionAdapter(callback)
    assert(callback == nil or type(callback) == "function", "action adapter must be a function or nil")
    self.actionAdapter = callback
end

function Controller:StartSelectedMacroReplay()
    local macro = self.macros:get()

    if not macro then
        return false, "no macro selected"
    end

    local state = self.tracker.state
    local macroArea = macro.map and macro.map.area or nil
    local macroLevel = macro.map and macro.map.level or nil

    if macroArea and state.map.area and macroArea ~= state.map.area then
        return false, "wrong map"
    end

    if macroLevel and state.map.level and macroLevel ~= state.map.level then
        return false, "wrong level"
    end

    if self.recorder.recording then return false, "stop recording before replay" end
    self.replayUnits = {}
    return self.replay:start(macro, function(event, index, total, finished, replayError)
        if finished then
            self.tracker.events:emit("macroReplayFinished", {
                macro = macro.name,
                total = total,
                error = replayError,
            })
            return
        end

        local payload = {
            macro = macro.name,
            index = index,
            total = total,
            event = deepCopy(event),
            marker = nil,
        }

        if event and event.type == "PLACE_DETECTED" then
            local unit = event.data and event.data.unit or nil
            local unitId = unit and (unit.unitId or unit.name) or nil
            local visualName = getUnitDisplayName(unitId)

            if visualName then
                payload.unitName = visualName
            end

            for slot, marker in pairs(self.placementMarkers) do
                local equipped = self:GetEquippedUnits()[slot]
                if equipped and equipped.name == visualName then
                    payload.marker = deepCopy(marker)
                    payload.slot = slot
                    break
                end
            end
        end

        self.tracker.events:emit("macroReplayEvent", payload)

        return self:_executeReplay(payload)
    end)
end

function Controller:StopMacroReplay()
    self.replay:stop()
    return true
end

function Controller:GetMacroReplayStatus()
    return self.replay:getStatus()
end

function Controller:SetAutoStoryConfig(config)
    assert(type(config) == "table", "Auto Story config must be a table")

    for key, value in pairs(config) do
        if key == "placeSlots" or key == "upgradeSlots" then
            if type(value) == "table" then
                self.autoStory[key] = deepCopy(value)
            end
        elseif self.autoStory[key] ~= nil then
            self.autoStory[key] = value == true
        end
    end

    if config.autoNext == true then
        self.autoStory.autoReplay = false
        self.autoStory.autoReturnLobby = false
    elseif config.autoReplay == true then
        self.autoStory.autoNext = false
        self.autoStory.autoReturnLobby = false
    elseif config.autoReturnLobby == true then
        self.autoStory.autoNext = false
        self.autoStory.autoReplay = false
    end

    self.tracker.events:emit("autoStoryConfigChanged", deepCopy(self.autoStory))
    return deepCopy(self.autoStory)
end

function Controller:GetAutoStoryConfig()
    return deepCopy(self.autoStory)
end

function Controller:SetAutoInfiniteConfig(config)
    assert(type(config) == "table", "Auto Infinite config must be a table")

    for key, value in pairs(config) do
        if key == "placeSlots" or key == "upgradeSlots" then
            if type(value) == "table" then
                self.autoInfinite[key] = deepCopy(value)
            end
        elseif key == "sellWave" then
            local wave = math.floor(tonumber(value) or self.autoInfinite.sellWave or 50)
            self.autoInfinite.sellWave = math.max(1, wave)
        elseif self.autoInfinite[key] ~= nil then
            self.autoInfinite[key] = value == true
        end
    end

    if config.autoReplay == true then
        self.autoInfinite.autoReturnLobby = false
    elseif config.autoReturnLobby == true then
        self.autoInfinite.autoReplay = false
    end

    self.tracker.events:emit("autoInfiniteConfigChanged", deepCopy(self.autoInfinite))
    return deepCopy(self.autoInfinite)
end

function Controller:GetAutoInfiniteConfig()
    return deepCopy(self.autoInfinite)
end

function Controller:SetWebhookConfig(config)
    assert(type(config) == "table", "Webhook config must be a table")

    for key, value in pairs(config) do
        if key == "url" then
            self.webhook.url = tostring(value or "")
        elseif self.webhook[key] ~= nil then
            self.webhook[key] = value == true
        end
    end

    self.tracker.events:emit("webhookConfigChanged", {})
    return deepCopy(self.webhook)
end

function Controller:GetWebhookConfig()
    return deepCopy(self.webhook)
end

function Controller:StartRecording(name)
    if self.replay.running then return false, "stop replay before recording" end
    return self.recorder:start(name)
end

function Controller:StopRecording()
    local ok, macro = self.recorder:stop()

    if ok and macro then
        local id, stored = self.macros:add(macro)
        self.tracker.events:emit("macrosChanged", {})
        return true, stored, id
    end

    return ok, macro, nil
end

function Controller:GetRecording()
    return self.recorder:getMacro()
end

function Controller:ExportMacro(macroOrId)
    if type(macroOrId) == "string" then
        return self.macros:exportJson(macroOrId)
    end

    local macro = macroOrId
        or self.recorder:getMacro()
        or self.importedMacro
        or self.macros:get()

    assert(macro, "no macro available to export")
    return Serializer.encode(macro)
end

function Controller:ImportMacro(json, overrideName)
    local id, macro = self.macros:importJson(json, overrideName)
    self.importedMacro = macro
    self.tracker.events:emit("macrosChanged", {})
    return deepCopy(macro), id
end

function Controller:GetImportedMacro()
    return self.importedMacro and deepCopy(self.importedMacro) or nil
end

-- Public Macros section API.
function Controller:ListMacros()
    return self.macros:list()
end

function Controller:GetMacro(id)
    return self.macros:get(id)
end

function Controller:GetSelectedMacro()
    return self.macros:get()
end

function Controller:GetSelectedMacroId()
    return self.macros:getSelectedId()
end

function Controller:SelectMacro(id)
    return self.macros:select(id)
end

function Controller:RenameMacro(id, newName)
    local ok, err = self.macros:rename(id, newName)
    if ok then self.tracker.events:emit("macrosChanged", {}) end
    return ok, err
end

function Controller:DeleteMacro(id)
    local ok, err = self.macros:remove(id)
    if ok then self.tracker.events:emit("macrosChanged", {}) end
    return ok, err
end

function Controller:ClearMacros()
    self.macros:clear()
    self.importedMacro = nil
end

function Controller:ExportSelectedMacro()
    return self.macros:exportJson()
end

function Controller:GetMacrosSummary()
    return {
        count = self.macros:count(),
        selectedId = self.macros:getSelectedId(),
        recording = self.recorder.recording,
        currentRecording = self.recorder:getMacro(),
        items = self.macros:list(),
    }
end

function Controller:SetWebhookTransport(callback)
    assert(callback == nil or type(callback) == "function", "webhook transport must be a function or nil")
    self.webhookTransport = callback
end

function Controller:_readResult(forcedOutcome, allowHidden)
    if not LocalPlayer then
        return nil, "player unavailable"
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local resultsUI = playerGui and playerGui:FindFirstChild("ResultsUI")
    local holder = resultsUI and resultsUI:FindFirstChild("Holder")

    if not resultsUI or not holder then
        return nil, "results unavailable"
    end

    -- ResultsUI keeps the previous Title text cached while Holder is hidden.
    -- Never classify a match from that stale text: only the visible results
    -- window is authoritative for Victory/Defeat.
    if not allowHidden then
        if resultsUI:IsA("ScreenGui") and resultsUI.Enabled == false then
            return nil, "results hidden"
        end

        if holder:IsA("GuiObject") and holder.Visible == false then
            return nil, "results hidden"
        end
    end

    local titleLabel = holder:FindFirstChild("Title")

    -- Holder visibility is the stale-result guard. Do not also require
    -- Title.Visible: the defeat layout can keep the title object hidden while
    -- still updating its Text to DEFEAT. Requiring both caused real defeats
    -- to be ignored even though the result window itself was active.
    local title = readText(titleLabel)
    if type(title) == "string" then
        -- Be tolerant of RichText/punctuation/spacing without accepting stale
        -- text from a hidden Holder.
        title = title
            :gsub("<.->", "")
            :gsub("[^%a]", "")
            :upper()
    else
        title = nil
    end

    local outcome = forcedOutcome
    if outcome ~= "victory" and outcome ~= "defeat" then
        if title == "VICTORY" then
            outcome = "victory"
        elseif title == "DEFEAT" then
            outcome = "defeat"
        else
            return nil, "result not ready"
        end
    end

    local levelName = readText(holder:FindFirstChild("LevelName")) or "Act ?"
    local difficulty = readText(holder:FindFirstChild("Difficulty")) or "Unknown"

    local timerText = readText(findPath(holder, "Middle", "Timer")) or "0:00"
    local duration = timerText:match("([%d]+:%d%d)$") or timerText

    local progressText = readText(findPath(
        playerGui,
        "spawn_units",
        "Lives",
        "Main",
        "Desc",
        "Level"
    ))

    local progress = parsePlayerProgress(progressText) or {
        level = 0,
        current = 0,
        required = 0,
    }

    local scrolling = findPath(holder, "LevelRewards", "ScrollingFrame")
    local rewards = {}
    local xpAmount = 0

    if scrolling then
        for _, child in ipairs(scrolling:GetChildren()) do
            if child:IsA("GuiObject")
                and child.Visible
                and child.Name ~= "Configuration"
            then
                local amountLabel = findPath(child, "Main", "Amount")
                    or child:FindFirstChild("Amount", true)
                local amountText = readText(amountLabel)
                local amount = parseNumber(amountText)

                if amount and amount > 0 then
                    local lowerName = child.Name:lower()
                    if child.Name == "XPReward" or lowerName:find("xp", 1, true) then
                        xpAmount = math.max(xpAmount, amount)
                    else
                        local topLabel = child:FindFirstChild("Top", true)
                        local rewardName = normalizeRewardName(
                            child:GetAttribute("reward_name")
                            or child:GetAttribute("resource")
                            or child:GetAttribute("item_id")
                            or readText(topLabel)
                            or child.Name
                        )

                        table.insert(rewards, {
                            name = rewardName,
                            amount = amount,
                        })
                    end
                end
            end
        end
    end

    local state = self.tracker.state
    local mapProfile = MapProfiles.resolve(state.map.area, state.map.level)
    local mode = detectMode(state.map.level)

    local challengeDifficulty = tostring(difficulty or ""):lower()
    local challengeNames = {
        ["high cost"] = true,
        ["short range"] = true,
        ["short range ii"] = true,
        ["fast enemies"] = true,
        ["regen enemies"] = true,
        ["tank enemies"] = true,
        ["shield enemies"] = true,
        ["triple cost"] = true,
        ["hyper-regen enemies"] = true,
        ["steel-plated enemies"] = true,
        ["godspeed enemies"] = true,
        ["flying enemies"] = true,
        ["armored enemies"] = true,
        ["mini-range"] = true,
        ["burst enemies"] = true,
    }

    if mode == "Story" and challengeNames[challengeDifficulty] then
        mode = "Challenger"
    end

    return {
        outcome = outcome,
        mode = mode,
        map = mapProfile.displayName,
        thumbnail = mapProfile.thumbnail,
        act = levelName,
        difficulty = difficulty,
        duration = duration,
        player = {
            username = LocalPlayer.Name,
            level = progress.level,
            currentExp = progress.current,
            requiredExp = progress.required,
        },
        playerExp = xpAmount,
        unitExp = xpAmount,
        rewards = rewards,
        timestamp = os.time(),
        area = state.map.area,
        level = state.map.level,
    }
end

function Controller:_formatSession()
    local wins = self.session.wins
    local losses = self.session.losses
    local total = wins + losses
    local rate = total > 0 and math.floor((wins / total) * 100 + 0.5) or 0

    return string.format(
        "%s %d W · %s %d L (%d%% WR)",
        WEBHOOK_EMOJIS.victory,
        wins,
        WEBHOOK_EMOJIS.defeat,
        losses,
        rate
    )
end

function Controller:BuildResultWebhook(result)
    assert(type(result) == "table", "result must be a table")

    local isWin = result.outcome == "victory"
    local isLoss = result.outcome == "defeat"
    assert(isWin or isLoss, "unsupported result outcome")

    local titleEmoji = isWin and WEBHOOK_EMOJIS.victory or WEBHOOK_EMOJIS.defeat
    local titleText = isWin and "Victory" or "Defeat"
    local mode = tostring(result.mode or "Story")

    local locationLine
    if mode == "Expedition" then
        locationLine = string.format(
            "⠀⠀⠀**%s · %s**",
            tostring(result.map or "Unknown"),
            tostring(result.difficulty or "Unknown")
        )
    else
        locationLine = string.format(
            "⠀⠀⠀**%s · %s · %s**",
            tostring(result.map or "Unknown"),
            tostring(result.act or "Act ?"),
            tostring(result.difficulty or "Unknown")
        )
    end

    local lines = {
        string.format("## %s %s", titleEmoji, titleText),
        string.format("-# %s", mode),
        locationLine,
        "-# Run",
        string.format(
            "⠀⠀⠀%s **Duration** %s %s",
            WEBHOOK_EMOJIS.arrow,
            WEBHOOK_EMOJIS.clock,
            tostring(result.duration or "0:00")
        ),
        string.format(
            "⠀⠀⠀%s **Session** %s",
            WEBHOOK_EMOJIS.arrow,
            self:_formatSession()
        ),
        "-# Player",
        string.format(
            "⠀⠀⠀%s %s **Username** ||%s||",
            WEBHOOK_EMOJIS.arrow,
            WEBHOOK_EMOJIS.person,
            tostring(result.player and result.player.username or "Unknown")
        ),
        string.format(
            "⠀⠀⠀%s %s **Level** %d (%s / %s)",
            WEBHOOK_EMOJIS.arrow,
            WEBHOOK_EMOJIS.playerExp,
            tonumber(result.player and result.player.level) or 0,
            tostring(result.player and result.player.currentExp or 0),
            tostring(result.player and result.player.requiredExp or 0)
        ),
        string.format("-# Rewards %s", WEBHOOK_EMOJIS.rewards),
    }

    if tonumber(result.playerExp) and result.playerExp > 0 then
        table.insert(lines, string.format(
            "⠀⠀⠀%s %s **Player EXP** ×%s",
            WEBHOOK_EMOJIS.arrow,
            WEBHOOK_EMOJIS.playerExp,
            tostring(result.playerExp)
        ))
    end

    if tonumber(result.unitExp) and result.unitExp > 0 then
        table.insert(lines, string.format(
            "⠀⠀⠀%s %s **Unit EXP** ×%s",
            WEBHOOK_EMOJIS.arrow,
            WEBHOOK_EMOJIS.unitExp,
            tostring(result.unitExp)
        ))
    end

    for _, reward in ipairs(result.rewards or {}) do
        local emoji = rewardEmoji(reward.name)
        local prefix = WEBHOOK_EMOJIS.arrow

        if emoji then
            table.insert(lines, string.format(
                "⠀⠀⠀%s %s **%s** ×%s",
                prefix,
                emoji,
                tostring(reward.name),
                tostring(reward.amount)
            ))
        else
            table.insert(lines, string.format(
                "⠀⠀⠀%s **%s** ×%s",
                prefix,
                tostring(reward.name),
                tostring(reward.amount)
            ))
        end
    end

    local footerName = mode == "Expedition" and "Anime Expeditions" or "Re: Adventures"
    table.insert(lines, string.format(
        "-# %s · <t:%d:R>",
        footerName,
        tonumber(result.timestamp) or os.time()
    ))

    return {
        embeds = {
            {
                description = table.concat(lines, "\n"),
                thumbnail = result.thumbnail and {
                    url = result.thumbnail,
                } or nil,
            },
        },
    }
end

function Controller:_postWebhook(payload)
    if self.webhookTransport then
        return self.webhookTransport(self.webhook.url, payload)
    end

    if self.webhook.url == "" then
        return false, "webhook url missing"
    end

    local env = (getgenv and getgenv()) or _G
    local requestFn = env.request or env.http_request or (env.syn and env.syn.request)
    local requestOptions = {
        Url = self.webhook.url,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
        },
        Body = HttpService:JSONEncode(payload),
    }

    local response
    if type(requestFn) == "function" then
        response = requestFn(requestOptions)
    else
        response = HttpService:RequestAsync(requestOptions)
    end
    local status = tonumber(response and response.StatusCode)
    return response ~= nil and (response.Success == true or (status ~= nil and status >= 200 and status < 300)), response
end

function Controller:SendResultWebhook(result)
    if not self.webhook.enabled then
        return false, "webhook disabled"
    end

    local payload = self:BuildResultWebhook(result)
    local ok, success, response = pcall(function()
        return self:_postWebhook(payload)
    end)

    if not ok then
        return false, success
    end

    return success == true, response
end

function Controller:_handleFinishedMatch()
    local generation = self.generation
    local result
    local lastReadError

    -- game_finished can arrive before ResultsUI replaces the previous cached
    -- title. Let the visible result frame settle before the first read.
    task.wait(0.35)

    -- Some defeat transitions render more slowly than victory. Keep polling
    -- the authoritative visible Holder long enough for the result UI to settle.
    for attempt = 1, 40 do
        if not self.running or self.generation ~= generation then return false, "stopped" end
        result, lastReadError = self:_readResult()

        if result then
            break
        end

        -- Defeat is also confirmed by the tracked base reaching zero. Do not
        -- wait the full result timeout when the defeat GUI is late/partial.
        local baseLife = tonumber(self.tracker.state.player.baseLife)
        if attempt >= 6 and baseLife and baseLife <= 0 then
            result = self:_readResult("defeat", true)
            break
        end

        task.wait(0.5)
    end

    if not result then
        local state = self.tracker.state
        if tonumber(state.player.baseLife) and tonumber(state.player.baseLife) <= 0 then
            result = self:_readResult("defeat", true)

            if not result then
                local mapProfile = MapProfiles.resolve(state.map.area, state.map.level)
                result = {
                    outcome = "defeat",
                    mode = detectMode(state.map.level),
                    map = mapProfile.displayName,
                    thumbnail = mapProfile.thumbnail,
                    act = "Act ?",
                    difficulty = "Unknown",
                    duration = "0:00",
                    player = {
                        username = LocalPlayer and LocalPlayer.Name or "Unknown",
                        level = 0,
                        currentExp = 0,
                        requiredExp = 0,
                    },
                    playerExp = 0,
                    unitExp = 0,
                    rewards = {},
                    timestamp = os.time(),
                    area = state.map.area,
                    level = state.map.level,
                }
            end
        end
    end

    if not result then
        local message = "Result detection failed: " .. tostring(lastReadError or "result unavailable")
        self.tracker.events:emit("actionError", {message = message})
        return false, message
    end

    local resultKey = table.concat({
        tostring(result.outcome),
        tostring(result.level),
        tostring(result.duration),
    }, "|")

    if self.lastWebhookResultKey == resultKey then
        return false, "already sent"
    end

    if result.outcome == "victory" then
        self.session.wins = self.session.wins + 1
    elseif result.outcome == "defeat" then
        self.session.losses = self.session.losses + 1
    else
        return false, "unsupported result outcome"
    end

    self.lastWebhookResultKey = resultKey

    if self.webhook.enabled then
        self.webhookBusy = true
        local callOk, ok, err = pcall(self.SendResultWebhook, self, result)
        self.webhookBusy = false
        if not callOk then ok, err = false, ok end
        if not ok then self.tracker.events:emit("actionError", {message = "Webhook failed: " .. tostring(err)}) end
        return ok, err
    end

    return true, result
end

function Controller:GetWebhookPreview()
    local result, err = self:_readResult()

    if not result then
        return nil, err
    end

    return self:BuildResultWebhook(result)
end

function Controller:GetWebhookSession()
    return deepCopy(self.session)
end

Core.StateTracker = StateTracker
Core.MapProfiles = MapProfiles
Core.Serializer = Serializer
Core.MacroRecorder = MacroRecorder
Core.MacroLibrary = MacroLibrary
Core.MacroReplay = MacroReplay
Core.Controller = Controller

function Core.new(options)
    return Controller.new(options)
end

return Core
