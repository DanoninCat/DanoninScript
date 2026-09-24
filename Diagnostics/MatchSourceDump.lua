-- Re Adventures - Match/Challenger Source Dumper for Real executor
-- Read-only. Searches loaded scripts/modules for match, lobby, challenger and return-flow contracts.
-- Does not fire remotes, hook functions, or modify game state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G

local function fn(name)
    local v = rawget(env, name)
    if type(v) == "function" then return v end
    local ok, fallback = pcall(function() return _G[name] end)
    if ok and type(fallback) == "function" then return fallback end
    return nil
end

local decompileFn = assert(fn("decompile"), "decompile unavailable")
local getscriptsFn = fn("getscripts")
local getloadedmodulesFn = fn("getloadedmodules")
local getscriptclosureFn = fn("getscriptclosure")
local writefileFn = fn("writefile")
local makefolderFn = fn("makefolder")
local isfolderFn = fn("isfolder")
local setclipboardFn = fn("setclipboard")

local debugTable = rawget(env, "debug") or debug
local getconstantsFn = type(debugTable) == "table" and debugTable.getconstants or nil
local getprotosFn = type(debugTable) == "table" and debugTable.getprotos or nil

local TARGETS = {
    "request_start_game",
    "request_join_lobby",
    "request_leave_lobby",
    "select_difficulty",
    "vote_start",
    "set_game_finished_vote",
    "teleport_back_to_lobby",
    "game_finished",
    "challenger",
    "challenge",
    "daily",
    "weekly",
}

local EXACT_ENDPOINTS = {
    request_start_game = true,
    request_join_lobby = true,
    request_leave_lobby = true,
    select_difficulty = true,
    vote_start = true,
    set_game_finished_vote = true,
    teleport_back_to_lobby = true,
    game_finished = true,
}

local function fullName(obj)
    if typeof(obj) ~= "Instance" then return tostring(obj) end
    local ok, value = pcall(function() return obj:GetFullName() end)
    return ok and value or tostring(obj)
end

local function containsTarget(text)
    if type(text) ~= "string" then return false end
    local lower = text:lower()
    for _, target in ipairs(TARGETS) do
        if lower:find(target, 1, true) then return true end
    end
    return false
end

local function snippetsAround(source)
    local out = {}
    local lower = source:lower()
    for _, target in ipairs(TARGETS) do
        local startAt = 1
        while true do
            local a, b = lower:find(target, startAt, true)
            if not a then break end
            table.insert(out, {
                target = target,
                start = a,
                snippet = source:sub(math.max(1, a - 2200), math.min(#source, b + 3400)),
            })
            startAt = b + 1
            if #out >= 24 then return out end
        end
    end
    return out
end

local function collectConstants(scriptObj)
    if type(getscriptclosureFn) ~= "function" or type(getconstantsFn) ~= "function" then return {} end
    local okClosure, closure = pcall(getscriptclosureFn, scriptObj)
    if not okClosure or type(closure) ~= "function" then return {} end

    local found, seen = {}, {}
    local function scanFunction(func, depth)
        if type(func) ~= "function" or depth > 3 then return end
        local okConstants, constants = pcall(getconstantsFn, func)
        if okConstants and type(constants) == "table" then
            for _, constant in ipairs(constants) do
                if type(constant) == "string" and containsTarget(constant) and not seen[constant] then
                    seen[constant] = true
                    table.insert(found, constant)
                end
            end
        end
        if type(getprotosFn) == "function" then
            local okProtos, protos = pcall(getprotosFn, func)
            if okProtos and type(protos) == "table" then
                for _, proto in ipairs(protos) do scanFunction(proto, depth + 1) end
            end
        end
    end
    scanFunction(closure, 0)
    return found
end

local candidates, seen = {}, {}
local function addCandidate(obj, sourceKind)
    if typeof(obj) ~= "Instance" then return end
    if not (obj:IsA("LocalScript") or obj:IsA("ModuleScript") or obj:IsA("Script")) then return end
    if seen[obj] then return end
    seen[obj] = true

    local path = fullName(obj)
    local lower = path:lower()
    local score = 0
    for _, word in ipairs({"challenge", "challenger", "lobby", "match", "game", "level", "story", "teleport", "vote"}) do
        if lower:find(word, 1, true) then score += 3 end
    end
    if lower:find("gui", 1, true) then score += 1 end
    if sourceKind == "loadedmodule" then score += 2 end

    table.insert(candidates, {
        object = obj,
        path = path,
        class = obj.ClassName,
        sourceKind = sourceKind,
        score = score,
    })
end

if type(getscriptsFn) == "function" then
    local ok, list = pcall(getscriptsFn)
    if ok and type(list) == "table" then
        for _, obj in ipairs(list) do addCandidate(obj, "getscripts") end
    end
end
if type(getloadedmodulesFn) == "function" then
    local ok, list = pcall(getloadedmodulesFn)
    if ok and type(list) == "table" then
        for _, obj in ipairs(list) do addCandidate(obj, "loadedmodule") end
    end
end

for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
    if obj:IsA("ModuleScript") then
        local lower = fullName(obj):lower()
        if lower:find("challenge", 1, true) or lower:find("lobby", 1, true) or lower:find("game", 1, true) then
            addCandidate(obj, "replicatedstorage")
        end
    end
end

table.sort(candidates, function(a, b)
    if a.score == b.score then return a.path < b.path end
    return a.score > b.score
end)

local report = {
    metadata = {
        version = "1.0.0-source",
        generatedAt = os.time(),
        placeId = game.PlaceId,
        gameId = game.GameId,
        jobId = game.JobId,
        player = player and player.Name or nil,
        candidates = #candidates,
    },
    targets = TARGETS,
    matches = {},
    failures = {},
    scanned = 0,
}

local foundExact = {}
local function scanCandidate(candidate)
    report.scanned += 1
    local constants = collectConstants(candidate.object)
    local likely = candidate.score > 0 or #constants > 0
    local ok, source = pcall(decompileFn, candidate.object)
    if not ok or type(source) ~= "string" then
        if likely then
            table.insert(report.failures, {path = candidate.path, reason = tostring(source)})
        end
        return
    end

    if containsTarget(source) or #constants > 0 then
        local snippets = snippetsAround(source)
        for _, s in ipairs(snippets) do
            if EXACT_ENDPOINTS[s.target] then foundExact[s.target] = true end
        end
        table.insert(report.matches, {
            path = candidate.path,
            class = candidate.class,
            sourceKind = candidate.sourceKind,
            score = candidate.score,
            constants = constants,
            snippets = snippets,
        })
    end
end

print("[MatchSourceDump] VERSION: 1.0.0-source")
print("[MatchSourceDump] Candidates:", #candidates)
print("[MatchSourceDump] Pass 1: high-signal scripts...")

for index, candidate in ipairs(candidates) do
    if candidate.score > 0 then
        scanCandidate(candidate)
        if index % 8 == 0 then task.wait() end
    end
end

local exactCount = 0
for _ in pairs(foundExact) do exactCount += 1 end
if exactCount < 4 then
    print("[MatchSourceDump] Pass 2: scanning remaining scripts...")
    for index, candidate in ipairs(candidates) do
        if candidate.score <= 0 then
            scanCandidate(candidate)
            if index % 6 == 0 then task.wait() end
        end
    end
end

local encoded = HttpService:JSONEncode(report)
local folder, diagnostics = "CatEmpire", "CatEmpire/Diagnostics"
local path

if type(writefileFn) == "function" then
    if type(makefolderFn) == "function" then
        if type(isfolderFn) ~= "function" or not isfolderFn(folder) then pcall(makefolderFn, folder) end
        if type(isfolderFn) ~= "function" or not isfolderFn(diagnostics) then pcall(makefolderFn, diagnostics) end
    end
    path = diagnostics .. "/match_source_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    if not pcall(writefileFn, path, encoded) then path = nil end
end

if not path and type(setclipboardFn) == "function" then pcall(setclipboardFn, encoded) end

print("[MatchSourceDump] Scanned:", report.scanned)
print("[MatchSourceDump] Matches:", #report.matches)
print("[MatchSourceDump] Failures:", #report.failures)
if path then print("[MatchSourceDump] Saved:", path) else print("[MatchSourceDump] JSON copied to clipboard.") end
for _, match in ipairs(report.matches) do
    print("[MatchSourceDump] MATCH:", match.path)
    local shown = {}
    for _, snippet in ipairs(match.snippets or {}) do
        if not shown[snippet.target] then
            shown[snippet.target] = true
            print("  ->", snippet.target)
        end
    end
end

return report
