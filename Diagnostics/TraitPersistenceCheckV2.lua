-- Re Adventures - Trait Persistence Check V2
-- READ-ONLY: no remotes, no hooks, no game-state mutation.
local VERSION = "2.0.0-direct-gc"
print("[TraitPersistenceV2] VERSION:", VERSION)

local HttpService = game:GetService("HttpService")
local env = (getgenv and getgenv()) or _G

local function fn(name)
    local v = rawget(env, name)
    if type(v) == "function" then return v end
    local ok, fallback = pcall(function() return _G[name] end)
    if ok and type(fallback) == "function" then return fallback end
end

local getgcFn = assert(fn("getgc"), "getgc unavailable")
local writefileFn = assert(fn("writefile"), "writefile unavailable")
local readfileFn = fn("readfile")
local isfileFn = fn("isfile")
local makefolderFn = fn("makefolder")
local isfolderFn = fn("isfolder")

local folder = "CatEmpire"
local diagnostics = folder .. "/Diagnostics"
local baselinePath = diagnostics .. "/trait_persistence_baseline_v2.json"

if makefolderFn then
    if not isfolderFn or not isfolderFn(folder) then pcall(makefolderFn, folder) end
    if not isfolderFn or not isfolderFn(diagnostics) then pcall(makefolderFn, diagnostics) end
end

local function raw(tbl, key)
    local ok, v = pcall(rawget, tbl, key)
    return ok and v or nil
end

local function decodeFile(path)
    if not readfileFn then return nil end
    if isfileFn and not isfileFn(path) then return nil end
    local ok, text = pcall(readfileFn, path)
    if not ok or type(text) ~= "string" or text == "" then return nil end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, text)
    return ok2 and type(data) == "table" and data or nil
end

local function normalizeTraits(traits)
    if type(traits) ~= "table" then return {} end
    local out = {}
    for _, v in pairs(traits) do
        if type(v) == "table" then
            out[#out+1] = {
                trait = tostring(raw(v, "trait") or ""),
                tier = tostring(raw(v, "tier") or ""),
            }
        end
    end
    table.sort(out, function(a,b)
        if a.trait == b.trait then return a.tier < b.tier end
        return a.trait < b.trait
    end)
    return out
end

local baseline = decodeFile(baselinePath)
local selectedUuid

-- Discover selected Trait Reroll UUID without invoking metamethods.
for _, obj in ipairs(getgcFn(true)) do
    if type(obj) == "table" then
        local uuid = raw(obj, "applying_unit_uuid")
        if type(uuid) == "string" and uuid ~= "" then
            local uiName = raw(obj, "_ui_instance_name")
            local reroll = raw(obj, "current_reroll_in_progress")
            local tokenButton = raw(obj, "TokenRerollButton")
            if uiName == "trait_reroll_ui" or reroll ~= nil or tokenButton ~= nil then
                selectedUuid = uuid
                break
            end
        end
    end
end

local targetUuid = selectedUuid or (baseline and baseline.uuid)
assert(type(targetUuid) == "string" and targetUuid ~= "",
    "Open Trait Reroll and select the unit on the first V2 run.")

local function findUnit(uuid)
    local gc = getgcFn(true)

    -- Best case: the unit record itself is visible in GC.
    for _, obj in ipairs(gc) do
        if type(obj) == "table" then
            local objectUuid = raw(obj, "uuid")
            if objectUuid ~= nil and tostring(objectUuid) == uuid then
                local unitId = raw(obj, "unit_id")
                local traits = raw(obj, "traits")
                if unitId ~= nil or type(traits) == "table" then
                    return obj, "direct_uuid_record"
                end
            end
        end
    end

    -- Fallback: a container is keyed directly by UUID.
    for _, obj in ipairs(gc) do
        if type(obj) == "table" then
            local record = raw(obj, uuid)
            if type(record) == "table" then
                local unitId = raw(record, "unit_id")
                local traits = raw(record, "traits")
                local objectUuid = raw(record, "uuid")
                if unitId ~= nil or type(traits) == "table" or tostring(objectUuid or "") == uuid then
                    return record, "uuid_keyed_container"
                end
            end
        end
    end

    -- Fallback matching the profile structure seen in the previous probes.
    for _, obj in ipairs(gc) do
        if type(obj) == "table" then
            local profile = raw(obj, "collection_profile_data")
            if type(profile) == "table" then
                local owned = raw(profile, "owned_units")
                if type(owned) == "table" then
                    local record = raw(owned, uuid)
                    if type(record) == "table" then
                        return record, "nested_collection_profile_data_owned_units"
                    end
                end
            end
        end
    end
end

local unit, resolver
local deadline = os.clock() + 30
repeat
    unit, resolver = findUnit(targetUuid)
    if unit then break end
    task.wait(0.5)
until os.clock() >= deadline

assert(unit, "V2 could not find unit record for UUID " .. targetUuid)

local current = {
    probeVersion = VERSION,
    uuid = targetUuid,
    unit_id = tostring(raw(unit, "unit_id") or ""),
    traits = normalizeTraits(raw(unit, "traits")),
    observedAt = os.time(),
    jobId = game.JobId,
    placeId = game.PlaceId,
    resolver = resolver,
}

if not baseline then
    writefileFn(baselinePath, HttpService:JSONEncode(current))
    print("========================================")
    print(" TRAIT PERSISTENCE V2 - BASELINE SAVED")
    print("========================================")
    print("UUID:", current.uuid)
    print("Unit:", current.unit_id)
    print("Traits:", HttpService:JSONEncode(current.traits))
    print("JobId:", current.jobId)
    print("Resolver:", current.resolver)
    print("Saved:", baselinePath)
    print("Rejoin, then run this exact V2 script again.")
    print("========================================")
    return {mode="baseline", current=current, path=baselinePath}
end

local sameTraits = HttpService:JSONEncode(baseline.traits or {}) == HttpService:JSONEncode(current.traits or {})
local sameJob = tostring(baseline.jobId or "") == tostring(current.jobId or "")
local result = {
    mode = "compare",
    probeVersion = VERSION,
    baseline = baseline,
    current = current,
    sameTraits = sameTraits,
    sameJob = sameJob,
}
local resultPath = diagnostics .. "/trait_persistence_result_v2_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
writefileFn(resultPath, HttpService:JSONEncode(result))

print("========================================")
print(" TRAIT PERSISTENCE V2 - RESULT")
print("========================================")
print("UUID:", current.uuid)
print("Baseline traits:", HttpService:JSONEncode(baseline.traits or {}))
print("Current traits:", HttpService:JSONEncode(current.traits or {}))
print("Same traits:", sameTraits)
print("Same server JobId:", sameJob)
print("Resolver:", current.resolver)
print("Saved:", resultPath)
print("========================================")
return result
