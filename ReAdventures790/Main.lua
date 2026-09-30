-- Source tracked: ReAdventures790/Main.lua
if game.PlaceId ~= 79073563583903 then
    return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Env = (getgenv and getgenv()) or _G

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
    ProtectDouble = true,
    SelectedUnitLabel = nil,
    SelectedUnitUUID = nil,
    TraitTargets = {},
    TraitSource = "Tokens",
    CapsuleTargets = {},
    CapsuleCursor = 0,
    ActionBusy = false,
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
local LastUnitSignature = ""

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

local function invokeEndpoint(name, ...)
    local args = table.pack(...)
    local folder = getEndpointFolder("client_to_server")
    local endpoint = folder and folder:FindFirstChild(name)

    if endpoint then
        local ok, packed = pcall(function()
            if endpoint:IsA("RemoteFunction") then
                return table.pack(endpoint:InvokeServer(table.unpack(args, 1, args.n)))
            elseif endpoint:IsA("RemoteEvent") then
                endpoint:FireServer(table.unpack(args, 1, args.n))
                return table.pack(true)
            end
            error("unsupported endpoint")
        end)
        if not ok then
            return false, nil, tostring(packed)
        end
        return true, table.unpack(packed, 1, packed.n)
    end

    if EndpointsClient and type(EndpointsClient.invoke_server) == "function" then
        local ok, a, b, c = pcall(EndpointsClient.invoke_server, name, table.unpack(args, 1, args.n))
        if not ok then
            return false, nil, tostring(a)
        end
        return true, a, b, c
    end

    return false, nil, "unavailable"
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

local function refreshUnits(force)
    local owned = getOwnedUnits(force == true)
    local values = {}
    local map = {}
    local signatureParts = {}

    if type(owned) == "table" then
        for uuid, unit in pairs(owned) do
            if type(uuid) == "string" and type(unit) == "table" then
                local label = string.format("%s | %s", prettyId(unitId(unit)), string.sub(uuid, 1, 8))
                values[#values + 1] = label
                map[label] = uuid
                signatureParts[#signatureParts + 1] = label
            end
        end
    end

    table.sort(values)
    table.sort(signatureParts)
    local signature = table.concat(signatureParts, "|")
    UnitMap = map

    if UnitDropdown and UnitDropdown.SetValues and (force or signature ~= LastUnitSignature) then
        pcall(function() UnitDropdown:SetValues(values) end)
    end
    LastUnitSignature = signature

    if State.SelectedUnitLabel and UnitMap[State.SelectedUnitLabel] then
        State.SelectedUnitUUID = UnitMap[State.SelectedUnitLabel]
    elseif values[1] then
        State.SelectedUnitLabel = values[1]
        State.SelectedUnitUUID = UnitMap[values[1]]
        if UnitDropdown and UnitDropdown.SetValue then
            pcall(function() UnitDropdown:SetValue(values[1]) end)
        end
    else
        State.SelectedUnitLabel = nil
        State.SelectedUnitUUID = nil
    end

    return #values
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

local function processTraitOnce()
    local uuid = State.SelectedUnitUUID
    if not uuid then
        refreshUnits(true)
        uuid = State.SelectedUnitUUID
    end
    if not uuid then
        setTraitStatus("Select a unit")
        return
    end
    if next(State.TraitTargets) == nil then
        setTraitStatus("Select at least one wanted Trait")
        return
    end

    local traits = currentTraits(uuid)
    if matchesTraitTarget(traits) then
        stopAutoTraits("Finished: " .. traitSummary(traits))
        return
    end
    if State.ProtectDouble and #traits >= 2 then
        stopAutoTraits("Stopped on Double Trait: " .. traitSummary(traits))
        return
    end

    local before = traitsFingerprint(traits)
    local ok, result, err
    if State.TraitSource == "Star Remnant" then
        ok, result, err = invokeEndpoint("use_item", "star_remnant", {unit_uuid = uuid})
    elseif State.TraitSource == "Star Remnant (Limited)" then
        ok, result, err = invokeEndpoint("use_item", "star_remnant_limited", {unit_uuid = uuid})
    else
        ok, result, err = invokeEndpoint("request_token_trait_reroll", uuid)
    end

    if not ok then
        setTraitStatus("Waiting for game action")
        task.wait(1.2)
        return
    end
    if result == false then
        local reason = tostring(err or "rejected")
        if reason == "not_ready" then
            setTraitStatus("Game is not ready yet")
            task.wait(0.8)
            return
        end
        stopAutoTraits("Stopped: " .. reason)
        return
    end

    local changed, newTraits = waitForTraitChange(uuid, before, 4)
    if changed then
        local summary = traitSummary(newTraits)
        setTraitStatus("Rolled: " .. summary)
        if matchesTraitTarget(newTraits) then
            stopAutoTraits("Finished: " .. summary)
            return
        end
        if State.ProtectDouble and #newTraits >= 2 then
            stopAutoTraits("Stopped on Double Trait: " .. summary)
            return
        end
        task.wait(0.2)
    else
        setTraitStatus("Synchronizing Trait state")
        task.wait(1.0)
    end
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

local function processStarOnce()
    local selected = selectedCapsuleLabels()
    if #selected == 0 then
        setStarsStatus("Select at least one capsule")
        return
    end

    State.CapsuleCursor = (State.CapsuleCursor % #selected) + 1
    local label = selected[State.CapsuleCursor]
    local itemId = CapsuleMap[label]
    local ok, result, err = invokeEndpoint("use_item", itemId)

    if not ok then
        setStarsStatus("Waiting for inventory service")
        task.wait(1.2)
        return
    end
    if result == false then
        setStarsStatus(label .. ": " .. tostring(err or "not available"))
        task.wait(0.8)
        return
    end

    setStarsStatus("Opened: " .. label)
    task.wait(0.65)
end

local function cleanup()
    State.Running = false
    State.AutoTraits = false
    State.AutoStars = false
    if WindowRef and WindowRef.Destroy then
        pcall(function() WindowRef:Destroy() end)
    elseif Fluent and Fluent.Destroy then
        pcall(function() Fluent:Destroy() end)
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

TraitStatus = Tabs.Traits:AddParagraph({Title = "Traits", Content = "Loading units..."})
UnitDropdown = Tabs.Traits:AddDropdown("RE790_Unit", {
    Title = "Unit",
    Values = {},
    Default = nil,
    DropdownOutsideWindow = true,
    Callback = function(value)
        State.SelectedUnitLabel = value
        State.SelectedUnitUUID = UnitMap[value]
        if State.SelectedUnitUUID then
            setTraitStatus("Current: " .. traitSummary(currentTraits(State.SelectedUnitUUID)))
        end
    end,
})
Tabs.Traits:AddButton({
    Title = "Refresh Units",
    Icon = "solar/refresh-bold",
    Callback = function()
        local count = refreshUnits(true)
        setTraitStatus(count > 0 and ("Units found: " .. tostring(count)) or "Waiting for collection data")
    end,
})
Tabs.Traits:AddDropdown("RE790_TraitSource", {
    Title = "Reroll Source",
    Values = {"Tokens", "Star Remnant", "Star Remnant (Limited)"},
    Default = "Tokens",
    DropdownOutsideWindow = true,
    Callback = function(value) State.TraitSource = value or "Tokens" end,
})
Tabs.Traits:AddDropdown("RE790_TraitTargets", {
    Title = "Wanted Traits",
    Values = TraitValues,
    Multi = true,
    Default = {},
    DropdownOutsideWindow = true,
    Callback = function(value) copySelection(State.TraitTargets, value) end,
})
Tabs.Traits:AddToggle("RE790_ProtectDouble", {
    Title = "Stop on Double Trait",
    Default = true,
    Callback = function(value) State.ProtectDouble = value == true end,
})
AutoTraitToggle = Tabs.Traits:AddToggle("RE790_AutoTraits", {
    Title = "Auto Traits",
    Default = false,
    Callback = function(value)
        State.AutoTraits = value == true
        if value then
            setTraitStatus("Auto Traits running")
        end
    end,
})
Tabs.Traits:AddButton({
    Title = "Reroll Once",
    Icon = "solar/refresh-bold",
    Callback = function()
        if not State.ActionBusy then
            State.ActionBusy = true
            task.spawn(function()
                pcall(processTraitOnce)
                State.ActionBusy = false
            end)
        end
    end,
})

StarsStatus = Tabs.Stars:AddParagraph({Title = "Stars", Content = "Select capsules to open"})
Tabs.Stars:AddDropdown("RE790_Capsules", {
    Title = "Capsules",
    Values = CapsuleValues,
    Multi = true,
    Default = {},
    DropdownOutsideWindow = true,
    Callback = function(value) copySelection(State.CapsuleTargets, value) end,
})
AutoStarsToggle = Tabs.Stars:AddToggle("RE790_AutoStars", {
    Title = "Auto Stars (Capsules)",
    Default = false,
    Callback = function(value)
        State.AutoStars = value == true
        if value then
            setStarsStatus("Auto Stars running")
        end
    end,
})
Tabs.Stars:AddButton({
    Title = "Open Once",
    Icon = "solar/refresh-bold",
    Callback = function()
        if not State.ActionBusy then
            State.ActionBusy = true
            task.spawn(function()
                pcall(processStarOnce)
                State.ActionBusy = false
            end)
        end
    end,
})

Tabs.Settings:AddDropdown("RE790_Theme", {
    Title = "Theme",
    Values = Fluent.Themes,
    Default = "Dark",
    DropdownOutsideWindow = true,
    Callback = function(value)
        pcall(function() Fluent:SetTheme(value) end)
    end,
})
Tabs.Settings:AddButton({
    Title = "Unload CAT EMPIRE",
    Icon = "solar/power-bold",
    Callback = cleanup,
})

refreshUnits(true)

task.spawn(function()
    local lastRefresh = 0
    while State.Running do
        local now = os.clock()
        if now - lastRefresh >= 5 then
            lastRefresh = now
            pcall(refreshUnits, false)
        end

        if not State.ActionBusy then
            if State.AutoTraits then
                State.ActionBusy = true
                task.spawn(function()
                    local ok, err = pcall(processTraitOnce)
                    if not ok then
                        setTraitStatus("Trait worker paused")
                        task.wait(1)
                    end
                    State.ActionBusy = false
                end)
            elseif State.AutoStars then
                State.ActionBusy = true
                task.spawn(function()
                    local ok, err = pcall(processStarOnce)
                    if not ok then
                        setStarsStatus("Stars worker paused")
                        task.wait(1)
                    end
                    State.ActionBusy = false
                end)
            end
        end

        task.wait(0.1)
    end
end)

Fluent:Notify({Title = "CAT EMPIRE", Content = "Re Adventures loaded", Duration = 3})
