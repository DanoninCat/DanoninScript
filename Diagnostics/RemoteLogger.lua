-- Cat Empire / Re Adventures - Lightweight Remote Logger
-- Purpose: capture remote traffic while keeping the game interactive.
-- This script does NOT scan Workspace/PlayerGui trees continuously.

local ENV = (getgenv and getgenv()) or _G
local STATE_KEY = "__CAT_EMPIRE_REMOTE_LOGGER_STATE"
local HOOK_KEY = "__CAT_EMPIRE_REMOTE_LOGGER_HOOKED"

if ENV[STATE_KEY] and ENV[STATE_KEY].api then
    ENV[STATE_KEY].enabled = true
    print("[RemoteLogger] Already installed; logging resumed.")
    print("[RemoteLogger] File:", ENV[STATE_KEY].filePath or "(memory only)")
    return ENV[STATE_KEY].api
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local unpackFn = table.unpack or unpack

local function globalFunction(name)
    local value = rawget(ENV, name)
    if type(value) == "function" then
        return value
    end

    local ok, fallback = pcall(function()
        return _G[name]
    end)

    return ok and type(fallback) == "function" and fallback or nil
end

local writefileFn = globalFunction("writefile")
local appendfileFn = globalFunction("appendfile")
local makefolderFn = globalFunction("makefolder")
local isfolderFn = globalFunction("isfolder")
local setclipboardFn = globalFunction("setclipboard")
local getcallingscriptFn = globalFunction("getcallingscript")
local hookmetamethodFn = globalFunction("hookmetamethod")
local getnamecallmethodFn = globalFunction("getnamecallmethod")
local newcclosureFn = globalFunction("newcclosure")

local state = {
    enabled = true,
    startedAt = os.time(),
    sequence = 0,
    dropped = 0,
    maxEntries = 1500,
    lines = {},
    incomingConnections = {},
    incomingRootConnection = nil,
    captureIncoming = true,
    endpointsOnly = false,
    filePath = nil,
    api = nil,
    directHooks = {
        fireServer = false,
        invokeServer = false,
    },
}

ENV[STATE_KEY] = state

local function timestamp()
    local clock = os.clock()
    local millis = math.floor((clock - math.floor(clock)) * 1000)
    return string.format("%s.%03d", os.date("%H:%M:%S"), millis)
end

local function safeFullName(instance)
    if not instance then
        return "nil"
    end

    local ok, name = pcall(function()
        return instance:GetFullName()
    end)

    return ok and name or tostring(instance)
end

local function trimString(value, limit)
    value = tostring(value)
    limit = limit or 320

    if #value > limit then
        return value:sub(1, limit) .. "...<truncated:" .. tostring(#value) .. ">"
    end

    return value
end

local function serialize(value, depth, seen)
    depth = depth or 0
    seen = seen or {}

    local kind = typeof(value)

    if kind == "nil" then
        return "nil"
    elseif kind == "string" then
        return string.format("%q", trimString(value))
    elseif kind == "number" or kind == "boolean" then
        return tostring(value)
    elseif kind == "Instance" then
        return string.format("<%s %s>", value.ClassName, safeFullName(value))
    elseif kind == "CFrame"
        or kind == "Vector3"
        or kind == "Vector2"
        or kind == "Color3"
        or kind == "UDim"
        or kind == "UDim2"
        or kind == "Rect"
        or kind == "Ray"
        or kind == "NumberRange"
        or kind == "NumberSequence"
        or kind == "ColorSequence"
        or kind == "EnumItem"
    then
        return string.format("<%s %s>", kind, trimString(tostring(value), 240))
    elseif kind == "table" then
        if seen[value] then
            return "<cycle>"
        end

        if depth >= 3 then
            return "{...}"
        end

        seen[value] = true
        local parts = {}
        local count = 0

        for key, item in pairs(value) do
            count = count + 1
            if count > 24 then
                table.insert(parts, "...<more>")
                break
            end

            table.insert(parts,
                "[" .. serialize(key, depth + 1, seen) .. "]="
                .. serialize(item, depth + 1, seen)
            )
        end

        seen[value] = nil
        return "{" .. table.concat(parts, ", ") .. "}"
    end

    return string.format("<%s %s>", kind, trimString(tostring(value), 240))
end

local function readValue(parent, name)
    local object = parent and parent:FindFirstChild(name)
    if object and object:IsA("ValueBase") then
        return object.Value
    end
    return nil
end

local function readText(root, ...)
    local current = root

    for index = 1, select("#", ...) do
        if not current then
            return nil
        end

        local childName = select(index, ...)
        current = current:FindFirstChild(childName)
    end

    if current and (
        current:IsA("TextLabel")
        or current:IsA("TextButton")
        or current:IsA("TextBox")
    ) then
        return current.Text
    end

    return nil
end

local function captureContext()
    local result = {}

    local mapConfig = Workspace:FindFirstChild("_MAP_CONFIG")
    result.area = readValue(mapConfig, "Area")
    result.level = readValue(mapConfig, "Level")
    result.mapLoaded = readValue(mapConfig, "MapLoaded")
    result.isLobby = readValue(mapConfig, "IsLobby")
    result.serverReady = readValue(Workspace, "SERVER_READY")
    result.wavesStarted = readValue(Workspace, "_waves_started")
    result.wave = readValue(Workspace, "_wave_num")

    local data = Workspace:FindFirstChild("_DATA")
    result.gameFinished = readValue(data, "GameFinished")
    result.gameStarted = readValue(data, "GameStarted")

    local voteStart = data and data:FindFirstChild("VoteStart")
    result.voteFinished = readValue(voteStart, "VotingFinished")
    result.voteCount = readValue(voteStart, "Votes")

    local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        local voteGui = playerGui:FindFirstChild("VoteStart")
        local voteHolder = voteGui and voteGui:FindFirstChild("Holder")
        result.readyVisible = voteGui
            and (not voteGui:IsA("ScreenGui") or voteGui.Enabled ~= false)
            and voteHolder
            and voteHolder:IsA("GuiObject")
            and voteHolder.Visible
            or false
        result.readyTitle = readText(voteHolder, "Title")
        result.readyCount = readText(voteHolder, "Description")
        result.readyButton = readText(voteHolder, "ButtonHolder", "Yes", "Main", "text")

        local resultsGui = playerGui:FindFirstChild("ResultsUI")
        local resultsHolder = resultsGui and resultsGui:FindFirstChild("Holder")
        result.resultsVisible = resultsGui
            and (not resultsGui:IsA("ScreenGui") or resultsGui.Enabled ~= false)
            and resultsHolder
            and resultsHolder:IsA("GuiObject")
            and resultsHolder.Visible
            or false
        result.resultsTitle = readText(resultsHolder, "Title")

        local visible = {}
        for _, child in ipairs(playerGui:GetChildren()) do
            if child:IsA("ScreenGui") and child.Enabled ~= false then
                table.insert(visible, child.Name)
                if #visible >= 16 then
                    break
                end
            end
        end
        table.sort(visible)
        result.screenGuis = visible
    end

    return result
end

local function formatPacked(label, packed)
    local lines = {}
    table.insert(lines, label .. " (" .. tostring(packed and packed.n or 0) .. "):")

    if not packed or packed.n == 0 then
        table.insert(lines, "  <none>")
        return table.concat(lines, "\n")
    end

    for index = 1, packed.n do
        table.insert(lines, "  [" .. tostring(index) .. "] " .. serialize(packed[index]))
    end

    return table.concat(lines, "\n")
end

local function formatContext(context)
    return "Context: " .. serialize(context)
end

local function persistLine(line)
    table.insert(state.lines, line)

    if #state.lines > state.maxEntries then
        table.remove(state.lines, 1)
        state.dropped = state.dropped + 1
    end

    if appendfileFn and state.filePath then
        task.defer(function()
            pcall(appendfileFn, state.filePath, line .. "\n")
        end)
    end
end

local function callerName()
    if not getcallingscriptFn then
        return "<unavailable>"
    end

    local ok, scriptObject = pcall(getcallingscriptFn)
    if not ok or not scriptObject then
        return "<executor/unknown>"
    end

    return safeFullName(scriptObject)
end

local function shouldLogRemote(remote)
    if typeof(remote) ~= "Instance" then
        return false
    end

    if not (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then
        return false
    end

    if not state.endpointsOnly then
        return true
    end

    local endpoints = ReplicatedStorage:FindFirstChild("endpoints")
    return endpoints ~= nil and remote:IsDescendantOf(endpoints)
end

local recentOutgoing = {}

local function outgoingFingerprint(remote, method, args)
    local parts = {
        safeFullName(remote),
        tostring(method),
        tostring(args and args.n or 0),
    }

    if args then
        for index = 1, math.min(args.n, 6) do
            table.insert(parts, serialize(args[index], 0, {}))
        end
    end

    return table.concat(parts, "|")
end

local function emitOutgoingOnce(remote, method, args, returns, caller)
    local key = outgoingFingerprint(remote, method, args)
    local now = os.clock()
    local previous = recentOutgoing[key]

    if previous and now - previous < 0.075 then
        return
    end

    recentOutgoing[key] = now

    -- Keep the dedupe table bounded during long sessions.
    if state.sequence % 100 == 0 then
        for fingerprint, seenAt in pairs(recentOutgoing) do
            if now - seenAt > 2 then
                recentOutgoing[fingerprint] = nil
            end
        end
    end

    emit("OUT", remote, method, args, returns, caller)
end

local function emit(direction, remote, method, args, returns, caller)
    if not state.enabled then
        return
    end

    state.sequence = state.sequence + 1

    local chunks = {
        "",
        string.format("[%s #%d %s]", direction, state.sequence, timestamp()),
        "Remote: " .. safeFullName(remote),
        "Class: " .. tostring(remote and remote.ClassName or "?"),
        "Method: " .. tostring(method or "?"),
    }

    if caller then
        table.insert(chunks, "Caller: " .. tostring(caller))
    end

    table.insert(chunks, formatPacked("Args", args))

    if returns then
        table.insert(chunks, formatPacked("Returns", returns))
    end

    table.insert(chunks, formatContext(captureContext()))
    table.insert(chunks, string.rep("-", 72))

    local line = table.concat(chunks, "\n")
    persistLine(line)
    print(line)
end

local function connectIncoming(remote)
    if not state.captureIncoming or not remote:IsA("RemoteEvent") then
        return
    end

    if state.incomingConnections[remote] then
        return
    end

    state.incomingConnections[remote] = remote.OnClientEvent:Connect(function(...)
        if not state.enabled then
            return
        end

        local args = table.pack(...)
        task.defer(function()
            emit("IN", remote, "OnClientEvent", args, nil, nil)
        end)
    end)
end

local function bindIncoming()
    local endpoints = ReplicatedStorage:FindFirstChild("endpoints")
    local serverToClient = endpoints and endpoints:FindFirstChild("server_to_client")

    if not serverToClient then
        return
    end

    for _, item in ipairs(serverToClient:GetDescendants()) do
        if item:IsA("RemoteEvent") then
            connectIncoming(item)
        end
    end

    if state.incomingRootConnection then
        state.incomingRootConnection:Disconnect()
    end

    state.incomingRootConnection = serverToClient.DescendantAdded:Connect(function(item)
        if item:IsA("RemoteEvent") then
            connectIncoming(item)
        end
    end)
end

local function setupOutputFile()
    if not writefileFn then
        return
    end

    local folder = "CatEmpire"
    local subfolder = folder .. "/Diagnostics"

    if makefolderFn then
        if not isfolderFn or not isfolderFn(folder) then
            pcall(makefolderFn, folder)
        end
        if not isfolderFn or not isfolderFn(subfolder) then
            pcall(makefolderFn, subfolder)
        end
    end

    local stamp = os.date("%Y%m%d_%H%M%S")
    state.filePath = subfolder .. "/remote_log_" .. stamp .. ".txt"

    local header = table.concat({
        "CAT EMPIRE REMOTE LOGGER",
        "Started: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "PlaceId: " .. tostring(game.PlaceId),
        "GameId: " .. tostring(game.GameId),
        "Mode: discovery; all outgoing remotes + incoming server_to_client RemoteEvents",
        string.rep("=", 72),
        "",
    }, "\n")

    local ok = pcall(writefileFn, state.filePath, header)
    if not ok then
        state.filePath = nil
    end
end

local API = {}

function API:Start()
    state.enabled = true
    bindIncoming()
    print("[RemoteLogger] Started.")
    return true, state.filePath
end

function API:Stop()
    state.enabled = false
    print("[RemoteLogger] Stopped.")
    return true, state.filePath
end

function API:Clear()
    table.clear(state.lines)
    state.sequence = 0
    state.dropped = 0

    if writefileFn and state.filePath then
        pcall(writefileFn, state.filePath,
            "CAT EMPIRE REMOTE LOGGER\nCleared: "
            .. os.date("%Y-%m-%d %H:%M:%S")
            .. "\n"
            .. string.rep("=", 72)
            .. "\n"
        )
    end

    print("[RemoteLogger] Cleared.")
    return true
end

function API:Export()
    local body = table.concat(state.lines, "\n")
    local summary = string.format(
        "Entries: %d | Dropped from memory: %d | File: %s",
        #state.lines,
        state.dropped,
        tostring(state.filePath or "memory only")
    )

    if writefileFn and state.filePath and not appendfileFn then
        pcall(writefileFn, state.filePath, body)
    elseif not state.filePath and setclipboardFn then
        pcall(setclipboardFn, body)
    end

    print("[RemoteLogger] " .. summary)
    return state.filePath, body, summary
end

function API:Status()
    return {
        enabled = state.enabled,
        entries = #state.lines,
        dropped = state.dropped,
        filePath = state.filePath,
        captureIncoming = state.captureIncoming,
        endpointsOnly = state.endpointsOnly,
        directHooks = {
            fireServer = state.directHooks.fireServer,
            invokeServer = state.directHooks.invokeServer,
        },
    }
end

function API:SetEndpointsOnly(value)
    state.endpointsOnly = value ~= false
    return state.endpointsOnly
end

function API:SetCaptureIncoming(value)
    state.captureIncoming = value ~= false

    if state.captureIncoming then
        bindIncoming()
    end

    return state.captureIncoming
end

state.api = API

setupOutputFile()
bindIncoming()

if not ENV[HOOK_KEY] then
    assert(type(hookmetamethodFn) == "function", "hookmetamethod is unavailable in this executor")
    assert(type(getnamecallmethodFn) == "function", "getnamecallmethod is unavailable in this executor")

    local oldNamecall
    local handler = function(self, ...)
        local method = getnamecallmethodFn()
        local activeState = ENV[STATE_KEY]

        if not activeState
            or not activeState.enabled
            or (method ~= "FireServer" and method ~= "InvokeServer")
            or not shouldLogRemote(self)
        then
            return oldNamecall(self, ...)
        end

        local args = table.pack(...)
        local caller = callerName()

        if method == "FireServer" then
            task.defer(function()
                emitOutgoingOnce(self, method, args, nil, caller)
            end)
            return oldNamecall(self, ...)
        end

        local returns = table.pack(oldNamecall(self, ...))
        task.defer(function()
            emitOutgoingOnce(self, method, args, returns, caller)
        end)
        return unpackFn(returns, 1, returns.n)
    end

    if newcclosureFn then
        handler = newcclosureFn(handler)
    end

    oldNamecall = hookmetamethodFn(game, "__namecall", handler)
    ENV[HOOK_KEY] = true
end


-- Some game modules call RemoteEvent.FireServer(remote, ...) or
-- RemoteFunction.InvokeServer(remote, ...) directly. Those calls can bypass
-- __namecall in some executors, so install class-method hooks as a fallback.
local hookfunctionFn = globalFunction("hookfunction")

if type(hookfunctionFn) == "function" then
    local function installDirectHook(className, methodName)
        local probe = Instance.new(className)
        local target = probe[methodName]

        if type(target) ~= "function" then
            probe:Destroy()
            return false, "method unavailable"
        end

        local oldMethod
        local wrapped = function(self, ...)
            local args = table.pack(...)

            if not shouldLogRemote(self) then
                return oldMethod(self, ...)
            end

            local caller = callerName()

            if methodName == "FireServer" then
                task.defer(function()
                    emitOutgoingOnce(self, methodName, args, nil, caller)
                end)
                return oldMethod(self, ...)
            end

            local returns = table.pack(oldMethod(self, ...))
            task.defer(function()
                emitOutgoingOnce(self, methodName, args, returns, caller)
            end)
            return unpackFn(returns, 1, returns.n)
        end

        if newcclosureFn then
            wrapped = newcclosureFn(wrapped)
        end

        local ok, original = pcall(hookfunctionFn, target, wrapped)
        probe:Destroy()

        if not ok or type(original) ~= "function" then
            return false, tostring(original)
        end

        oldMethod = original
        return true
    end

    local okFire = installDirectHook("RemoteEvent", "FireServer")
    state.directHooks.fireServer = okFire == true

    local okInvoke = installDirectHook("RemoteFunction", "InvokeServer")
    state.directHooks.invokeServer = okInvoke == true
end

print("[RemoteLogger] Lightweight logger started.")
print("[RemoteLogger] Output:", state.filePath or "memory/clipboard only")
print("[RemoteLogger] Outgoing capture: __namecall=true"
    .. " | FireServer hook=" .. tostring(state.directHooks.fireServer)
    .. " | InvokeServer hook=" .. tostring(state.directHooks.invokeServer))
print("[RemoteLogger] Discovery mode: ALL outgoing RemoteEvent/RemoteFunction calls are logged.")
print("[RemoteLogger] Commands:")
print("  getgenv().__CAT_EMPIRE_REMOTE_LOGGER_STATE.api:Status()")
print("  getgenv().__CAT_EMPIRE_REMOTE_LOGGER_STATE.api:Export()")
print("  getgenv().__CAT_EMPIRE_REMOTE_LOGGER_STATE.api:Clear()")
print("  getgenv().__CAT_EMPIRE_REMOTE_LOGGER_STATE.api:Stop()")
print("  getgenv().__CAT_EMPIRE_REMOTE_LOGGER_STATE.api:Start()")

return API
