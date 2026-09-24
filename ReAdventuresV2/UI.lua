local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local UI = {}

local function notify(Fluent, text)
    if Fluent and type(Fluent.Notify) == "function" then
        pcall(function()
            Fluent:Notify({
                Title = "Cat Empire",
                Content = tostring(text),
                Duration = 2,
            })
        end)
    end
end

local function selectedSlots(value, labelToSlot)
    local slots = {}

    if type(value) ~= "table" then
        local slot = labelToSlot[value]
        if slot then
            table.insert(slots, slot)
        end
        return slots
    end

    for key, item in pairs(value) do
        local label
        local enabled = true

        if type(key) == "string" then
            label = key
            enabled = item == true
        elseif type(item) == "string" then
            label = item
        end

        if enabled and label and labelToSlot[label] then
            table.insert(slots, labelToSlot[label])
        end
    end

    table.sort(slots)
    return slots
end

local function unitOptions(app)
    local values = {}
    local map = {}

    local used = {}

    for _, unit in ipairs(app:GetEquippedUnits()) do
        local label

        if unit.locked then
            label = string.format("Slot %d - Locked", unit.slot)
        elseif unit.equipped then
            label = tostring(unit.name or ("Unit " .. tostring(unit.slot)))

            if used[label] then
                label = string.format("%s (Slot %d)", label, unit.slot)
            end
        else
            label = string.format("Slot %d - Empty", unit.slot)
        end

        used[label] = true
        table.insert(values, label)
        map[label] = unit.slot
    end

    return values, map
end

local function markerOptions(app)
    local values = {}
    local map = {}
    local names = {}
    local used = {}

    for _, unit in ipairs(app:GetEquippedUnits()) do
        if unit.equipped and not unit.locked then
            local label = tostring(unit.name or ("Unit " .. tostring(unit.slot)))

            if used[label] then
                label = string.format("%s (Slot %d)", label, unit.slot)
            end

            used[label] = true
            table.insert(values, label)
            map[label] = unit.slot
            names[label] = tostring(unit.name or label)
        end
    end

    if #values == 0 then
        table.insert(values, "No Units")
    end

    return values, map, names
end

local function markerFolder()
    local folder = Workspace:FindFirstChild("RE_PlacementMarkers")

    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "RE_PlacementMarkers"
        folder.Parent = Workspace
    end

    return folder
end

local function drawMarker(slot, cframe, name)
    local folder = markerFolder()
    local old = folder:FindFirstChild("Slot_" .. tostring(slot))

    if old then
        old:Destroy()
    end

    local marker = Instance.new("Model")
    marker.Name = "Slot_" .. tostring(slot)
    marker.Parent = folder

    local ground = CFrame.new(cframe.Position + Vector3.new(0, 0.035, 0))

    local function arm(angle)
        local part = Instance.new("Part")
        part.Name = "X"
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CastShadow = false
        part.Material = Enum.Material.Neon
        part.Size = Vector3.new(1.05, 0.045, 0.105)
        part.Transparency = 0.1
        part.CFrame = ground * CFrame.Angles(0, math.rad(angle), 0)
        part.Parent = marker
        return part
    end

    local anchor = arm(45)
    arm(-45)

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Label"
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.fromOffset(108, 20)
    billboard.StudsOffsetWorldSpace = Vector3.new(1.65, 0.72, 0)
    billboard.Parent = anchor

    local text = Instance.new("TextLabel")
    text.BackgroundTransparency = 1
    text.Size = UDim2.fromScale(1, 1)
    text.Font = Enum.Font.GothamMedium
    text.Text = tostring(name or ("Slot " .. tostring(slot)))
    text.TextSize = 12
    text.TextScaled = false
    text.TextXAlignment = Enum.TextXAlignment.Left
    text.TextStrokeTransparency = 0.55
    text.Parent = billboard

    return marker
end

function UI.AttachAutoStory(Window, app, Fluent)
    local Options = Fluent.Options

    local Tab = Window:AddTab({
        Title = "Auto Story",
        Icon = "play",
    })

    Tab:AddSection("Match")

    local autoReady = Tab:AddToggle("RE_AutoReady", {
        Title = "Auto Ready",
        Default = false,
    })

    autoReady:OnChanged(function(value)
        app:SetAutoStoryConfig({
            autoReady = value,
        })
    end)

    Tab:AddSection("Units")

    local values, labelToSlot = unitOptions(app)

    local autoPlace = Tab:AddToggle("RE_AutoPlaceEnabled", {
        Title = "Auto Place Units",
        Default = false,
    })

    autoPlace:OnChanged(function(value)
        app:SetAutoStoryConfig({
            autoPlace = value,
        })
    end)

    local place = Tab:AddDropdown("RE_AutoPlaceUnits", {
        Title = "Place Units",
        Values = values,
        Multi = true,
        Default = {},
    })

    place:OnChanged(function(value)
        app:SetAutoStoryConfig({
            placeSlots = selectedSlots(value, labelToSlot),
        })
    end)

    local autoUpgrade = Tab:AddToggle("RE_AutoUpgradeEnabled", {
        Title = "Auto Upgrade Units",
        Default = false,
    })

    autoUpgrade:OnChanged(function(value)
        app:SetAutoStoryConfig({
            autoUpgrade = value,
        })
    end)

    local upgrade = Tab:AddDropdown("RE_AutoUpgradeUnits", {
        Title = "Upgrade Units",
        Values = values,
        Multi = true,
        Default = {},
    })

    upgrade:OnChanged(function(value)
        app:SetAutoStoryConfig({
            upgradeSlots = selectedSlots(value, labelToSlot),
        })
    end)

    Tab:AddSection("Placement Marker")

    local markerValues, markerToSlot, markerNames = markerOptions(app)
    local markerDropdown = Tab:AddDropdown("RE_MarkerUnit", {
        Title = "Marker Unit",
        Values = markerValues,
        Default = markerValues[1],
    })

    local markerArmed = false
    local mouse = Players.LocalPlayer and Players.LocalPlayer:GetMouse()

    Tab:AddButton({
        Title = "Place Marker",
        Callback = function()
            local selected = Options.RE_MarkerUnit and Options.RE_MarkerUnit.Value
            local slot = markerToSlot[selected]

            if not slot then
                notify(Fluent, "Select Unit")
                return
            end

            markerArmed = true
            notify(Fluent, "Click Map")
        end,
    })

    Tab:AddButton({
        Title = "Clear Markers",
        Callback = function()
            markerArmed = false
            app:ClearPlacementMarker()

            local folder = Workspace:FindFirstChild("RE_PlacementMarkers")
            if folder then
                folder:Destroy()
            end

            notify(Fluent, "Markers Cleared")
        end,
    })

    if mouse then
        table.insert(app.uiConnections, mouse.Button1Down:Connect(function()
            if not markerArmed then
                return
            end

            markerArmed = false

            local selected = Options.RE_MarkerUnit and Options.RE_MarkerUnit.Value
            local slot = markerToSlot[selected]
            local hit = mouse.Hit

            if not slot or not hit then
                return
            end

            local name = markerNames[selected] or selected
            local ok = app:SetPlacementMarker(slot, hit, name)

            if ok then
                drawMarker(slot, hit, name)
                notify(Fluent, "Marker Saved")
            end
        end))
    end

    Tab:AddSection("After Match")

    local syncingPostMatch = false

    local autoNext = Tab:AddToggle("RE_AutoNext", {
        Title = "Auto Next",
        Default = false,
    })

    local autoReplay = Tab:AddToggle("RE_AutoReplay", {
        Title = "Auto Replay",
        Default = false,
    })

    local autoLobby = Tab:AddToggle("RE_AutoReturnLobby", {
        Title = "Auto Return Lobby",
        Default = false,
    })

    local function setOtherOff(optionName)
        local option = Options[optionName]
        if option and option.Value == true then
            pcall(function()
                option:SetValue(false)
            end)
        end
    end

    autoNext:OnChanged(function(value)
        if syncingPostMatch then
            return
        end

        if value then
            syncingPostMatch = true
            setOtherOff("RE_AutoReplay")
            setOtherOff("RE_AutoReturnLobby")
            syncingPostMatch = false
        end

        app:SetAutoStoryConfig({
            autoNext = value,
        })
    end)

    autoReplay:OnChanged(function(value)
        if syncingPostMatch then
            return
        end

        if value then
            syncingPostMatch = true
            setOtherOff("RE_AutoNext")
            setOtherOff("RE_AutoReturnLobby")
            syncingPostMatch = false
        end

        app:SetAutoStoryConfig({
            autoReplay = value,
        })
    end)

    autoLobby:OnChanged(function(value)
        if syncingPostMatch then
            return
        end

        if value then
            syncingPostMatch = true
            setOtherOff("RE_AutoNext")
            setOtherOff("RE_AutoReplay")
            syncingPostMatch = false
        end

        app:SetAutoStoryConfig({
            autoReturnLobby = value,
        })
    end)

    task.spawn(function()
        local lastUnitsSignature = ""
        local lastMarkersSignature = ""

        while app.running do
            task.wait(5)
            if not app.running then break end

            local latestValues, latestMap = unitOptions(app)
            local latestMarkerValues, latestMarkerToSlot, latestMarkerNames = markerOptions(app)

            local unitsSignature = table.concat(latestValues, "\31")
            local markersSignature = table.concat(latestMarkerValues, "\31")

            values = latestValues
            labelToSlot = latestMap
            markerValues = latestMarkerValues
            markerToSlot = latestMarkerToSlot
            markerNames = latestMarkerNames

            if unitsSignature ~= lastUnitsSignature or markersSignature ~= lastMarkersSignature then
                lastUnitsSignature = unitsSignature
                lastMarkersSignature = markersSignature

                pcall(function()
                    place:SetValues(values)
                    upgrade:SetValues(values)
                    markerDropdown:SetValues(markerValues)
                end)
            end
        end
    end)

    return Tab
end

function UI.AttachChallengers(Window, app, Fluent)
    local config = app:GetChallengerConfig()

    local Tab = Window:AddTab({
        Title = "Challengers",
        Icon = "target",
    })

    Tab:AddSection("Automation")

    local kind = Tab:AddDropdown("RE_ChallengerType", {
        Title = "Challenger Type",
        Values = {"Normal", "Daily"},
        Default = config.kind or "Normal",
    })

    kind:OnChanged(function(value)
        app:SetChallengerConfig({
            kind = value,
        })
    end)

    local enabled = Tab:AddToggle("RE_ChallengerEnabled", {
        Title = "Auto Challengers",
        Default = config.enabled == true,
    })

    enabled:OnChanged(function(value)
        app:SetChallengerConfig({
            enabled = value,
        })

        if value then
            notify(Fluent, "Auto Challengers Enabled")
        end
    end)

    local autoMacro = Tab:AddToggle("RE_ChallengerAutoMacro", {
        Title = "Auto Load Macro by Map",
        Default = config.autoLoadMacro ~= false,
    })

    autoMacro:OnChanged(function(value)
        app:SetChallengerConfig({
            autoLoadMacro = value,
        })
    end)

    local autoReturn = Tab:AddToggle("RE_ChallengerReturnLobby", {
        Title = "Auto Return Lobby",
        Default = config.autoReturnLobby ~= false,
    })

    autoReturn:OnChanged(function(value)
        app:SetChallengerConfig({
            autoReturnLobby = value,
        })
    end)

    Tab:AddButton({
        Title = "Join Challenger Now",
        Callback = function()
            local ok, err = app:RunChallengerStep(true)
            if ok then
                notify(Fluent, "Joining " .. tostring(app:GetChallengerConfig().kind) .. " Challenger")
            else
                notify(Fluent, tostring(err or "Join Failed"))
            end
        end,
    })

    Tab:AddSection("Map Macro")

    Tab:AddButton({
        Title = "Load Macro for Current Map",
        Callback = function()
            local ok, err = app:AutoLoadCurrentMapMacro()
            if ok then
                notify(Fluent, "Map Macro Loaded")
            else
                notify(Fluent, tostring(err or "No matching macro"))
            end
        end,
    })

    table.insert(app.uiDisconnectors, app:On("mapMacroLoaded", function(payload)
        local level = payload and payload.level or "map"
        notify(Fluent, "Loaded macro for " .. tostring(level))
    end))

    table.insert(app.uiDisconnectors, app:On("challengerPortalActivated", function(payload)
        local method = payload and payload.method or "trigger"
        notify(Fluent, "Challenger portal activated via " .. tostring(method))
    end))

    table.insert(app.uiDisconnectors, app:On("reconnectTriggered", function(payload)
        notify(Fluent, "Auto Reconnect: " .. tostring(payload and payload.reason or "disconnect"))
    end))

    return Tab
end

function UI.AttachMacros(Window, app, Fluent)
    local Options = Fluent.Options
    local state = {
        optionToId = {},
        lastExport = nil,
    }

    local Tab = Window:AddTab({
        Title = "Macros",
        Icon = "list",
    })

    Tab:AddSection("Recorder")

    Tab:AddInput("RE_MacroName", {
        Title = "Macro Name",
        Placeholder = "Macro Name",
    })

    Tab:AddButton({
        Title = "Record Macro",
        Callback = function()
            local name = Options.RE_MacroName and Options.RE_MacroName.Value or ""
            local ok, err = app:StartRecording(name ~= "" and name or nil)

            if ok then
                notify(Fluent, "Recording")
            else
                notify(Fluent, err or "Recording Failed")
            end
        end,
    })

    Tab:AddButton({
        Title = "Stop & Save",
        Callback = function()
            local ok = app:StopRecording()

            if ok then
                notify(Fluent, "Saved")
            end
        end,
    })

    Tab:AddSection("Macros")

    local function getValues()
        local values = {}
        state.optionToId = {}

        for _, item in ipairs(app:ListMacros()) do
            local label = tostring(item.name or "Macro")
            local base = label
            local suffix = 2

            while state.optionToId[label] do
                label = base .. " " .. tostring(suffix)
                suffix = suffix + 1
            end

            state.optionToId[label] = item.id
            table.insert(values, label)
        end

        if #values == 0 then
            table.insert(values, "No Macros")
        end

        return values
    end

    local dropdown = Tab:AddDropdown("RE_MacroSelected", {
        Title = "Saved Macros",
        Values = getValues(),
        Default = nil,
    })

    dropdown:OnChanged(function(value)
        local id = state.optionToId[value]
        if id then
            app:SelectMacro(id)
        end
    end)

    local autoPlay = Tab:AddToggle("RE_MacroAutoPlay", {
        Title = "Auto Play Macro",
        Default = false,
    })

    autoPlay:OnChanged(function(value)
        if value then
            local ok, err = app:StartSelectedMacroReplay()

            if not ok then
                notify(Fluent, tostring(err or "Replay Failed"))
                pcall(function()
                    autoPlay:SetValue(false)
                end)
            end
        else
            app:StopMacroReplay()
        end
    end)

    app:On("macroReplayFinished", function(payload)
        if payload.error then notify(Fluent, payload.error) end
        pcall(function()
            autoPlay:SetValue(false)
        end)
    end)

    local function refresh()
        local values = getValues()
        pcall(function()
            dropdown:SetValues(values)
            local selected = app:GetSelectedMacroId()
            for label, id in pairs(state.optionToId) do
                if id == selected then dropdown:SetValue(label); return end
            end
            dropdown:SetValue(nil)
        end)
    end
    table.insert(app.uiDisconnectors, app:On("macrosChanged", refresh))
    refresh()

    Tab:AddButton({
        Title = "Refresh",
        Callback = refresh,
    })

    Tab:AddInput("RE_MacroRename", {
        Title = "Rename",
        Placeholder = "New Name",
    })

    Tab:AddButton({
        Title = "Apply Rename",
        Callback = function()
            local id = app:GetSelectedMacroId()
            local name = Options.RE_MacroRename and Options.RE_MacroRename.Value or ""

            if id and name ~= "" then
                local ok = app:RenameMacro(id, name)
                if ok then
                    refresh()
                    notify(Fluent, "Renamed")
                end
            end
        end,
    })

    Tab:AddButton({
        Title = "Delete Macro",
        Callback = function()
            local id = app:GetSelectedMacroId()
            if id and app:DeleteMacro(id) then
                refresh()
                notify(Fluent, "Deleted")
            end
        end,
    })

    Tab:AddSection("Import / Export")

    Tab:AddInput("RE_MacroImport", {
        Title = "Import Macro",
        Placeholder = "Macro JSON",
    })

    Tab:AddButton({
        Title = "Import",
        Callback = function()
            local json = Options.RE_MacroImport and Options.RE_MacroImport.Value or ""
            if json == "" then
                return
            end

            local ok, err = pcall(function()
                app:ImportMacro(json)
            end)

            if ok then
                refresh()
                notify(Fluent, "Imported")
            else
                notify(Fluent, tostring(err))
            end
        end,
    })

    Tab:AddButton({
        Title = "Export",
        Callback = function()
            local ok, json = pcall(function()
                return app:ExportSelectedMacro()
            end)

            if ok and type(json) == "string" then
                state.lastExport = json
                local env = (getgenv and getgenv()) or _G
                if type(env.setclipboard) == "function" then
                    env.setclipboard(json)
                else
                    print("[Macro]", json)
                end
                notify(Fluent, "Exported")
            end
        end,
    })

    return {
        Tab = Tab,
        Refresh = refresh,
        GetLastExport = function()
            return state.lastExport
        end,
    }
end

function UI.AttachWebhook(Window, app, Fluent)
    local Options = Fluent.Options

    local Tab = Window:AddTab({
        Title = "Webhook",
        Icon = "send",
    })

    Tab:AddSection("Webhook")

    local webhookInput = Tab:AddInput("RE_WebhookURL", {
        Title = "Webhook URL",
        Placeholder = "Webhook URL",
    })

    webhookInput:OnChanged(function(value)
        app:SetWebhookConfig({
            url = tostring(value or ""),
        })
    end)

    local enabled = Tab:AddToggle("RE_WebhookEnabled", {
        Title = "Enable Webhook",
        Default = false,
    })

    enabled:OnChanged(function(value)
        app:SetWebhookConfig({
            enabled = value,
            url = Options.RE_WebhookURL and Options.RE_WebhookURL.Value or "",
        })

        if value then
            notify(Fluent, "Webhook Enabled")
        end
    end)

    return Tab
end

function UI.AttachRuntimeSettings(Tab, app, Fluent)
    if not Tab then return nil end

    local config = app:GetRuntimeConfig()

    Tab:AddSection("Runtime Automation")

    local antiAfk = Tab:AddToggle("RE_AntiAFK", {
        Title = "Anti-AFK",
        Default = config.antiAfk == true,
    })

    antiAfk:OnChanged(function(value)
        app:SetRuntimeConfig({
            antiAfk = value,
        })
    end)

    local reconnect = Tab:AddToggle("RE_AutoReconnect", {
        Title = "Auto Reconnect",
        Default = config.autoReconnect == true,
    })

    reconnect:OnChanged(function(value)
        app:SetRuntimeConfig({
            autoReconnect = value,
        })
    end)

    local execute = Tab:AddToggle("RE_AutoExecute", {
        Title = "Auto Execute Script",
        Default = config.autoExecute == true,
    })

    execute:OnChanged(function(value)
        app:SetRuntimeConfig({
            autoExecute = value,
        })

        if value then
            notify(Fluent, "Auto Execute queued for teleports")
        end
    end)

    return {
        AntiAFK = antiAfk,
        AutoReconnect = reconnect,
        AutoExecute = execute,
    }
end

function UI.Attach(Window, app, Fluent)
    app.uiConnections = app.uiConnections or {}
    app.uiDisconnectors = app.uiDisconnectors or {}
    local lastError, lastErrorTime
    table.insert(app.uiDisconnectors, app:On("actionError", function(payload)
        local message = tostring(payload and payload.message or "")

        -- RemoteFunctions can legitimately reject an action while the game is
        -- transitioning between result/ready states. Keep those internal
        -- retries out of the user-facing notification stream.
        if message:find("Game rejected action:", 1, true) then
            return
        end

        if message ~= lastError or os.clock() - (lastErrorTime or 0) >= 10 then
            lastError, lastErrorTime = message, os.clock()
            notify(Fluent, message)
        end
    end))
    return {
        AutoStory = UI.AttachAutoStory(Window, app, Fluent),
        Challengers = UI.AttachChallengers(Window, app, Fluent),
        Macros = UI.AttachMacros(Window, app, Fluent),
        Webhook = UI.AttachWebhook(Window, app, Fluent),
    }
end

return UI
