-- Source tracked: UntitledDefense105/Main.lua
if game.PlaceId ~= 105596644794991 then
    return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local Env = (getgenv and getgenv()) or _G
local LOADER_COMMAND = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Loader/Loader.lua", true))()]]

if type(Env.__SARTEX_UD105_CLEANUP) == "function" then
    pcall(Env.__SARTEX_UD105_CLEANUP)
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

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local InventoryRequest = Remotes:WaitForChild("InventoryRequest")
local InventoryResult = Remotes:WaitForChild("InventoryResult")
local TraitRerollRequest = Remotes:WaitForChild("TraitRerollRequest")
local TraitRerollResult = Remotes:WaitForChild("TraitRerollResult")
local HalloweenShop = Remotes:WaitForChild("HalloweenShop")
local ItemEvents = ReplicatedStorage:WaitForChild("ItemEvents")

local TraitData = require(ReplicatedStorage:WaitForChild("TraitData"))
local UnitData = require(ReplicatedStorage:WaitForChild("UnitData"))
local ItemData = require(ReplicatedStorage:WaitForChild("ItemData"))
local HalloweenData = require(ReplicatedStorage:WaitForChild("HalloweenData"))

local State = {
    Running = true,

    Units = {},
    Items = {},
    TraitRerollers = 0,
    InventoryLoaded = false,

    AutoTraits = false,
    TraitTargets = {},
    SelectedUnits = {},
    SelectAllUnits = false,
    TraitCompleted = {},
    TraitCursor = 0,
    TraitBusy = false,
    TraitDelay = 0.05,

    AutoStars = false,
    CapsuleTargets = {},
    SelectAllCapsules = false,
    CapsuleCursor = 0,
    StarBusy = false,
    StarDelay = 0.01,
    StarAmount = 100,
    StarMode = "Selected Amount",
    SkipStarAnimations = true,
    StarsOpened = 0,

    AntiAFK = false,
    AutoRejoin = false,
    AutoExecute = false,
    RejoinQueued = false,
}

local WindowRef
local UnitDropdown
local CapsuleDropdown
local TraitStatus
local StarsStatus
local AutoTraitsToggle
local AutoStarsToggle
local RuntimeConnections = {}

local UnitMap = {}
local UnitIdToLabel = {}
local CapsuleMap = {}
local CapsuleValues = {}
local PendingTrait = {}

local function setParagraph(paragraph, title, content)
    if not paragraph then
        return
    end

    if paragraph.SetTitle then
        pcall(function()
            paragraph:SetTitle(title)
        end)
    end

    if paragraph.SetDesc then
        pcall(function()
            paragraph:SetDesc(content or "")
        end)
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

local function connectRuntime(signal, callback)
    if not signal then
        return nil
    end

    local connection = signal:Connect(callback)
    RuntimeConnections[#RuntimeConnections + 1] = connection
    return connection
end

local function traitLabel(trait)
    if type(trait) ~= "table" then
        return "No Trait"
    end

    local ok, description = pcall(TraitData.describe, trait)

    if ok
        and type(description) == "table"
        and type(description.label) == "string"
        and description.label ~= ""
    then
        return description.label
    end

    local name = tostring(trait.name or "Trait")
    local tier = trait.tier

    if tier then
        return name .. " " .. tostring(tier)
    end

    return name
end

local TraitValues = {}
local TraitSeen = {}

do
    local ok, outcomes = pcall(TraitData.outcomes)

    if ok and type(outcomes) == "table" then
        for _, outcome in ipairs(outcomes) do
            local label = traitLabel(outcome)

            if not TraitSeen[label] then
                TraitSeen[label] = true
                TraitValues[#TraitValues + 1] = label
            end
        end
    end

    if #TraitValues == 0
        and type(TraitData.Traits) == "table"
    then
        for _, definition in ipairs(TraitData.Traits) do
            if type(definition) == "table" then
                if type(definition.tiers) == "table" then
                    for _, tier in ipairs(definition.tiers) do
                        local label =
                            tostring(definition.name)
                            .. " "
                            .. tostring(tier.label or tier.tier)

                        if not TraitSeen[label] then
                            TraitSeen[label] = true
                            TraitValues[#TraitValues + 1] = label
                        end
                    end
                elseif definition.name then
                    local label = tostring(definition.name)

                    if not TraitSeen[label] then
                        TraitSeen[label] = true
                        TraitValues[#TraitValues + 1] = label
                    end
                end
            end
        end
    end

    table.sort(TraitValues)
end

local function unitById(id)
    for _, unit in ipairs(State.Units) do
        if type(unit) == "table"
            and tostring(unit.id) == tostring(id)
        then
            return unit
        end
    end

    return nil
end

local function unitDisplayName(unit)
    if type(unit) ~= "table" then
        return "Unit"
    end

    local rawName = tostring(unit.name or "Unit")
    local ok, definition = pcall(UnitData.unitByName, rawName)

    if ok and type(definition) == "table" then
        return tostring(
            definition.displayName
            or definition.display_name
            or definition.name
            or rawName
        )
    end

    return rawName
end

local function selectedUnitIds()
    local out = {}

    for id, enabled in pairs(State.SelectedUnits) do
        if enabled and unitById(id) then
            out[#out + 1] = id
        end
    end

    table.sort(out, function(a, b)
        local ua = unitById(a)
        local ub = unitById(b)
        return unitDisplayName(ua) < unitDisplayName(ub)
    end)

    return out
end

local function rebuildUnitDropdown(preserve)
    local previous = {}

    if preserve ~= false then
        for id, enabled in pairs(State.SelectedUnits) do
            if enabled then
                previous[id] = true
            end
        end
    end

    table.clear(UnitMap)
    table.clear(UnitIdToLabel)

    local labels = {}
    local duplicateCount = {}

    for _, unit in ipairs(State.Units) do
        if type(unit) == "table" and unit.id ~= nil then
            local base =
                unitDisplayName(unit)
                .. " • "
                .. traitLabel(unit.trait)

            duplicateCount[base] =
                (duplicateCount[base] or 0) + 1

            local count = duplicateCount[base]
            local label =
                count == 1
                and base
                or (base .. " (" .. tostring(count) .. ")")

            labels[#labels + 1] = label
            UnitMap[label] = tostring(unit.id)
            UnitIdToLabel[tostring(unit.id)] = label
        end
    end

    table.sort(labels)

    if State.SelectAllUnits then
        table.clear(State.SelectedUnits)

        for _, unit in ipairs(State.Units) do
            if type(unit) == "table" and unit.id ~= nil then
                State.SelectedUnits[tostring(unit.id)] = true
            end
        end
    else
        table.clear(State.SelectedUnits)

        for id in pairs(previous) do
            if UnitIdToLabel[id] then
                State.SelectedUnits[id] = true
            end
        end
    end

    if UnitDropdown and UnitDropdown.SetValues then
        local selectedLabels = {}

        for id in pairs(State.SelectedUnits) do
            local label = UnitIdToLabel[id]

            if label then
                selectedLabels[label] = true
            end
        end

        pcall(function()
            UnitDropdown:SetValues(labels)
            UnitDropdown:SetValue(selectedLabels)
        end)
    end

    return #labels
end

local function capsuleName(id)
    local ok, name = pcall(ItemData.nameOf, id)

    if ok and type(name) == "string" and name ~= "" then
        return name
    end

    if type(HalloweenData.CAPSULE) == "table"
        and tostring(HalloweenData.CAPSULE.id) == tostring(id)
    then
        return tostring(HalloweenData.CAPSULE.name or id)
    end

    return tostring(id)
end

local function rebuildCapsules()
    table.clear(CapsuleMap)
    table.clear(CapsuleValues)

    local found = {}

    local function add(id)
        id = tostring(id or "")

        if id == "" or found[id] then
            return
        end

        local isCapsule = false
        local ok, kind = pcall(ItemData.kindOf, id)

        if ok and kind == "capsule" then
            isCapsule = true
        end

        if type(HalloweenData.CAPSULE) == "table"
            and id == tostring(HalloweenData.CAPSULE.id)
        then
            isCapsule = true
        end

        if not isCapsule then
            return
        end

        found[id] = true

        local label = capsuleName(id)
        local base = label
        local suffix = 2

        while CapsuleMap[label] do
            label = base .. " (" .. tostring(suffix) .. ")"
            suffix = suffix + 1
        end

        CapsuleMap[label] = id
        CapsuleValues[#CapsuleValues + 1] = label
    end

    if type(HalloweenData.CAPSULE) == "table" then
        add(HalloweenData.CAPSULE.id)
    end

    for id in pairs(State.Items) do
        add(id)
    end

    table.sort(CapsuleValues)

    if State.SelectAllCapsules then
        table.clear(State.CapsuleTargets)

        for _, label in ipairs(CapsuleValues) do
            State.CapsuleTargets[label] = true
        end
    else
        for label in pairs(State.CapsuleTargets) do
            if not CapsuleMap[label] then
                State.CapsuleTargets[label] = nil
            end
        end
    end

    if CapsuleDropdown and CapsuleDropdown.SetValues then
        local selected = {}

        for label in pairs(State.CapsuleTargets) do
            if CapsuleMap[label] then
                selected[label] = true
            end
        end

        pcall(function()
            CapsuleDropdown:SetValues(CapsuleValues)
            CapsuleDropdown:SetValue(selected)
        end)
    end
end

local function requestInventory()
    pcall(function()
        InventoryRequest:FireServer(true)
    end)
end

connectRuntime(InventoryResult.OnClientEvent, function(payload)
    if type(payload) ~= "table" then
        return
    end

    if type(payload.units) == "table" then
        State.Units = payload.units
    end

    if type(payload.items) == "table" then
        State.Items = payload.items
    end

    if payload.traitRerollers ~= nil then
        State.TraitRerollers =
            tonumber(payload.traitRerollers) or 0
    end

    State.InventoryLoaded = true

    if not State.AutoTraits then
        rebuildUnitDropdown(true)
    end

    rebuildCapsules()
end)

connectRuntime(TraitRerollResult.OnClientEvent, function(payload)
    if type(payload) ~= "table" then
        return
    end

    if payload.traitRerollers ~= nil then
        State.TraitRerollers =
            tonumber(payload.traitRerollers)
            or State.TraitRerollers
    end

    local id = tostring(payload.id or "")
    local unit = id ~= "" and unitById(id) or nil

    if unit and payload.success and payload.trait ~= nil then
        unit.trait = payload.trait
    end

    local pending = id ~= "" and PendingTrait[id] or nil

    if type(pending) == "table" then
        pending.done = true
        pending.payload = payload
    end
end)

local function waitInventory(timeout)
    if State.InventoryLoaded then
        return true
    end

    requestInventory()

    local deadline = os.clock() + (timeout or 4)

    repeat
        if State.InventoryLoaded then
            return true
        end

        task.wait(0.05)
    until os.clock() >= deadline or not State.Running

    return State.InventoryLoaded
end

local function stopAutoTraits(message)
    State.AutoTraits = false
    State.TraitBusy = false

    if AutoTraitsToggle and AutoTraitsToggle.SetValue then
        pcall(function()
            AutoTraitsToggle:SetValue(false)
        end)
    end

    if message then
        setTraitStatus(message)
    end

    rebuildUnitDropdown(true)
end

local function matchesTraitTarget(unit)
    if type(unit) ~= "table" then
        return false
    end

    if next(State.TraitTargets) == nil then
        return false
    end

    return State.TraitTargets[traitLabel(unit.trait)] == true
end

local function allSelectedTraitsFinished()
    local ids = selectedUnitIds()

    if #ids == 0 then
        return false
    end

    for _, id in ipairs(ids) do
        if not State.TraitCompleted[id] then
            return false
        end
    end

    return true
end

local function nextTraitUnit()
    local ids = selectedUnitIds()

    if #ids == 0 then
        return nil
    end

    for _ = 1, #ids do
        State.TraitCursor =
            (State.TraitCursor % #ids) + 1

        local id = ids[State.TraitCursor]

        if not State.TraitCompleted[id] then
            return unitById(id)
        end
    end

    return nil
end

local function rerollUnit(unit)
    if type(unit) ~= "table" or unit.id == nil then
        return false, "invalid unit"
    end

    if State.TraitRerollers <= 0 then
        return false, "out of rerollers"
    end

    local id = tostring(unit.id)
    local pending = {
        done = false,
        payload = nil,
    }

    PendingTrait[id] = pending

    local ok, err = pcall(function()
        TraitRerollRequest:FireServer({
            id = unit.id,
            confirmMythic = true,
        })
    end)

    if not ok then
        PendingTrait[id] = nil
        return false, tostring(err)
    end

    local deadline = os.clock() + 3.5

    while State.Running
        and not pending.done
        and os.clock() < deadline
    do
        task.wait(0.01)
    end

    PendingTrait[id] = nil

    if not pending.done then
        return false, "reroll timeout"
    end

    local result = pending.payload

    if type(result) ~= "table" then
        return false, "invalid reroll result"
    end

    if not result.success then
        return false, tostring(result.reason or "reroll failed")
    end

    return true, result
end

local function processTraitOnce(manual)
    if not waitInventory(3) then
        setTraitStatus("Inventory unavailable")
        return
    end

    local unit = nextTraitUnit()

    if not unit then
        setTraitStatus("Select at least one character")
        return
    end

    local id = tostring(unit.id)

    if matchesTraitTarget(unit) and not manual then
        State.TraitCompleted[id] = true

        if allSelectedTraitsFinished() then
            stopAutoTraits("Finished selected characters")
        end

        return
    end

    setTraitStatus(
        "Rolling "
        .. unitDisplayName(unit)
        .. " • "
        .. tostring(State.TraitRerollers)
        .. " rerollers"
    )

    local ok, result = rerollUnit(unit)

    if not ok then
        local reason = tostring(result or "reroll failed")

        if reason:lower():find("reroll", 1, true)
            or reason:lower():find("token", 1, true)
        then
            stopAutoTraits("Stopped: " .. reason)
        else
            setTraitStatus(reason)
        end

        task.wait(0.15)
        return
    end

    local current = traitLabel(unit.trait)

    setTraitStatus(
        unitDisplayName(unit)
        .. ": "
        .. current
    )

    if not manual and matchesTraitTarget(unit) then
        State.TraitCompleted[id] = true

        if allSelectedTraitsFinished() then
            stopAutoTraits("Finished selected characters")
            return
        end
    end

    task.wait(math.max(0.01, State.TraitDelay))
end

local function rerollSelectedOnce()
    if not waitInventory(3) then
        setTraitStatus("Inventory unavailable")
        return
    end

    local ids = selectedUnitIds()

    if #ids == 0 then
        setTraitStatus("Select at least one character")
        return
    end

    for _, id in ipairs(ids) do
        if not State.Running then
            break
        end

        local unit = unitById(id)

        if unit then
            setTraitStatus("Rolling " .. unitDisplayName(unit))

            local ok, reason = rerollUnit(unit)

            if not ok then
                setTraitStatus(tostring(reason))
                break
            end

            setTraitStatus(
                unitDisplayName(unit)
                .. ": "
                .. traitLabel(unit.trait)
            )

            task.wait(math.max(0.01, State.TraitDelay))
        end
    end

    rebuildUnitDropdown(true)
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

local function ownedCapsuleCount(itemId)
    return math.max(
        0,
        math.floor(
            tonumber(State.Items[itemId]) or 0
        )
    )
end

local function directOpenCapsule(itemId, amount)
    amount = math.max(
        1,
        math.floor(tonumber(amount) or 1)
    )

    local ok, result = pcall(function()
        return HalloweenShop:InvokeServer(
            "open",
            itemId,
            amount
        )
    end)

    if not ok then
        return false, tostring(result)
    end

    if type(result) ~= "table" then
        return false, "invalid capsule result"
    end

    if not result.success then
        return false, tostring(result.reason or "open failed")
    end

    if result.remaining ~= nil then
        State.Items[itemId] =
            math.max(
                0,
                math.floor(
                    tonumber(result.remaining) or 0
                )
            )
    else
        State.Items[itemId] =
            math.max(
                0,
                ownedCapsuleCount(itemId) - amount
            )
    end

    return true, result
end

local function nativeAnimatedOpen(itemId, amount)
    local before = ownedCapsuleCount(itemId)

    local ok, err = pcall(function()
        ItemEvents.OpenCapsule:Fire({
            id = itemId,
            amount = amount,
        })
    end)

    if not ok then
        return false, tostring(err)
    end

    local deadline = os.clock() + 8

    repeat
        task.wait(0.1)
        requestInventory()
        task.wait(0.05)

        if ownedCapsuleCount(itemId) < before then
            return true
        end
    until os.clock() >= deadline or not State.Running

    return false, "opening timeout"
end

local function openCapsuleChunk(itemId, amount)
    if State.SkipStarAnimations then
        return directOpenCapsule(itemId, amount)
    end

    return nativeAnimatedOpen(itemId, amount)
end

local function openCapsuleAmount(itemId, requested)
    local owned = ownedCapsuleCount(itemId)

    if owned <= 0 then
        return false, "no capsules", 0
    end

    local target

    if requested == "ALL" then
        target = owned
    else
        target = math.min(
            owned,
            math.max(
                1,
                math.floor(
                    tonumber(requested) or 1
                )
            )
        )
    end

    local remaining = target
    local opened = 0

    while remaining > 0 and State.Running do
        -- The native OpenAll implementation in this place caps one
        -- server request at 100, so use the same supported chunk size.
        local chunk = math.min(remaining, 100)

        local ok, result =
            openCapsuleChunk(itemId, chunk)

        if not ok then
            return false, result, opened
        end

        opened = opened + chunk
        remaining = remaining - chunk
        State.StarsOpened = State.StarsOpened + chunk

        if remaining > 0 then
            task.wait(math.max(0.01, State.StarDelay))
        end
    end

    return true, nil, opened
end

local function processStarOnce(manual)
    if not waitInventory(3) then
        setStarsStatus("Inventory unavailable")
        return
    end

    rebuildCapsules()

    local selected = selectedCapsuleLabels()

    if #selected == 0 then
        setStarsStatus("Select at least one capsule")
        return
    end

    State.CapsuleCursor =
        (State.CapsuleCursor % #selected) + 1

    local label = selected[State.CapsuleCursor]
    local itemId = CapsuleMap[label]
    local amount =
        State.StarMode == "ALL Owned"
        and "ALL"
        or State.StarAmount

    local owned = ownedCapsuleCount(itemId)

    if owned <= 0 then
        setStarsStatus(label .. ": none owned")

        if State.AutoStars then
            local anyOwned = false

            for _, otherLabel in ipairs(selected) do
                local otherId = CapsuleMap[otherLabel]

                if otherId
                    and ownedCapsuleCount(otherId) > 0
                then
                    anyOwned = true
                    break
                end
            end

            if not anyOwned then
                State.AutoStars = false

                if AutoStarsToggle
                    and AutoStarsToggle.SetValue
                then
                    pcall(function()
                        AutoStarsToggle:SetValue(false)
                    end)
                end

                setStarsStatus("Finished selected capsules")
            end
        end

        task.wait(0.05)
        return
    end

    setStarsStatus(
        "Opening "
        .. label
        .. " • owned "
        .. tostring(owned)
    )

    local ok, reason, opened =
        openCapsuleAmount(itemId, amount)

    if not ok then
        setStarsStatus(
            label
            .. ": "
            .. tostring(reason or "open failed")
        )
        task.wait(0.15)
        return
    end

    setStarsStatus(
        string.format(
            "%s • opened %d • remaining %d",
            label,
            opened,
            ownedCapsuleCount(itemId)
        )
    )

    if manual then
        requestInventory()
    end

    task.wait(math.max(0.01, State.StarDelay))
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
    local queueFn =
        executorFunction(
            "queue_on_teleport",
            "queueonteleport"
        )

    if type(queueFn) ~= "function" then
        return false
    end

    return pcall(queueFn, LOADER_COMMAND)
end

local function requestReconnect()
    if not State.AutoRejoin
        or State.RejoinQueued
    then
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

        local lower =
            tostring(message or ""):lower()

        if lower:find("disconnect", 1, true)
            or lower:find("connection", 1, true)
            or lower:find("desconect", 1, true)
            or lower:find("conex", 1, true)
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
    local promptGui =
        CoreGui:FindFirstChild("RobloxPromptGui")

    promptOverlay =
        promptGui
        and promptGui:FindFirstChild("promptOverlay")
end)

if promptOverlay then
    connectRuntime(promptOverlay.ChildAdded, function(child)
        task.delay(0.1, function()
            if not State.AutoRejoin then
                return
            end

            local name =
                tostring(
                    child and child.Name or ""
                ):lower()

            if name:find("errorprompt", 1, true) then
                requestReconnect()
            end
        end)
    end)
end

local function cleanup()
    State.Running = false
    State.AutoTraits = false
    State.AutoStars = false

    for _, connection in ipairs(RuntimeConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(RuntimeConnections)
    table.clear(PendingTrait)

    if WindowRef and WindowRef.Destroy then
        pcall(function()
            WindowRef:Destroy()
        end)
    elseif Fluent and Fluent.Destroy then
        pcall(function()
            Fluent:Destroy()
        end)
    end

    Env.__SARTEX_UD105_CLEANUP = nil
end

Env.__SARTEX_UD105_CLEANUP = cleanup

local Window = Fluent:CreateWindow({
    Title = "SARTEX INTERNAL",
    SubTitle = "Untitled Defense",
    TabWidth = 150,
    Size = UDim2.fromOffset(760, 470),
    Acrylic = true,
    Animated = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
    ScreenGuiName = "SARTEX_INTERNAL_UNTITLED_DEFENSE_105",
})

WindowRef = Window

local Tabs = {
    Traits = Window:AddTab({
        Title = "Traits",
        Icon = "solar/stars-bold",
    }),
    Stars = Window:AddTab({
        Title = "Stars",
        Icon = "solar/widget-4-bold",
    }),
    Settings = Window:AddTab({
        Title = "Settings",
        Icon = "solar/settings-bold",
    }),
}

TraitStatus = Tabs.Traits:AddParagraph({
    Title = "Traits",
    Content = "Loading inventory...",
})

UnitDropdown = Tabs.Traits:AddDropdown(
    "UD105_Units",
    {
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

                    local id =
                        enabled
                        and label
                        and UnitMap[label]
                        or nil

                    if id then
                        State.SelectedUnits[id] = true
                    end
                end
            elseif type(value) == "string"
                and UnitMap[value]
            then
                State.SelectedUnits[
                    UnitMap[value]
                ] = true
            end

            setTraitStatus(
                string.format(
                    "%d selected • %d rerollers",
                    #selectedUnitIds(),
                    State.TraitRerollers
                )
            )
        end,
    }
)

Tabs.Traits:AddToggle(
    "UD105_SelectAllUnits",
    {
        Title = "Select All Characters",
        Default = false,
        Callback = function(value)
            State.SelectAllUnits = value == true
            State.TraitCompleted = {}

            if State.SelectAllUnits then
                table.clear(State.SelectedUnits)

                for _, unit in ipairs(State.Units) do
                    if type(unit) == "table"
                        and unit.id ~= nil
                    then
                        State.SelectedUnits[
                            tostring(unit.id)
                        ] = true
                    end
                end
            else
                table.clear(State.SelectedUnits)
            end

            rebuildUnitDropdown(true)

            setTraitStatus(
                State.SelectAllUnits
                    and string.format(
                        "%d characters selected",
                        #selectedUnitIds()
                    )
                    or "Select characters"
            )
        end,
    }
)

Tabs.Traits:AddButton({
    Title = "Refresh Characters",
    Icon = "solar/refresh-bold",
    Callback = function()
        requestInventory()
        task.delay(0.15, function()
            if State.Running then
                local count =
                    rebuildUnitDropdown(true)

                setTraitStatus(
                    string.format(
                        "%d characters • %d rerollers",
                        count,
                        State.TraitRerollers
                    )
                )
            end
        end)
    end,
})

if type(Tabs.Traits.AddSlider) == "function" then
    Tabs.Traits:AddSlider(
        "UD105_TraitDelay",
        {
            Title = "Time Between Trait Rerolls",
            Default = 0.05,
            Min = 0.01,
            Max = 2,
            Rounding = 3,
            Callback = function(value)
                State.TraitDelay =
                    math.max(
                        0.01,
                        tonumber(value) or 0.05
                    )
            end,
        }
    )
else
    Tabs.Traits:AddInput(
        "UD105_TraitDelay",
        {
            Title = "Time Between Trait Rerolls",
            Default = "0.05",
            Placeholder = "0.05",
            Numeric = true,
            Callback = function(value)
                State.TraitDelay =
                    math.max(
                        0.01,
                        tonumber(value) or 0.05
                    )
            end,
        }
    )
end

Tabs.Traits:AddDropdown(
    "UD105_TraitTargets",
    {
        Title = "Wanted Traits",
        Values = TraitValues,
        Multi = true,
        Default = {},
        DropdownOutsideWindow = true,
        Callback = function(value)
            copySelection(
                State.TraitTargets,
                value
            )
            State.TraitCompleted = {}
        end,
    }
)

AutoTraitsToggle = Tabs.Traits:AddToggle(
    "UD105_AutoTraits",
    {
        Title = "Auto Traits",
        Default = false,
        Callback = function(value)
            State.AutoTraits = value == true

            if value then
                State.TraitCompleted = {}
                State.TraitCursor = 0
                setTraitStatus(
                    "Auto Traits running"
                )
            end
        end,
    }
)

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
    Content = "Direct server opening available; animations can be completely bypassed",
})

CapsuleDropdown = Tabs.Stars:AddDropdown(
    "UD105_Capsules",
    {
        Title = "Capsules",
        Values = {},
        Multi = true,
        Default = {},
        DropdownOutsideWindow = true,
        Callback = function(value)
            copySelection(
                State.CapsuleTargets,
                value
            )
        end,
    }
)

Tabs.Stars:AddToggle(
    "UD105_SelectAllCapsules",
    {
        Title = "Select All Capsules",
        Default = false,
        Callback = function(value)
            State.SelectAllCapsules =
                value == true

            table.clear(
                State.CapsuleTargets
            )

            local selected = {}

            if State.SelectAllCapsules then
                for _, label in ipairs(
                    CapsuleValues
                ) do
                    State.CapsuleTargets[
                        label
                    ] = true
                    selected[label] = true
                end
            end

            if CapsuleDropdown
                and CapsuleDropdown.SetValue
            then
                pcall(function()
                    CapsuleDropdown:SetValue(
                        selected
                    )
                end)
            end

            setStarsStatus(
                State.SelectAllCapsules
                    and string.format(
                        "%d capsules selected",
                        #CapsuleValues
                    )
                    or "Select capsules"
            )
        end,
    }
)

Tabs.Stars:AddDropdown(
    "UD105_StarMode",
    {
        Title = "Opening Mode",
        Values = {
            "Selected Amount",
            "ALL Owned",
        },
        Default = "Selected Amount",
        DropdownOutsideWindow = true,
        Callback = function(value)
            State.StarMode =
                value or "Selected Amount"
        end,
    }
)

Tabs.Stars:AddInput(
    "UD105_StarAmount",
    {
        Title = "Open Amount",
        Default = "100",
        Placeholder = "100",
        Numeric = true,
        Callback = function(value)
            State.StarAmount =
                math.max(
                    1,
                    math.floor(
                        tonumber(value) or 100
                    )
                )
        end,
    }
)

if type(Tabs.Stars.AddSlider) == "function" then
    Tabs.Stars:AddSlider(
        "UD105_StarDelay",
        {
            Title = "Time Between Opening Batches",
            Default = 0.01,
            Min = 0.01,
            Max = 3,
            Rounding = 3,
            Callback = function(value)
                State.StarDelay =
                    math.max(
                        0.01,
                        tonumber(value) or 0.01
                    )
            end,
        }
    )
else
    Tabs.Stars:AddInput(
        "UD105_StarDelay",
        {
            Title = "Time Between Opening Batches",
            Default = "0.01",
            Placeholder = "0.01",
            Numeric = true,
            Callback = function(value)
                State.StarDelay =
                    math.max(
                        0.01,
                        tonumber(value) or 0.01
                    )
            end,
        }
    )
end

Tabs.Stars:AddToggle(
    "UD105_SkipAnimations",
    {
        Title = "Block Opening Animations",
        Default = true,
        Callback = function(value)
            State.SkipStarAnimations =
                value == true

            setStarsStatus(
                State.SkipStarAnimations
                    and "Animations fully bypassed"
                    or "Native animations enabled"
            )
        end,
    }
)

AutoStarsToggle = Tabs.Stars:AddToggle(
    "UD105_AutoStars",
    {
        Title = "Auto Stars",
        Default = false,
        Callback = function(value)
            State.AutoStars = value == true

            if value then
                State.StarsOpened = 0
                State.CapsuleCursor = 0
                setStarsStatus(
                    State.StarMode
                    == "ALL Owned"
                        and "Opening ALL owned capsules"
                        or (
                            "Opening "
                            .. tostring(
                                State.StarAmount
                            )
                            .. " per cycle"
                        )
                )
            end
        end,
    }
)

Tabs.Stars:AddButton({
    Title = "Open Now",
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

Tabs.Settings:AddToggle(
    "UD105_AntiAFK",
    {
        Title = "Anti AFK",
        Default = false,
        Callback = function(value)
            State.AntiAFK =
                value == true
        end,
    }
)

Tabs.Settings:AddToggle(
    "UD105_AutoRejoin",
    {
        Title = "Auto Rejoin",
        Default = false,
        Callback = function(value)
            State.AutoRejoin =
                value == true

            if not value then
                State.RejoinQueued = false
            end
        end,
    }
)

Tabs.Settings:AddToggle(
    "UD105_AutoExecute",
    {
        Title = "Auto Load After Rejoin",
        Default = false,
        Callback = function(value)
            State.AutoExecute =
                value == true

            if value then
                pcall(queueLoader)
            end
        end,
    }
)

Tabs.Settings:AddSection("Interface")

Tabs.Settings:AddDropdown(
    "UD105_Theme",
    {
        Title = "Theme",
        Values = Fluent.Themes,
        Default = "Dark",
        DropdownOutsideWindow = true,
        Callback = function(value)
            pcall(function()
                Fluent:SetTheme(value)
            end)
        end,
    }
)

Tabs.Settings:AddButton({
    Title = "Unload SARTEX INTERNAL",
    Icon = "solar/power-bold",
    Callback = cleanup,
})

requestInventory()

task.delay(0.25, function()
    if not State.Running then
        return
    end

    rebuildUnitDropdown(true)
    rebuildCapsules()

    setTraitStatus(
        string.format(
            "%d characters • %d rerollers",
            #State.Units,
            State.TraitRerollers
        )
    )

    setStarsStatus(
        #CapsuleValues > 0
            and (
                tostring(#CapsuleValues)
                .. " capsule type(s) found"
            )
            or "Waiting for capsule inventory"
    )
end)

task.spawn(function()
    while State.Running do
        if State.AutoTraits
            and not State.TraitBusy
        then
            State.TraitBusy = true

            local ok = pcall(
                processTraitOnce,
                false
            )

            if not ok then
                setTraitStatus(
                    "Auto Traits paused briefly"
                )
                task.wait(0.2)
            end

            State.TraitBusy = false
        end

        task.wait(0.01)
    end
end)

task.spawn(function()
    while State.Running do
        if State.AutoStars
            and not State.StarBusy
        then
            State.StarBusy = true

            local ok = pcall(
                processStarOnce,
                false
            )

            if not ok then
                setStarsStatus(
                    "Auto Stars paused briefly"
                )
                task.wait(0.2)
            end

            State.StarBusy = false
        end

        task.wait(0.01)
    end
end)
