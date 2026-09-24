-- Re Adventures - Trait Rollback Research Probe (Real executor)
-- READ-ONLY. Does not fire remotes, hook functions, mutate tables, or change game state.
-- Run once BEFORE a manual reroll and again AFTER the reroll.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
assert(player, "LocalPlayer unavailable")
local playerGui = player:FindFirstChildOfClass("PlayerGui")
local traitGui = playerGui and playerGui:FindFirstChild("TraitReroll")

local env = (getgenv and getgenv()) or _G

local function fn(name)
    local v = rawget(env, name)
    if type(v) == "function" then return v end
    local ok, fallback = pcall(function() return _G[name] end)
    if ok and type(fallback) == "function" then return fallback end
    return nil
end

local getgcFn = assert(fn("getgc"), "getgc unavailable")
local getscriptsFn = fn("getscripts")
local getloadedmodulesFn = fn("getloadedmodules")
local decompileFn = fn("decompile")
local writefileFn = fn("writefile")
local makefolderFn = fn("makefolder")
local isfolderFn = fn("isfolder")
local setclipboardFn = fn("setclipboard")

local function fullName(v)
    if typeof(v) ~= "Instance" then return tostring(v) end
    local ok, name = pcall(function() return v:GetFullName() end)
    return ok and name or tostring(v)
end

local function primitive(v)
    local t = typeof(v)
    if t == "nil" or t == "boolean" or t == "number" or t == "string" then
        if t == "string" and #v > 1000 then
            return v:sub(1, 1000) .. "...<truncated>"
        end
        return v
    elseif t == "Instance" then
        return "<" .. v.ClassName .. " " .. fullName(v) .. ">"
    elseif t == "Vector3" or t == "Vector2" or t == "CFrame"
        or t == "Color3" or t == "UDim2" or t == "EnumItem"
    then
        return "<" .. t .. " " .. tostring(v) .. ">"
    end
    return "<" .. t .. ">"
end

local function shallowTable(tbl, maxFields)
    local out = {}
    local count = 0
    for k, v in pairs(tbl) do
        count += 1
        if count > (maxFields or 80) then
            out["<truncated>"] = true
            break
        end
        local key = tostring(k)
        if type(v) == "table" then
            local nested = {}
            local n = 0
            for nk, nv in pairs(v) do
                n += 1
                if n > 25 then
                    nested["<truncated>"] = true
                    break
                end
                if type(nv) ~= "table" and type(nv) ~= "function" and type(nv) ~= "userdata" and type(nv) ~= "thread" then
                    nested[tostring(nk)] = primitive(nv)
                elseif typeof(nv) == "Instance" then
                    nested[tostring(nk)] = primitive(nv)
                end
            end
            out[key] = nested
        elseif type(v) ~= "function" and type(v) ~= "userdata" and type(v) ~= "thread" then
            out[key] = primitive(v)
        elseif typeof(v) == "Instance" then
            out[key] = primitive(v)
        end
    end
    return out
end

local function traitsFromRecord(record)
    if type(record) ~= "table" then return nil end
    local candidates = {
        "traits", "_traits", "trait", "_trait",
        "trait_data", "_traits_string",
    }
    local out = {}
    for _, key in ipairs(candidates) do
        if record[key] ~= nil then
            local v = record[key]
            if type(v) == "table" then
                out[key] = shallowTable(v, 30)
            else
                out[key] = primitive(v)
            end
        end
    end
    return next(out) and out or nil
end

local report = {
    metadata = {
        generatedAt = os.time(),
        placeId = game.PlaceId,
        gameId = game.GameId,
        jobId = game.JobId,
        player = player.Name,
    },
    traitControllers = {},
    selectedUuid = nil,
    collectionCandidates = {},
    uuidReferences = {},
    sourceMatches = {},
    sourceFailures = {},
}

-- Phase 1: identify the live TraitReroll controller and selected UUID.
local gc = getgcFn(true)
local seenTables = {}

for _, obj in ipairs(gc) do
    if type(obj) == "table" and not seenTables[obj] then
        seenTables[obj] = true

        local looksLikeTraitController =
            obj.applying_unit_uuid ~= nil
            or obj.current_reroll_in_progress ~= nil
            or obj.TokenRerollButton ~= nil
            or (traitGui ~= nil and obj.screenGUI == traitGui)

        if looksLikeTraitController then
            local entry = {
                applying_unit_uuid = primitive(obj.applying_unit_uuid),
                selected_item_id = primitive(obj.selected_item_id),
                current_reroll_in_progress = primitive(obj.current_reroll_in_progress),
                isOpen = primitive(obj.IsOpen),
                screenGUI = primitive(obj.screenGUI),
                hasSession = type(obj.session) == "table",
                fields = shallowTable(obj, 100),
            }
            table.insert(report.traitControllers, entry)

            if type(obj.applying_unit_uuid) == "string" and obj.applying_unit_uuid ~= "" then
                report.selectedUuid = obj.applying_unit_uuid
            end
        end
    end
end

local selectedUuid = report.selectedUuid

-- Phase 2: locate collection/session-like tables and inspect the selected UUID record.
for _, obj in ipairs(gc) do
    if type(obj) == "table" then
        local hasGet = type(rawget(obj, "get_unit_by_uuid")) == "function"
        local hasChange = type(rawget(obj, "change_traits")) == "function"

        if hasGet or hasChange then
            local entry = {
                hasGetUnitByUuid = hasGet,
                hasChangeTraits = hasChange,
                fields = shallowTable(obj, 100),
            }

            if selectedUuid and hasGet then
                local ok, record = pcall(obj.get_unit_by_uuid, obj, selectedUuid)
                entry.lookupOk = ok
                if ok and type(record) == "table" then
                    entry.unitRecord = shallowTable(record, 120)
                    entry.unitTraits = traitsFromRecord(record)
                else
                    entry.lookupResult = primitive(record)
                end
            end

            table.insert(report.collectionCandidates, entry)
        end
    end
end

-- Phase 3: find every live table that directly references the UUID or a record with that UUID.
if selectedUuid then
    local refCount = 0
    for _, obj in ipairs(gc) do
        if type(obj) == "table" then
            local hit = false
            local reasons = {}

            local direct = rawget(obj, selectedUuid)
            if direct ~= nil then
                hit = true
                table.insert(reasons, "key_uuid")
            end

            for _, key in ipairs({"uuid", "_uuid", "unit_uuid", "applying_unit_uuid", "selected_unit_uuid"}) do
                if rawget(obj, key) == selectedUuid then
                    hit = true
                    table.insert(reasons, key)
                end
            end

            if hit then
                refCount += 1
                if refCount <= 120 then
                    local entry = {
                        reasons = reasons,
                        fields = shallowTable(obj, 120),
                    }

                    if type(direct) == "table" then
                        entry.directRecord = shallowTable(direct, 120)
                        entry.directTraits = traitsFromRecord(direct)
                    end

                    local selfTraits = traitsFromRecord(obj)
                    if selfTraits then
                        entry.selfTraits = selfTraits
                    end

                    table.insert(report.uuidReferences, entry)
                end
            end
        end
    end
end

-- Phase 4: decompile client modules that reveal how collection trait state is changed.
if type(decompileFn) == "function" then
    local scripts = {}
    local seen = {}

    local function addList(list)
        if type(list) ~= "table" then return end
        for _, s in ipairs(list) do
            if typeof(s) == "Instance"
                and (s:IsA("ModuleScript") or s:IsA("LocalScript") or s:IsA("Script"))
                and not seen[s]
            then
                seen[s] = true
                table.insert(scripts, s)
            end
        end
    end

    if type(getscriptsFn) == "function" then
        local ok, list = pcall(getscriptsFn)
        if ok then addList(list) end
    end
    if type(getloadedmodulesFn) == "function" then
        local ok, list = pcall(getloadedmodulesFn)
        if ok then addList(list) end
    end

    local targets = {
        "function u0:change_traits",
        "function u0.change_traits",
        ":change_traits(",
        "collection_profile_data",
        "request_token_trait_reroll",
        "unit_trait_transfer",
        "_traits_string",
    }

    local function captureSnippets(source)
        local snippets = {}
        local lower = source:lower()
        for _, target in ipairs(targets) do
            local needle = target:lower()
            local from = 1
            while true do
                local a, b = lower:find(needle, from, true)
                if not a then break end
                table.insert(snippets, {
                    target = target,
                    snippet = source:sub(math.max(1, a - 1800), math.min(#source, b + 3000)),
                })
                if #snippets >= 15 then return snippets end
                from = b + 1
            end
        end
        return snippets
    end

    for index, s in ipairs(scripts) do
        local ok, source = pcall(decompileFn, s)
        if ok and type(source) == "string" then
            local snippets = captureSnippets(source)
            if #snippets > 0 then
                table.insert(report.sourceMatches, {
                    path = fullName(s),
                    class = s.ClassName,
                    snippets = snippets,
                })
            end
        elseif not ok then
            if #report.sourceFailures < 30 then
                table.insert(report.sourceFailures, {
                    path = fullName(s),
                    error = tostring(source),
                })
            end
        end

        if index % 10 == 0 then
            task.wait()
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

    path = diagnostics .. "/trait_rollback_probe_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    local ok = pcall(writefileFn, path, encoded)
    if not ok then path = nil end
end

if not path and type(setclipboardFn) == "function" then
    pcall(setclipboardFn, encoded)
end

print("========================================")
print(" TRAIT ROLLBACK RESEARCH PROBE")
print("========================================")
print("Selected UUID:", selectedUuid or "<not found>")
print("Trait controllers:", #report.traitControllers)
print("Collection candidates:", #report.collectionCandidates)
print("UUID references:", #report.uuidReferences)
print("Source matches:", #report.sourceMatches)
print("Source failures:", #report.sourceFailures)
if path then
    print("Saved:", path)
else
    print("JSON copied to clipboard.")
end
print("========================================")

return report
