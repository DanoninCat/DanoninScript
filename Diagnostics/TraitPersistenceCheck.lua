-- Re Adventures - Trait Persistence Check (Real executor)
-- READ-ONLY. Stores a selected unit UUID/trait locally, then compares after rejoin.
-- Does not fire remotes, hook functions, or modify game state.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
assert(player, "LocalPlayer unavailable")

local env = (getgenv and getgenv()) or _G

local function fn(name)
    local v = rawget(env, name)
    if type(v) == "function" then return v end
    local ok, fallback = pcall(function() return _G[name] end)
    if ok and type(fallback) == "function" then return fallback end
    return nil
end

local getgcFn = assert(fn("getgc"), "getgc unavailable")
local writefileFn = assert(fn("writefile"), "writefile unavailable")
local readfileFn = fn("readfile")
local isfileFn = fn("isfile")
local makefolderFn = fn("makefolder")
local isfolderFn = fn("isfolder")

local folder = "CatEmpire"
local diagnostics = folder .. "/Diagnostics"
local baselinePath = diagnostics .. "/trait_persistence_baseline.json"

if makefolderFn then
    if not isfolderFn or not isfolderFn(folder) then pcall(makefolderFn, folder) end
    if not isfolderFn or not isfolderFn(diagnostics) then pcall(makefolderFn, diagnostics) end
end

local function raw(tbl, key)
    local ok, v = pcall(rawget, tbl, key)
    return ok and v or nil
end

local function normalizeTraits(traits)
    if type(traits) ~= "table" then return {} end
    local out = {}
    for _, v in pairs(traits) do
        if type(v) == "table" then
            table.insert(out, {
                trait = tostring(raw(v, "trait") or ""),
                tier = tostring(raw(v, "tier") or ""),
            })
        end
    end
    table.sort(out, function(a,b)
        if a.trait == b.trait then return a.tier < b.tier end
        return a.trait < b.trait
    end)
    return out
end

local gc = getgcFn(true)
local selectedUuid
local collection

for _, obj in ipairs(gc) do
    if type(obj) == "table" then
        local uuid = raw(obj, "applying_unit_uuid")
        local name = raw(obj, "_ui_instance_name")
        if name == "trait_reroll_ui" and type(uuid) == "string" and uuid ~= "" then
            selectedUuid = uuid
        end

        local getUnit = raw(obj, "get_unit_by_uuid")
        local data = raw(obj, "collection_profile_data")
        if type(getUnit) == "function" and type(data) == "table" then
            collection = obj
        end
    end
end

local baseline
if readfileFn and (not isfileFn or isfileFn(baselinePath)) then
    local ok, text = pcall(readfileFn, baselinePath)
    if ok and type(text) == "string" and text ~= "" then
        local decodedOk, decoded = pcall(HttpService.JSONDecode, HttpService, text)
        if decodedOk and type(decoded) == "table" then
            baseline = decoded
        end
    end
end

local targetUuid = selectedUuid or (baseline and baseline.uuid)
assert(type(targetUuid) == "string" and targetUuid ~= "",
    "Select the unit in Trait Reroll on the first run, or keep the baseline file for post-rejoin check.")

assert(collection, "Collection object not found")

local getUnit = raw(collection, "get_unit_by_uuid")
local ok, unit = pcall(getUnit, collection, targetUuid)
assert(ok and type(unit) == "table", "Unit record not found for UUID " .. tostring(targetUuid))

local current = {
    uuid = targetUuid,
    unit_id = tostring(raw(unit, "unit_id") or ""),
    traits = normalizeTraits(raw(unit, "traits")),
    observedAt = os.time(),
    jobId = game.JobId,
    placeId = game.PlaceId,
}

if not baseline then
    writefileFn(baselinePath, HttpService:JSONEncode(current))
    print("========================================")
    print(" TRAIT PERSISTENCE BASELINE SAVED")
    print("========================================")
    print("UUID:", current.uuid)
    print("Unit:", current.unit_id)
    print("Traits:", HttpService:JSONEncode(current.traits))
    print("JobId:", current.jobId)
    print("Baseline:", baselinePath)
    print("Now rejoin/reconnect, then run this script again.")
    print("========================================")
    return {
        mode = "baseline",
        current = current,
        path = baselinePath,
    }
end

local sameTraits = HttpService:JSONEncode(baseline.traits or {})
    == HttpService:JSONEncode(current.traits or {})
local sameJob = tostring(baseline.jobId or "") == tostring(current.jobId or "")

local result = {
    mode = "compare",
    baseline = baseline,
    current = current,
    sameTraits = sameTraits,
    sameJob = sameJob,
}

local resultPath = diagnostics .. "/trait_persistence_result_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
writefileFn(resultPath, HttpService:JSONEncode(result))

print("========================================")
print(" TRAIT PERSISTENCE RESULT")
print("========================================")
print("UUID:", current.uuid)
print("Baseline traits:", HttpService:JSONEncode(baseline.traits or {}))
print("Current traits:", HttpService:JSONEncode(current.traits or {}))
print("Same traits:", sameTraits)
print("Same server JobId:", sameJob)
print("Saved:", resultPath)
print("========================================")

return result
