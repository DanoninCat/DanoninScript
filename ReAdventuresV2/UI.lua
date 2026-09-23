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

function UI.AttachAutoStory(Window, app, Fluent)
    local Options = Fluent.Options

    local Tab = Window:AddTab({
        Title = "Auto Story",
        Icon = "play",
    })

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
        while true do
            task.wait(2)

            local latestValues, latestMap = unitOptions(app)
            values = latestValues
            labelToSlot = latestMap

            pcall(function()
                place:SetValues(values)
                upgrade:SetValues(values)
            end)
        end
    end)

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
            local ok = app:StartRecording(name ~= "" and name or nil)

            if ok then
                notify(Fluent, "Recording")
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
        Default = "No Macros",
    })

    dropdown:OnChanged(function(value)
        local id = state.optionToId[value]
        if id then
            app:SelectMacro(id)
        end
    end)

    local function refresh()
        local values = getValues()
        pcall(function()
            dropdown:SetValues(values)
        end)
    end

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

            local ok = pcall(function()
                app:ImportMacro(json)
            end)

            if ok then
                refresh()
                notify(Fluent, "Imported")
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
                print("[Macro]", json)
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

function UI.Attach(Window, app, Fluent)
    return {
        AutoStory = UI.AttachAutoStory(Window, app, Fluent),
        Macros = UI.AttachMacros(Window, app, Fluent),
        Webhook = UI.AttachWebhook(Window, app, Fluent),
    }
end

return UI
