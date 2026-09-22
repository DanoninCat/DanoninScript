-- Re Adventures V2 passive runtime core
-- No UI is created here. No RemoteEvent/RemoteFunction is invoked here.
-- Designed to be embedded or wired into the existing Loader/UI.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local Core = {}
Core.VERSION = "2.0.0"

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
            state = self:getSnapshot(),
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
                state = self:getSnapshot(),
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
                        state = self:getSnapshot(),
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
                state = self:getSnapshot(),
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
            state = self:getSnapshot(),
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
                state = self:getSnapshot(),
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
                state = self:getSnapshot(),
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
        defaultLevel = "marineford_level_1",
        profileQuality = "complete",
    },
    aot = {
        displayName = "Walled City",
        defaultLevel = "aot_level_1",
        profileQuality = "complete",
    },
    demonslayer = {
        displayName = "Snowy Town",
        defaultLevel = "demonslayer_level_1",
        profileQuality = "partial_workspace_limit",
    },
    naruto = {
        displayName = "Sand Village",
        defaultLevel = "naruto_level_1",
        profileQuality = "complete",
    },
    namek = {
        displayName = "Namek",
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
    assert(type(decoded.version) == "number", "macro version is missing")
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
            snapshotInterval = tonumber(options.snapshotInterval) or 1,
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
    local state = self.tracker:getSnapshot()

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

    local state = self.tracker:getSnapshot()
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
        self:_record("PLACE_DETECTED", {
            unit = payload.unit,
        })
    end)

    listen("unitUpgradeChanged", function(payload)
        self:_record("UPGRADE_DETECTED", {
            uuid = payload.uuid,
            from = payload.from,
            to = payload.to,
            unit = payload.unit,
        })
    end)

    listen("unitRemoved", function(payload)
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

    local state = self.tracker:getSnapshot()

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
        importedMacro = nil,
        webhookTransport = nil,
    }, Controller)
end

function Controller:Start()
    return self.tracker:start()
end

function Controller:Stop()
    if self.recorder.recording then
        self:StopRecording()
    end

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

function Controller:StartRecording(name)
    return self.recorder:start(name)
end

function Controller:StopRecording()
    local ok, macro = self.recorder:stop()

    if ok and macro then
        local id, stored = self.macros:add(macro)
        self.events = self.events
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
    return self.macros:rename(id, newName)
end

function Controller:DeleteMacro(id)
    return self.macros:remove(id)
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

function Controller:BuildWebhookPayload(kind, extra)
    local state = self.tracker:getSnapshot()

    return {
        kind = kind,
        timestamp = os.time(),
        map = deepCopy(state.map),
        match = deepCopy(state.match),
        player = {
            name = state.player.name,
            money = state.player.money,
            baseLife = state.player.baseLife,
            baseMaxLife = state.player.baseMaxLife,
        },
        counters = deepCopy(state.counters),
        extra = deepCopy(extra or {}),
    }
end

function Controller:SendWebhook(kind, extra)
    if not self.webhookTransport then
        return false, "webhook transport not configured"
    end

    local payload = self:BuildWebhookPayload(kind, extra)
    local ok, result = pcall(self.webhookTransport, payload)

    if not ok then
        return false, result
    end

    return true, result
end

Core.StateTracker = StateTracker
Core.MapProfiles = MapProfiles
Core.Serializer = Serializer
Core.MacroRecorder = MacroRecorder
Core.MacroLibrary = MacroLibrary
Core.Controller = Controller

function Core.new(options)
    return Controller.new(options)
end

return Core
