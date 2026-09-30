-- Source tracked: ReAdventures790/Main.lua
if game.PlaceId ~= 79073563583903 then
    return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
local Env = (getgenv and getgenv()) or _G
local LOADER_COMMAND = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Loader/Loader.lua", true))()]]

if type(Env.__CE_RE790_CLEANUP) == "function" then
    pcall(Env.__CE_RE790_CLEANUP)
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

local Loader
local EndpointsClient
pcall(function()
    Loader = require(ReplicatedStorage:WaitForChild("src"):WaitForChild("Loader"))
    EndpointsClient = Loader.load_client_service(nil, "EndpointsClient")
end)

local State = {
    Running = true,
    AutoTraits = false,
    AutoStars = false,

    SelectedUnits = {},
    TraitTargets = {},
    DoubleTraitTargets = {},
    TraitSource = "Tokens",
    TraitCursor = 0,
    TraitBusy = false,
    TraitCompleted = {},

    CapsuleTargets = {},
    CapsuleCursor = 0,
    StarBusy = false,
    StarDelay = 0.65,
    StarBatchSize = 10,
    StarsOpened = 0,
    SkipStarAnimations = true,

    AntiAFK = false,
    AutoRejoin = false,
    AutoExecute = false,
    RejoinQueued = false,
}

local WindowRef
local UnitDropdown
local AutoTraitToggle
local AutoStarsToggle
local TraitStatus
local StarsStatus
local CollectionCache
local OwnedCache
local UnitMap = {}
local UnitUUIDToLabel = {}
local LastUnitSignature = ""
local RuntimeConnections = {}
local DisabledStarConnections = {}
local StarVisualHooksInstalled = false
local UnitRefreshQueued = false
local LastUnitUiRefresh = 0
local UNIT_UI_REFRESH_INTERVAL = 0.75
local NativeStarHandler
local NativeStarController

local function setParagraph(paragraph, title, content)
    if not paragraph then
        return
    end
    if paragraph.SetTitle then
        pcall(function() paragraph:SetTitle(title) end)
    end
    if paragraph.SetDesc then
        pcall(function() paragraph:SetDesc(content or "") end)
    end
end

local function setTraitStatus(text)
    setParagraph(TraitStatus, "Traits", tostring(text or ""))
end

local function setStarsStatus(text)
    setParagraph(StarsStatus, "Stars", tostring(text or ""))
end

local function copySelection(target, value)
    table.clear(target)
    if type(value) ~= "table" then
        return
    end
    for key, item in pairs(value) do
        if type(key) == "string" and item == true then
            target[key] = true
        elseif type(item) == "string" then
            target[item] = true
        end
    end
end

local function getEndpointFolder(side)
    local endpoints = ReplicatedStorage:FindFirstChild("endpoints")
    return endpoints and endpoints:FindFirstChild(side)
end

local RpcBusy = false

local function rawInvokeEndpoint(name, ...)
    local args = table.pack(...)

    -- Match the game's own client path first. The native Trait UI uses
    -- EndpointsClient.invoke_server inside task.spawn.
    if EndpointsClient
        and type(EndpointsClient.invoke_server) == "function"
    then
        local ok, a, b, c = pcall(
            EndpointsClient.invoke_server,
            name,
            table.unpack(args, 1, args.n)
        )

        if not ok then
            return false, nil, tostring(a)
        end

        return true, a, b, c
    end

    local folder = getEndpointFolder("client_to_server")
    local endpoint = folder and folder:FindFirstChild(name)

    if endpoint then
        local ok, packed = pcall(function()
            if endpoint:IsA("RemoteFunction") then
                return table.pack(
                    endpoint:InvokeServer(
                        table.unpack(args, 1, args.n)
                    )
                )
            elseif endpoint:IsA("RemoteEvent") then
                endpoint:FireServer(
                    table.unpack(args, 1, args.n)
                )
                return table.pack(true)
            end

            error("unsupported endpoint")
        end)

        if not ok then
            return false, nil, tostring(packed)
        end

        return true, table.unpack(
            packed,
            1,
            packed.n
        )
    end

    return false, nil, "unavailable"
end

local function invokeEndpoint(name, ...)
    local args = table.pack(...)

    -- RemoteFunctions are intentionally serialized. Running use_item and
    -- request_token_trait_reroll concurrently caused executor/client stalls.
    while RpcBusy and State.Running do
        task.wait(0.025)
    end

    if not State.Running then
        return false, nil, "stopped"
    end

    RpcBusy = true

    local result = table.pack(
        rawInvokeEndpoint(
            name,
            table.unpack(args, 1, args.n)
        )
    )

    RpcBusy = false
    task.wait()

    return table.unpack(
        result,
        1,
        result.n
    )
end

local function ownedFromTable(value)
    if type(value) ~= "table" then
        return nil, nil
    end

    local profile = rawget(value, "collection_profile_data")
    local owned = type(profile) == "table" and rawget(profile, "owned_units") or nil
    if type(owned) == "table" then
        return value, owned
    end

    local collection = rawget(value, "collection")
    if type(collection) == "table" then
        profile = rawget(collection, "collection_profile_data")
        owned = type(profile) == "table" and rawget(profile, "owned_units") or nil
        if type(owned) == "table" then
            return collection, owned
        end
    end

    return nil, nil
end

local function getOwnedUnits(force)
    if not force and type(CollectionCache) == "table" then
        local collection, owned = ownedFromTable(CollectionCache)
        if collection and owned then
            OwnedCache = owned
            return owned
        end
    end

    local getgcFn = Env.getgc or rawget(_G, "getgc")
    if type(getgcFn) ~= "function" then
        return nil
    end

    local ok, objects = pcall(getgcFn, true)
    if not ok or type(objects) ~= "table" then
        return nil
    end

    for _, value in ipairs(objects) do
        if type(value) == "table" then
            local collection, owned = ownedFromTable(value)
            if collection and owned then
                CollectionCache = collection
                OwnedCache = owned
                return owned
            end
        end
    end

    return nil
end

local function prettyId(id)
    id = tostring(id or "Unit")
    local text = id:gsub("_", " ")
    return (text:gsub("(%a)([%w']*)", function(a, b)
        return string.upper(a) .. string.lower(b)
    end))
end

local function unitId(unit)
    if type(unit) ~= "table" then
        return "Unit"
    end
    return rawget(unit, "unit_id")
        or rawget(unit, "id")
        or rawget(unit, "unit")
        or rawget(unit, "name")
        or "Unit"
end

local UnitDisplayNames = {}
local UnitNamesScanned = false

local function scanUnitDisplayNames()
    if UnitNamesScanned then
        return
    end

    local src = ReplicatedStorage:FindFirstChild("src")
    local data = src and src:FindFirstChild("Data")
    local unitsRoot = data and data:FindFirstChild("Units")

    if not unitsRoot then
        return
    end

    UnitNamesScanned = true

    for _, module in ipairs(unitsRoot:GetDescendants()) do
        if module:IsA("ModuleScript") then
            local ok, definitions = pcall(require, module)

            if ok and type(definitions) == "table" then
                for key, definition in pairs(definitions) do
                    if type(definition) == "table" then
                        local id = rawget(definition, "id")
                            or (type(key) == "string" and key or nil)

                        local displayName = rawget(definition, "name")
                            or rawget(definition, "display_name")
                            or rawget(definition, "displayName")

                        if type(id) == "string"
                            and id ~= ""
                            and type(displayName) == "string"
                            and displayName ~= ""
                        then
                            UnitDisplayNames[id] = displayName
                        end
                    end
                end
            end
        end
    end
end

local function unitDisplayName(unit)
    local id = tostring(unitId(unit))

    if not UnitNamesScanned then
        scanUnitDisplayNames()
    end

    local direct = type(unit) == "table"
        and (
            rawget(unit, "display_name")
            or rawget(unit, "displayName")
        )
        or nil

    return (type(direct) == "string" and direct ~= "" and direct)
        or UnitDisplayNames[id]
        or prettyId(id)
end

local function traitKey(trait)
    if type(trait) ~= "table" then
        return nil
    end
    local id = tostring(rawget(trait, "trait") or rawget(trait, "id") or "")
    if id == "" then
        return nil
    end
    local tier = tostring(rawget(trait, "tier") or "1")
    return id .. "|" .. tier
end

local Roman = { ["1"] = "I", ["2"] = "II", ["3"] = "III" }
local TraitLabels = {
    ["superior|1"] = "Superior I",
    ["superior|2"] = "Superior II",
    ["superior|3"] = "Superior III",
    ["range|1"] = "Range I",
    ["range|2"] = "Range II",
    ["range|3"] = "Range III",
    ["nimble|1"] = "Nimble I",
    ["nimble|2"] = "Nimble II",
    ["nimble|3"] = "Nimble III",
    ["culling|1"] = "Culling",
    ["neuroplasticity|1"] = "Adept",
    ["sniper|1"] = "Sniper",
    ["godspeed|1"] = "Godspeed",
    ["reaper|1"] = "Reaper",
    ["golden|1"] = "Golden",
    ["divine|1"] = "Divine",
    ["ethereal|1"] = "Celestial",
    ["unique|1"] = "Unique",
}

local TraitValues = {
    "Superior I", "Superior II", "Superior III",
    "Range I", "Range II", "Range III",
    "Nimble I", "Nimble II", "Nimble III",
    "Culling", "Adept", "Sniper", "Godspeed", "Reaper",
    "Golden", "Divine", "Celestial", "Unique",
}

local function currentTraits(uuid)
    local owned = getOwnedUnits(false)
    local unit = owned and owned[uuid]
    local traits = type(unit) == "table" and rawget(unit, "traits") or nil
    return type(traits) == "table" and traits or {}
end

local function traitsFingerprint(traits)
    local parts = {}
    for _, trait in ipairs(traits or {}) do
        local key = traitKey(trait)
        if key then
            parts[#parts + 1] = key
        end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function traitSummary(traits)
    local parts = {}
    for _, trait in ipairs(traits or {}) do
        local key = traitKey(trait)
        local label = key and TraitLabels[key]
        if not label and type(trait) == "table" then
            local id = tostring(rawget(trait, "trait") or rawget(trait, "id") or "Trait")
            local tier = tostring(rawget(trait, "tier") or "1")
            label = prettyId(id) .. (Roman[tier] and (" " .. Roman[tier]) or "")
        end
        if label then
            parts[#parts + 1] = label
        end
    end
    if #parts == 0 then
        return "No Trait"
    end
    return table.concat(parts, " + ")
end

local function matchesTraitTarget(traits)
    if next(State.TraitTargets) == nil then
        return false
    end

    for _, trait in ipairs(traits or {}) do
        local key = traitKey(trait)
        local label = key and TraitLabels[key]

        if label and State.TraitTargets[label] then
            return true
        end
    end

    return false
end

local function matchesDoubleTarget(traits)
    if next(State.DoubleTraitTargets) == nil then
        return false
    end

    local matched = 0

    for _, trait in ipairs(traits or {}) do
        local key = traitKey(trait)
        local label = key and TraitLabels[key]

        if label and State.DoubleTraitTargets[label] then
            matched = matched + 1
        end
    end

    return matched >= 2
end

local function matchesAnyTraitGoal(traits)
    return matchesTraitTarget(traits)
        or matchesDoubleTarget(traits)
end

local function stopAutoTraits(reason)
    State.AutoTraits = false
    if AutoTraitToggle and AutoTraitToggle.SetValue then
        pcall(function() AutoTraitToggle:SetValue(false) end)
    end
    if reason then
        setTraitStatus(reason)
    end
end

local function stopAutoStars(reason)
    State.AutoStars = false
    if AutoStarsToggle and AutoStarsToggle.SetValue then
        pcall(function() AutoStarsToggle:SetValue(false) end)
    end
    if reason then
        setStarsStatus(reason)
    end
end

local function selectedUnitUUIDs()
    local out = {}

    for uuid, enabled in pairs(State.SelectedUnits) do
        if enabled and UnitUUIDToLabel[uuid] then
            out[#out + 1] = uuid
        end
    end

    table.sort(out, function(a, b)
        return tostring(UnitUUIDToLabel[a] or a)
            < tostring(UnitUUIDToLabel[b] or b)
    end)

    return out
end

local function refreshUnits(force)
    local owned = getOwnedUnits(force == true)
    local values = {}
    local map = {}
    local reverse = {}
    local signatureParts = {}
    local duplicates = {}

    if type(owned) == "table" then
        for uuid, unit in pairs(owned) do
            if type(uuid) == "string"
                and type(unit) == "table"
            then
                local name = unitDisplayName(unit)
                local traitText = traitSummary(
                    rawget(unit, "traits") or {}
                )
                local base = string.format(
                    "%s  •  %s",
                    name,
                    traitText
                )

                duplicates[base] = (duplicates[base] or 0) + 1
                local label = base

                if duplicates[base] > 1 then
                    label = string.format(
                        "%s (%d)",
                        base,
                        duplicates[base]
                    )
                end

                values[#values + 1] = label
                map[label] = uuid
                reverse[uuid] = label
                signatureParts[#signatureParts + 1] = label
            end
        end
    end

    table.sort(values)
    table.sort(signatureParts)

    local previousSelected = {}
    for uuid, enabled in pairs(State.SelectedUnits) do
        if enabled then
            previousSelected[uuid] = true
        end
    end

    UnitMap = map
    UnitUUIDToLabel = reverse

    local selectedLabels = {}

    for uuid in pairs(previousSelected) do
        local label = reverse[uuid]
        if label then
            State.SelectedUnits[uuid] = true
            selectedLabels[label] = true
        else
            State.SelectedUnits[uuid] = nil
            State.TraitCompleted[uuid] = nil
        end
    end

    if next(State.SelectedUnits) == nil and values[1] then
        local uuid = map[values[1]]
        if uuid then
            State.SelectedUnits[uuid] = true
            selectedLabels[values[1]] = true
        end
    end

    local signature = table.concat(signatureParts, "|")

    if UnitDropdown
        and UnitDropdown.SetValues
        and (force or signature ~= LastUnitSignature)
    then
        pcall(function()
            UnitDropdown:SetValues(values)
            UnitDropdown:SetValue(selectedLabels)
        end)
    end

    LastUnitSignature = signature
    LastUnitUiRefresh = os.clock()
    return #values
end

local function requestUnitRefresh(force)
    if force then
        UnitRefreshQueued = false
        return refreshUnits(true)
    end

    if UnitRefreshQueued then
        return
    end

    local elapsed = os.clock() - LastUnitUiRefresh
    local delayTime = math.max(
        0,
        UNIT_UI_REFRESH_INTERVAL - elapsed
    )

    UnitRefreshQueued = true

    task.delay(delayTime, function()
        UnitRefreshQueued = false

        if State.Running then
            pcall(refreshUnits, false)
        end
    end)
end

local CapsuleMap = {
    ["Demon Academy Star"] = "capsule_april",
    ["Ocean Star"] = "capsule_marineford",
    ["Desert Star"] = "capsule_narutodesertraid",
    ["Spirit Star"] = "capsule_bleach",
    ["Mysterious Egg #1"] = "easter_egg_reward_1",
    ["Mysterious Egg #2"] = "easter_egg_reward_2",
    ["Mysterious Egg #3"] = "easter_egg_reward_3",
    ["Dimensional Star"] = "capsule_dimension",
    ["Christmas Gift"] = "christmas_gift",
    ["Shiny Christmas Gift"] = "christmas_gift_shiny",
    ["Frozen Star"] = "capsule_christmas",
    ["Blazing Star"] = "capsule_demonslayerraid",
    ["Blood Star"] = "capsule_blood",
    ["Turtle Star"] = "capsule_turtle",
    ["Extinction Star"] = "capsule_aotraid",
    ["Sound Sealed Star"] = "capsule_sound",
    ["Curse Star"] = "capsule_jjk",
    ["Silver Star"] = "capsule_silver",
    ["Love Star"] = "capsule_heart",
    ["Haunted Star"] = "capsule_halloween",
    ["Flash Star"] = "capsule_flash",
    ["Explode Star"] = "capsule_explode",
    ["Ice Flower Star"] = "capsule_ice",
    ["Hybrid Star"] = "capsule_hxhant",
    ["Cool Star"] = "capsule_cool",
    ["Anniversary Star"] = "capsule_anniversary",
    ["Devil Star"] = "capsule_csm_pity",
    ["Star Fruit Capsule"] = "StarFruitCapsule",
    ["Spooky Star"] = "capsule_halloween2",
    ["Summer Star"] = "capsule_summer",
    ["Academy Star"] = "capsule_fairytail",
    ["Magic Sealed Star"] = "capsule_erza",
    ["Celestial Star"] = "capsule_fairytail_infinite",
    ["Icy Star"] = "capsule_christmas2",
    ["Enlightened Star"] = "capsule_enlightened",
    ["Sealed Star (UPD 20)"] = "capsule_infmansionshibuya",
}

local function discoverCapsules()
    local src = ReplicatedStorage:FindFirstChild("src")
    local data = src and src:FindFirstChild("Data")
    local itemsRoot = data and data:FindFirstChild("Items")
    if not itemsRoot then
        return
    end

    for _, module in ipairs(itemsRoot:GetDescendants()) do
        if module:IsA("ModuleScript") then
            local ok, definitions = pcall(require, module)
            if ok and type(definitions) == "table" then
                for itemId, definition in pairs(definitions) do
                    if type(definition) == "table" then
                        local usage = rawget(definition, "usage")
                        if type(usage) == "table" and rawget(usage, "type") == "capsule" then
                            local id = tostring(rawget(definition, "id") or itemId)
                            local label = tostring(rawget(definition, "name") or prettyId(id))
                            if label ~= "" and id ~= "" then
                                CapsuleMap[label] = id
                            end
                        end
                    end
                end
            end
        end
    end
end

discoverCapsules()

local CapsuleValues = {}
for label in pairs(CapsuleMap) do
    CapsuleValues[#CapsuleValues + 1] = label
end
table.sort(CapsuleValues)

local function waitForTraitChange(uuid, before, timeout)
    local deadline = os.clock() + (timeout or 4)
    repeat
        if not State.Running then
            return false, currentTraits(uuid)
        end
        local traits = currentTraits(uuid)
        if traitsFingerprint(traits) ~= before then
            return true, traits
        end
        task.wait(0.08)
    until os.clock() >= deadline
    return false, currentTraits(uuid)
end

local function allSelectedUnitsFinished()
    local uuids = selectedUnitUUIDs()

    if #uuids == 0 then
        return false
    end

    for _, uuid in ipairs(uuids) do
        if not State.TraitCompleted[uuid] then
            return false
        end
    end

    return true
end

local function nextTraitUUID()
    local uuids = selectedUnitUUIDs()

    if #uuids == 0 then
        return nil
    end

    for _ = 1, #uuids do
        State.TraitCursor =
            (State.TraitCursor % #uuids) + 1

        local uuid = uuids[State.TraitCursor]

        if not State.TraitCompleted[uuid] then
            return uuid
        end
    end

    return nil
end

local function processTraitOnce(manual)
    local uuid = nextTraitUUID()

    if not uuid then
        refreshUnits(true)
        uuid = nextTraitUUID()
    end

    if not uuid then
        setTraitStatus("Select at least one character")
        return
    end

    if not manual
        and next(State.TraitTargets) == nil
        and next(State.DoubleTraitTargets) == nil
    then
        setTraitStatus("Select a Trait or a Double Trait target")
        return
    end

    local traits = currentTraits(uuid)
    local label = UnitUUIDToLabel[uuid] or "Character"

    if not manual and matchesAnyTraitGoal(traits) then
        State.TraitCompleted[uuid] = true
        requestUnitRefresh(false)

        if allSelectedUnitsFinished() then
            stopAutoTraits("Finished selected characters")
        else
            setTraitStatus(
                label .. ": target reached"
            )
        end

        return
    end

    local before = traitsFingerprint(traits)
    local ok, result, err

    if State.TraitSource == "Star Remnant" then
        ok, result, err = invokeEndpoint(
            "use_item",
            "star_remnant",
            {unit_uuid = uuid}
        )
    elseif State.TraitSource == "Star Remnant (Limited)" then
        ok, result, err = invokeEndpoint(
            "use_item",
            "star_remnant_limited",
            {unit_uuid = uuid}
        )
    else
        ok, result, err = invokeEndpoint(
            "request_token_trait_reroll",
            uuid
        )
    end

    if not ok then
        setTraitStatus("Trait reroll is temporarily unavailable")
        task.wait(0.8)
        return
    end

    if result == false then
        local reason = tostring(err or "rejected")

        if reason == "not_ready" then
            setTraitStatus("Waiting for the next reroll")
            task.wait(0.35)
            return
        end

        if manual then
            setTraitStatus("Reroll failed")
        else
            stopAutoTraits("Stopped: " .. reason)
        end

        return
    end

    local changed, newTraits =
        waitForTraitChange(uuid, before, 4)

    if changed then
        local summary = traitSummary(newTraits)

        if not manual and matchesAnyTraitGoal(newTraits) then
            State.TraitCompleted[uuid] = true
        end

        requestUnitRefresh(false)

        if not manual and allSelectedUnitsFinished() then
            stopAutoTraits("Finished selected characters")
            return
        end

        setTraitStatus(
            unitDisplayName(
                (getOwnedUnits(false) or {})[uuid]
            )
            .. ": "
            .. summary
        )

        task.wait(0.12)
    else
        setTraitStatus("Updating Trait state...")
        task.wait(0.45)
    end
end

local function rerollSelectedOnce()
    local uuids = selectedUnitUUIDs()

    if #uuids == 0 then
        setTraitStatus("Select at least one character")
        return
    end

    for _, uuid in ipairs(uuids) do
        if not State.Running then
            return
        end

        State.TraitCursor = 0

        local original = State.SelectedUnits
        local only = {[uuid] = true}
        State.SelectedUnits = only

        pcall(processTraitOnce, true)

        State.SelectedUnits = original
        task.wait(0.12)
    end

    requestUnitRefresh(false)
end

local function selectedCapsuleLabels()
    local out = {}
    for _, label in ipairs(CapsuleValues) do
        if State.CapsuleTargets[label] then
            out[#out + 1] = label
        end
    end
    return out
end

local function executorGlobalFunction(name)
    local direct = rawget(Env, name)
        or rawget(_G, name)

    if type(direct) == "function" then
        return direct
    end

    -- Real exposes some executor APIs as true globals without mirroring
    -- every one of them into getgenv()/_G.
    if name == "getconnections" then
        local ok, value = pcall(function()
            return getconnections
        end)
        if ok and type(value) == "function" then
            return value
        end
    elseif name == "getgc" then
        local ok, value = pcall(function()
            return getgc
        end)
        if ok and type(value) == "function" then
            return value
        end
    end

    return nil
end

local function executorDebugMethod(name)
    local debugTable = rawget(Env, "debug")
        or rawget(_G, "debug")

    if type(debugTable) ~= "table" then
        local ok, value = pcall(function()
            return debug
        end)

        if ok and type(value) == "table" then
            debugTable = value
        end
    end

    if type(debugTable) == "table"
        and type(debugTable[name]) == "function"
    then
        return debugTable[name]
    end

    local direct = rawget(Env, name)
        or rawget(_G, name)

    return type(direct) == "function"
        and direct
        or nil
end

local function functionHasConstant(fn, wanted)
    if type(fn) ~= "function" then
        return false
    end

    local getConstants =
        executorDebugMethod("getconstants")

    if type(getConstants) ~= "function" then
        return false
    end

    local ok, constants = pcall(function()
        return getConstants(fn)
    end)

    if not ok or type(constants) ~= "table" then
        return false
    end

    for _, constant in pairs(constants) do
        if constant == wanted then
            return true
        end
    end

    return false
end

local function controllerFromHandler(handler, getUpvalues)
    if type(handler) ~= "function"
        or type(getUpvalues) ~= "function"
    then
        return nil
    end

    local ok, handlerUpvalues = pcall(function()
        return getUpvalues(handler)
    end)

    if not ok or type(handlerUpvalues) ~= "table" then
        return nil
    end

    for _, controller in pairs(handlerUpvalues) do
        if type(controller) == "table" then
            local hasSession =
                type(rawget(controller, "session")) == "table"
            local looksLikeItemsController =
                rawget(controller, "ItemsGrid") ~= nil
                or rawget(controller, "virtual_item_frames") ~= nil
                or rawget(controller, "virtual_grid_frames") ~= nil
                or rawget(controller, "item_group") ~= nil

            if hasSession and looksLikeItemsController then
                return controller
            end
        end
    end

    return nil
end

local function cacheNativeStarUse(handler, controller)
    if type(handler) == "function"
        and type(controller) == "table"
    then
        NativeStarHandler = handler
        NativeStarController = controller

        return NativeStarHandler, NativeStarController
    end

    return nil, nil
end

local function resolveNativeStarUse(force)
    if not force
        and type(NativeStarHandler) == "function"
        and type(NativeStarController) == "table"
    then
        return NativeStarHandler, NativeStarController
    end

    NativeStarHandler = nil
    NativeStarController = nil

    local getConnections =
        executorGlobalFunction("getconnections")
    local getUpvalues =
        executorDebugMethod("getupvalues")

    if type(getUpvalues) ~= "function" then
        return nil, nil
    end

    local activePlayerGui = PlayerGui
        or (
            LocalPlayer
            and LocalPlayer:FindFirstChildOfClass("PlayerGui")
        )

    -- Primary path: this is the exact path confirmed by the runtime
    -- diagnostics. Connection #2 contains one function upvalue: the
    -- inventory item-use handler. Its own upvalue is the items controller.
    if type(getConnections) == "function"
        and activePlayerGui
    then
        local itemsGui =
            activePlayerGui:FindFirstChild("items")
        local grid =
            itemsGui and itemsGui:FindFirstChild("grid")
        local itemOptions =
            grid and grid:FindFirstChild("ItemOptions")
        local main =
            itemOptions and itemOptions:FindFirstChild("Main")
        local options =
            main and main:FindFirstChild("Options")
        local scrolling =
            options and options:FindFirstChild("ScrollingFrame")
        local use10Button =
            scrolling and scrolling:FindFirstChild("Use10")

        if use10Button and use10Button:IsA("GuiButton") then
            local okConnections, connections =
                pcall(function()
                    return getConnections(
                        use10Button.MouseButton1Click
                    )
                end)

            if okConnections
                and type(connections) == "table"
            then
                -- Prefer connection #2 because the runtime test proved
                -- that #1 is only the generic button/SFX handler.
                local ordered = {}

                if connections[2] then
                    ordered[#ordered + 1] =
                        connections[2]
                end

                for index, connection in ipairs(connections) do
                    if index ~= 2 then
                        ordered[#ordered + 1] =
                            connection
                    end
                end

                for _, connection in ipairs(ordered) do
                    local outer = connection.Function

                    if type(outer) == "function" then
                        local okOuter, outerUpvalues =
                            pcall(function()
                                return getUpvalues(outer)
                            end)

                        if okOuter
                            and type(outerUpvalues) == "table"
                        then
                            for _, handler in pairs(outerUpvalues) do
                                if type(handler) == "function" then
                                    local controller =
                                        controllerFromHandler(
                                            handler,
                                            getUpvalues
                                        )

                                    if controller then
                                        return cacheNativeStarUse(
                                            handler,
                                            controller
                                        )
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Fallback: locate the same handler from the already-loaded Lua
    -- objects. This lets Auto Stars work even if the Items window was
    -- never opened by the user in the current session.
    local getGc =
        executorGlobalFunction("getgc")

    if type(getGc) == "function" then
        local okGc, objects = pcall(function()
            return getGc(true)
        end)

        if okGc and type(objects) == "table" then
            for _, object in ipairs(objects) do
                if type(object) == "function"
                    and functionHasConstant(
                        object,
                        "selected_item_uuid_or_id"
                    )
                    and functionHasConstant(
                        object,
                        "usage_from_inventory"
                    )
                then
                    local controller =
                        controllerFromHandler(
                            object,
                            getUpvalues
                        )

                    if controller then
                        return cacheNativeStarUse(
                            object,
                            controller
                        )
                    end
                end
            end
        end
    end

    return nil, nil
end

local function readNativeItemCount(controller, itemId)
    if type(controller) ~= "table" then
        return nil
    end

    local function tryMethod(holder, name)
        if type(holder) ~= "table" then
            return nil
        end

        local fn = rawget(holder, name)

        if type(fn) ~= "function" then
            return nil
        end

        local ok, value = pcall(function()
            return fn(holder, itemId)
        end)

        if ok and tonumber(value) then
            return tonumber(value)
        end

        ok, value = pcall(function()
            return fn(itemId)
        end)

        if ok and tonumber(value) then
            return tonumber(value)
        end

        return nil
    end

    -- The native item handler references get_number_of_owned_item.
    local count =
        tryMethod(
            controller,
            "get_number_of_owned_item"
        )

    if count ~= nil then
        return count
    end

    local session = rawget(controller, "session")
    local inventory =
        type(session) == "table"
        and rawget(session, "inventory")
        or nil

    count =
        tryMethod(
            inventory,
            "get_number_of_owned_item"
        )

    if count ~= nil then
        return count
    end

    -- Last fallback for profile layouts where stackable items live
    -- directly in inventory_profile_data / items tables.
    local profile =
        type(inventory) == "table"
        and rawget(inventory, "inventory_profile_data")
        or nil

    if type(profile) == "table" then
        local direct = rawget(profile, itemId)

        if tonumber(direct) then
            return tonumber(direct)
        end

        if type(direct) == "table" then
            local value =
                rawget(direct, "amount")
                or rawget(direct, "count")
                or rawget(direct, "quantity")

            if tonumber(value) then
                return tonumber(value)
            end
        end

        for _, key in ipairs({
            "items",
            "owned_items",
            "normal_items",
        }) do
            local items = rawget(profile, key)

            if type(items) == "table" then
                local entry = rawget(items, itemId)

                if tonumber(entry) then
                    return tonumber(entry)
                end

                if type(entry) == "table" then
                    local value =
                        rawget(entry, "amount")
                        or rawget(entry, "count")
                        or rawget(entry, "quantity")

                    if tonumber(value) then
                        return tonumber(value)
                    end
                end
            end
        end
    end

    return nil
end

local function waitNativeItemConsumption(
    controller,
    itemId,
    before,
    expected,
    timeout
)
    if before == nil then
        task.wait(
            expected >= 10
                and math.max(0.85, State.StarDelay)
                or math.max(0.22, State.StarDelay)
        )
        return true, nil
    end

    local deadline =
        os.clock() + (timeout or 4)

    repeat
        if not State.Running then
            return false, before
        end

        local current =
            readNativeItemCount(
                controller,
                itemId
            )

        if current ~= nil
            and current <= before - expected
        then
            task.wait(0.08)
            return true, current
        end

        task.wait(0.06)
    until os.clock() >= deadline

    local current =
        readNativeItemCount(
            controller,
            itemId
        )

    return current ~= nil
        and current < before,
        current
end

local function nativeUseCapsule(itemId, useTen)
    local handler, controller =
        resolveNativeStarUse(false)

    if type(handler) ~= "function"
        or type(controller) ~= "table"
    then
        handler, controller =
            resolveNativeStarUse(true)
    end

    if type(handler) ~= "function"
        or type(controller) ~= "table"
    then
        return false, "native Use10 handler unavailable"
    end

    while RpcBusy and State.Running do
        task.wait(0.025)
    end

    if not State.Running then
        return false, "stopped"
    end

    local expected = useTen and 10 or 1
    local before =
        readNativeItemCount(
            controller,
            tostring(itemId)
        )

    controller.selected_item_uuid_or_id =
        tostring(itemId)
    controller.selected_item_is_unique = false

    RpcBusy = true

    local ok, err = pcall(function()
        handler(useTen == true)
    end)

    if not ok then
        RpcBusy = false
        NativeStarHandler = nil
        NativeStarController = nil
        return false, tostring(err)
    end

    -- handler() only schedules the real use_item call. Do not start
    -- the next batch until inventory state confirms that this batch
    -- was consumed (or a conservative fallback delay elapsed).
    local consumed, after =
        waitNativeItemConsumption(
            controller,
            tostring(itemId),
            before,
            expected,
            useTen and 4 or 2
        )

    RpcBusy = false

    if before ~= nil and not consumed then
        return false,
            string.format(
                "batch not confirmed (%s -> %s)",
                tostring(before),
                tostring(after)
            )
    end

    return true, nil, expected
end

local function restoreStarVisualConnections()
    for _, connection in ipairs(DisabledStarConnections) do
        pcall(function()
            if connection
                and type(connection.Enable) == "function"
            then
                connection:Enable()
            end
        end)
    end

    table.clear(DisabledStarConnections)
    StarVisualHooksInstalled = false
end

local function hideStarVisual(item)
    if not State.SkipStarAnimations or not item then
        return
    end

    local name = tostring(item.Name or ""):lower()

    if name:find("hatch", 1, true)
        or name:find("itemreward", 1, true)
        or name:find("item_reward", 1, true)
    then
        pcall(function()
            if item:IsA("ScreenGui") then
                item.Enabled = false
            elseif item:IsA("GuiObject") then
                item.Visible = false
            end
        end)
    end
end

local function installStarVisualHooks()
    if StarVisualHooksInstalled
        or not State.SkipStarAnimations
    then
        return
    end

    StarVisualHooksInstalled = true

    local getConnections = rawget(Env, "getconnections")
        or rawget(_G, "getconnections")

    if type(getConnections) == "function" then
        local folder = getEndpointFolder("server_to_client")

        for _, name in ipairs({
            "show_item_hatch_effect",
            "show_unit_and_item_rewards",
        }) do
            local remote = folder
                and folder:FindFirstChild(name)

            if remote and remote:IsA("RemoteEvent") then
                local ok, connections =
                    pcall(
                        getConnections,
                        remote.OnClientEvent
                    )

                if ok and type(connections) == "table" then
                    for _, connection in ipairs(connections) do
                        if type(connection.Disable) == "function" then
                            local disabled = pcall(function()
                                connection:Disable()
                            end)

                            if disabled then
                                DisabledStarConnections[
                                    #DisabledStarConnections + 1
                                ] = connection
                            end
                        end
                    end
                end
            end
        end
    end

    -- One initial pass only. New animation GUIs are handled by
    -- PlayerGui.DescendantAdded instead of scanning the whole tree per capsule.
    if PlayerGui then
        task.defer(function()
            local ok, descendants =
                pcall(PlayerGui.GetDescendants, PlayerGui)

            if ok and type(descendants) == "table" then
                for _, item in ipairs(descendants) do
                    hideStarVisual(item)
                end
            end
        end)
    end
end

local function setSkipStarAnimations(enabled)
    local nextValue = enabled == true

    if not nextValue then
        State.SkipStarAnimations = false
        restoreStarVisualConnections()
        return
    end

    State.SkipStarAnimations = true
    installStarVisualHooks()
end

local function processStarOnce(manual)
    local selected = selectedCapsuleLabels()

    if #selected == 0 then
        setStarsStatus("Select at least one capsule")
        return
    end

    State.CapsuleCursor =
        (State.CapsuleCursor % #selected) + 1

    local label = selected[State.CapsuleCursor]
    local itemId = CapsuleMap[label]

    if State.SkipStarAnimations then
        installStarVisualHooks()
    end

    local amount = manual
        and 1
        or math.max(
            1,
            math.floor(
                tonumber(State.StarBatchSize) or 10
            )
        )

    local remaining = amount
    local opened = 0

    while remaining > 0 and State.Running do
        local useTen = remaining >= 10
        local step = useTen and 10 or 1

        local ok, err =
            nativeUseCapsule(itemId, useTen)

        if not ok then
            setStarsStatus(
                "Native capsule use failed: "
                .. tostring(err or "unknown")
            )
            task.wait(0.35)
            return
        end

        opened = opened + step
        remaining = remaining - step

        -- Yield between native batches. A requested amount above 10
        -- is intentionally split into the game's real Use10 chunks,
        -- never ten individual remote calls.
        if remaining > 0 then
            task.wait(
                useTen
                    and math.max(0.12, State.StarDelay)
                    or math.max(0.08, State.StarDelay)
            )
        end
    end

    State.StarsOpened =
        State.StarsOpened + opened

    if manual then
        setStarsStatus("Opened: " .. label)
    else
        setStarsStatus(
            string.format(
                "Native x%d  •  %s",
                opened,
                label
            )
        )
    end

    task.wait(
        math.max(0.05, State.StarDelay)
    )
end

local function connectRuntime(signal, callback)
    if not signal then
        return nil
    end

    local connection = signal:Connect(callback)
    RuntimeConnections[#RuntimeConnections + 1] = connection
    return connection
end

local function executorFunction(...)
    for index = 1, select("#", ...) do
        local name = select(index, ...)
        local value = rawget(Env, name)

        if type(value) == "function" then
            return value
        end
    end

    local syn = rawget(Env, "syn")

    if type(syn) == "table"
        and type(syn.queue_on_teleport) == "function"
    then
        return syn.queue_on_teleport
    end

    local fluxus = rawget(Env, "fluxus")

    if type(fluxus) == "table"
        and type(fluxus.queue_on_teleport) == "function"
    then
        return fluxus.queue_on_teleport
    end

    return nil
end

local function queueLoader()
    local queueFn = executorFunction(
        "queue_on_teleport",
        "queueonteleport"
    )

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

    task.delay(1.25, function()
        if not State.Running then
            return
        end

        local ok = pcall(function()
            TeleportService:Teleport(
                game.PlaceId,
                LocalPlayer
            )
        end)

        if not ok then
            State.RejoinQueued = false
        end
    end)
end

if LocalPlayer then
    connectRuntime(LocalPlayer.Idled, function()
        if not State.AntiAFK then
            return
        end

        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(
                Vector2.new(0, 0)
            )
        end)
    end)
end

local errorSignal
pcall(function()
    errorSignal = GuiService.ErrorMessageChanged
end)

if errorSignal then
    connectRuntime(errorSignal, function(message)
        if not State.AutoRejoin then
            return
        end

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
    promptOverlay = promptGui
        and promptGui:FindFirstChild("promptOverlay")
end)

if promptOverlay then
    connectRuntime(promptOverlay.ChildAdded, function(child)
        task.delay(0.1, function()
            if not State.AutoRejoin then
                return
            end

            local name = tostring(
                child and child.Name or ""
            ):lower()

            if name:find("errorprompt", 1, true) then
                requestReconnect()
            end
        end)
    end)
end

if PlayerGui then
    connectRuntime(PlayerGui.DescendantAdded, function(item)
        if State.SkipStarAnimations then
            task.defer(hideStarVisual, item)
        end
    end)
end

local function cleanup()
    State.Running = false
    State.AutoTraits = false
    State.AutoStars = false

    restoreStarVisualConnections()

    for _, connection in ipairs(RuntimeConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(RuntimeConnections)

    if WindowRef and WindowRef.Destroy then
        pcall(function()
            WindowRef:Destroy()
        end)
    elseif Fluent and Fluent.Destroy then
        pcall(function()
            Fluent:Destroy()
        end)
    end

    Env.__CE_RE790_CLEANUP = nil
end
Env.__CE_RE790_CLEANUP = cleanup

local Window = Fluent:CreateWindow({
    Title = "CAT EMPIRE",
    SubTitle = "Re Adventures",
    TabWidth = 150,
    Size = UDim2.fromOffset(760, 470),
    Acrylic = true,
    Animated = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
    ScreenGuiName = "CAT_EMPIRE_RE_ADVENTURES_790",
})
WindowRef = Window

local Tabs = {
    Traits = Window:AddTab({Title = "Traits", Icon = "solar/stars-bold"}),
    Stars = Window:AddTab({Title = "Stars", Icon = "solar/widget-4-bold"}),
    Settings = Window:AddTab({Title = "Settings", Icon = "solar/settings-bold"}),
}

TraitStatus = Tabs.Traits:AddParagraph({
    Title = "Traits",
    Content = "Select characters and target Traits",
})

UnitDropdown = Tabs.Traits:AddDropdown("RE790_Units", {
    Title = "Characters",
    Values = {},
    Multi = true,
    Default = {},
    DropdownOutsideWindow = true,
    Callback = function(value)
        table.clear(State.SelectedUnits)
        State.TraitCompleted = {}

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

                local uuid = enabled
                    and label
                    and UnitMap[label]
                    or nil

                if uuid then
                    State.SelectedUnits[uuid] = true
                end
            end
        elseif type(value) == "string"
            and UnitMap[value]
        then
            State.SelectedUnits[
                UnitMap[value]
            ] = true
        end

        local count = #selectedUnitUUIDs()

        setTraitStatus(
            count > 0
                and string.format(
                    "%d character%s selected",
                    count,
                    count == 1 and "" or "s"
                )
                or "Select at least one character"
        )
    end,
})

Tabs.Traits:AddButton({
    Title = "Refresh Characters",
    Icon = "solar/refresh-bold",
    Callback = function()
        local count = refreshUnits(true)

        setTraitStatus(
            count > 0
                and ("Characters found: " .. tostring(count))
                or "Characters are still loading"
        )
    end,
})

Tabs.Traits:AddDropdown("RE790_TraitSource", {
    Title = "Reroll With",
    Values = {
        "Tokens",
        "Star Remnant",
        "Star Remnant (Limited)",
    },
    Default = "Tokens",
    DropdownOutsideWindow = true,
    Callback = function(value)
        State.TraitSource = value or "Tokens"
    end,
})

Tabs.Traits:AddDropdown("RE790_TraitTargets", {
    Title = "Wanted Traits",
    Values = TraitValues,
    Multi = true,
    Default = {},
    DropdownOutsideWindow = true,
    Callback = function(value)
        copySelection(State.TraitTargets, value)
        State.TraitCompleted = {}
    end,
})

Tabs.Traits:AddDropdown("RE790_DoubleTraitTargets", {
    Title = "Wanted Double Trait",
    Values = TraitValues,
    Multi = true,
    Default = {},
    DropdownOutsideWindow = true,
    Callback = function(value)
        copySelection(
            State.DoubleTraitTargets,
            value
        )
        State.TraitCompleted = {}
    end,
})

AutoTraitToggle = Tabs.Traits:AddToggle("RE790_AutoTraits", {
    Title = "Auto Traits",
    Default = false,
    Callback = function(value)
        State.AutoTraits = value == true

        if value then
            State.TraitCompleted = {}
            State.TraitCursor = 0
            setTraitStatus("Auto Traits running")
        end
    end,
})

Tabs.Traits:AddButton({
    Title = "Reroll Selected Once",
    Icon = "solar/refresh-bold",
    Callback = function()
        if State.TraitBusy then
            return
        end

        State.TraitBusy = true

        task.spawn(function()
            pcall(rerollSelectedOnce)
            State.TraitBusy = false
        end)
    end,
})

StarsStatus = Tabs.Stars:AddParagraph({
    Title = "Stars",
    Content = "Uses the game's native Use 10 flow; larger amounts run in native x10 chunks"
})

Tabs.Stars:AddDropdown("RE790_Capsules", {
    Title = "Capsules",
    Values = CapsuleValues,
    Multi = true,
    Default = {},
    DropdownOutsideWindow = true,
    Callback = function(value)
        copySelection(State.CapsuleTargets, value)
    end,
})

Tabs.Stars:AddInput("RE790_StarBatchSize", {
    Title = "Open At Once",
    Default = "10",
    Placeholder = "10",
    Numeric = true,
    Callback = function(value)
        State.StarBatchSize = math.max(
            1,
            math.floor(tonumber(value) or 10)
        )
    end,
})

if type(Tabs.Stars.AddSlider) == "function" then
    Tabs.Stars:AddSlider("RE790_StarDelay", {
        Title = "Time Between Openings",
        Default = 0.65,
        Min = 0.05,
        Max = 5,
        Rounding = 2,
        Callback = function(value)
            State.StarDelay = math.max(
                0.05,
                tonumber(value) or 0.65
            )
        end,
    })
else
    Tabs.Stars:AddInput("RE790_StarDelay", {
        Title = "Time Between Capsules",
        Default = "0.65",
        Placeholder = "0.65",
        Numeric = true,
        Callback = function(value)
            State.StarDelay = math.max(
                0.05,
                tonumber(value) or 0.65
            )
        end,
    })
end

Tabs.Stars:AddToggle("RE790_SkipStarAnimations", {
    Title = "Skip Opening Animations",
    Default = true,
    Callback = function(value)
        setSkipStarAnimations(value == true)
    end,
})

AutoStarsToggle = Tabs.Stars:AddToggle("RE790_AutoStars", {
    Title = "Auto Stars",
    Default = false,
    Callback = function(value)
        State.AutoStars = value == true

        if value then
            State.StarsOpened = 0
            State.CapsuleCursor = 0
            setStarsStatus(
                string.format(
                    "Open at once: %d",
                    State.StarBatchSize
                )
            )
        end
    end,
})

Tabs.Stars:AddButton({
    Title = "Open Once",
    Icon = "solar/refresh-bold",
    Callback = function()
        if State.StarBusy then
            return
        end

        State.StarBusy = true

        task.spawn(function()
            pcall(processStarOnce, true)
            State.StarBusy = false
        end)
    end,
})

Tabs.Settings:AddSection("Session")

Tabs.Settings:AddToggle("RE790_AntiAFK", {
    Title = "Anti AFK",
    Default = false,
    Callback = function(value)
        State.AntiAFK = value == true
    end,
})

Tabs.Settings:AddToggle("RE790_AutoRejoin", {
    Title = "Auto Rejoin",
    Default = false,
    Callback = function(value)
        State.AutoRejoin = value == true

        if not value then
            State.RejoinQueued = false
        end
    end,
})

Tabs.Settings:AddToggle("RE790_AutoExecute", {
    Title = "Auto Load After Rejoin",
    Default = false,
    Callback = function(value)
        State.AutoExecute = value == true

        if value then
            pcall(queueLoader)
        end
    end,
})

Tabs.Settings:AddSection("Interface")

Tabs.Settings:AddDropdown("RE790_Theme", {
    Title = "Theme",
    Values = Fluent.Themes,
    Default = "Dark",
    DropdownOutsideWindow = true,
    Callback = function(value)
        pcall(function()
            Fluent:SetTheme(value)
        end)
    end,
})

Tabs.Settings:AddButton({
    Title = "Unload CAT EMPIRE",
    Icon = "solar/power-bold",
    Callback = cleanup,
})

setSkipStarAnimations(true)
refreshUnits(true)

task.spawn(function()
    local lastRefresh = 0

    while State.Running do
        local current = os.clock()

        if current - lastRefresh >= 6 then
            lastRefresh = current
            requestUnitRefresh(false)
        end

        task.wait(0.5)
    end
end)

task.spawn(function()
    while State.Running do
        if State.AutoTraits and not State.TraitBusy then
            State.TraitBusy = true

            task.spawn(function()
                local ok = pcall(
                    processTraitOnce,
                    false
                )

                if not ok then
                    setTraitStatus(
                        "Auto Traits paused briefly"
                    )
                    task.wait(0.5)
                end

                State.TraitBusy = false
            end)
        end

        task.wait(0.12)
    end
end)

task.spawn(function()
    while State.Running do
        if State.AutoStars and not State.StarBusy then
            State.StarBusy = true

            task.spawn(function()
                local ok = pcall(
                    processStarOnce,
                    false
                )

                if not ok then
                    setStarsStatus(
                        "Auto Stars paused briefly"
                    )
                    task.wait(0.5)
                end

                State.StarBusy = false
            end)
        end

        task.wait(0.12)
    end
end)

Fluent:Notify({
    Title = "CAT EMPIRE",
    Content = "Re Adventures loaded",
    Duration = 3,
})
