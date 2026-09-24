-- Re Adventures - Trait Reroll Source Dumper for Real executor
-- Read-only. Searches loaded scripts/modules for request_token_trait_reroll usage.
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
    "request_token_trait_reroll",
    "request_buy_trait_reroll",
    "unit_traits_changed",
    "set_skip_double_traits_warning",
    "set_trait_filter",
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
        if lower:find(target:lower(), 1, true) then
            return true
        end
    end
    return false
end

local function snippetsAround(source)
    local out = {}
    local lower = source:lower()

    for _, target in ipairs(TARGETS) do
        local needle = target:lower()
        local startAt = 1
        while true do
            local a, b = lower:find(needle, startAt, true)
            if not a then break end

            local from = math.max(1, a - 1800)
            local to = math.min(#source, b + 2600)
            local snippet = source:sub(from, to)

            table.insert(out, {
                target = target,
                start = a,
                snippet = snippet,
            })

            startAt = b + 1
            if #out >= 12 then
                return out
            end
        end
    end

    return out
end

local function collectConstants(scriptObj)
    if type(getscriptclosureFn) ~= "function" or type(getconstantsFn) ~= "function" then
        return {}
    end

    local okClosure, closure = pcall(getscriptclosureFn, scriptObj)
    if not okClosure or type(closure) ~= "function" then
        return {}
    end

    local found = {}
    local seen = {}

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
                for _, proto in ipairs(protos) do
                    scanFunction(proto, depth + 1)
                end
            end
        end
    end

    scanFunction(closure, 0)
    return found
end

local candidates = {}
local seen = {}

local function addCandidate(obj, source)
    if typeof(obj) ~= "Instance" then return end
    if not (obj:IsA("LocalScript") or obj:IsA("ModuleScript") or obj:IsA("Script")) then return end
    if seen[obj] then return end
    seen[obj] = true

    local path = fullName(obj)
    local lower = path:lower()
    local score = 0

    if lower:find("trait", 1, true) then score += 10 end
    if lower:find("reroll", 1, true) then score += 10 end
    if lower:find("unit", 1, true) then score += 3 end
    if lower:find("collection", 1, true) then score += 2 end
    if lower:find("lobby", 1, true) then score += 1 end
    if source == "loadedmodule" then score += 2 end

    table.insert(candidates, {
        object = obj,
        path = path,
        class = obj.ClassName,
        source = source,
        score = score,
    })
end

if type(getscriptsFn) == "function" then
    local ok, list = pcall(getscriptsFn)
    if ok and type(list) == "table" then
        for _, obj in ipairs(list) do
            addCandidate(obj, "getscripts")
        end
    end
end

if type(getloadedmodulesFn) == "function" then
    local ok, list = pcall(getloadedmodulesFn)
    if ok and type(list) == "table" then
        for _, obj in ipairs(list) do
            addCandidate(obj, "loadedmodule")
        end
    end
end

-- Include obvious ReplicatedStorage trait modules even if not returned above.
for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
    if obj:IsA("ModuleScript") then
        local lower = fullName(obj):lower()
        if lower:find("trait", 1, true) or lower:find("reroll", 1, true) then
            addCandidate(obj, "replicatedstorage")
        end
    end
end

table.sort(candidates, function(a, b)
    if a.score == b.score then
        return a.path < b.path
    end
    return a.score > b.score
end)

local report = {
    metadata = {
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

local function scanCandidate(candidate)
    report.scanned += 1

    local constants = collectConstants(candidate.object)
    local likely = candidate.score > 0 or #constants > 0

    -- Decompile high-signal scripts first. Low-signal scripts are still scanned
    -- later if no match has been found yet.
    local ok, source = pcall(decompileFn, candidate.object)
    if not ok or type(source) ~= "string" then
        if likely then
            table.insert(report.failures, {
                path = candidate.path,
                reason = tostring(source),
            })
        end
        return false
    end

    if containsTarget(source) or #constants > 0 then
        table.insert(report.matches, {
            path = candidate.path,
            class = candidate.class,
            sourceKind = candidate.source,
            score = candidate.score,
            constants = constants,
            snippets = snippetsAround(source),
        })
        return true
    end

    return false
end

print("[TraitSourceDump] Candidates:", #candidates)
print("[TraitSourceDump] Scanning relevant scripts...")

-- Pass 1: strong candidates only.
for index, candidate in ipairs(candidates) do
    if candidate.score > 0 then
        scanCandidate(candidate)
        if index % 8 == 0 then task.wait() end
    end
end

-- Pass 2: if exact call was not found, scan remaining loaded scripts/modules.
local hasExact = false
for _, match in ipairs(report.matches) do
    for _, snippet in ipairs(match.snippets or {}) do
        if snippet.target == "request_token_trait_reroll" then
            hasExact = true
            break
        end
    end
    if hasExact then break end
end

if not hasExact then
    print("[TraitSourceDump] Exact call not found in trait-named scripts; scanning remaining scripts...")
    for index, candidate in ipairs(candidates) do
        if candidate.score <= 0 then
            scanCandidate(candidate)
            if index % 6 == 0 then task.wait() end
        end
    end
end

local encoded = HttpService:JSONEncode(report)

local folder = "CatEmpire"
local diagnostics = folder .. "/Diagnostics"
local path

if type(writefileFn) == "function" then
    if type(makefolderFn) == "function" then
        if type(isfolderFn) ~= "function" or not isfolderFn(folder) then
            pcall(makefolderFn, folder)
        end
        if type(isfolderFn) ~= "function" or not isfolderFn(diagnostics) then
            pcall(makefolderFn, diagnostics)
        end
    end

    path = diagnostics .. "/trait_source_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    local ok = pcall(writefileFn, path, encoded)
    if not ok then path = nil end
end

if not path and type(setclipboardFn) == "function" then
    pcall(setclipboardFn, encoded)
end

print("[TraitSourceDump] Scanned:", report.scanned)
print("[TraitSourceDump] Matches:", #report.matches)
print("[TraitSourceDump] Failures:", #report.failures)
if path then
    print("[TraitSourceDump] Saved:", path)
else
    print("[TraitSourceDump] JSON copied to clipboard.")
end

for _, match in ipairs(report.matches) do
    print("[TraitSourceDump] MATCH:", match.path)
    for _, snippet in ipairs(match.snippets or {}) do
        print("  ->", snippet.target)
    end
end

return report
