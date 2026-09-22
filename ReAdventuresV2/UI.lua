-- Re Adventures V2 - Existing UI integration
-- Creates a dedicated "Macros" area INSIDE an existing window/tab system.
-- It never creates a ScreenGui or a second window.

local UI = {}

local function tryCall(object, methodNames, ...)
    if not object then
        return false, nil
    end

    local args = { ... }

    for _, methodName in ipairs(methodNames) do
        local method = object[methodName]

        if type(method) == "function" then
            local ok, result = pcall(function()
                return method(object, table.unpack(args))
            end)

            if ok then
                return true, result
            end
        end
    end

    return false, nil
end

local function createTab(window, name)
    local ok, tab

    ok, tab = tryCall(window, {
        "CreateTab",
        "AddTab",
        "NewTab",
        "Tab",
    }, name)

    if ok and tab then
        return tab
    end

    ok, tab = tryCall(window, {
        "CreateTab",
        "AddTab",
        "NewTab",
        "Tab",
    }, {
        Name = name,
        Title = name,
        Icon = "list",
    })

    if ok and tab then
        return tab
    end

    error("[ReAdventuresV2] Existing UI does not expose a compatible tab creation method.")
end

local function createSection(parent, name)
    local ok, section

    ok, section = tryCall(parent, {
        "CreateSection",
        "AddSection",
        "NewSection",
        "Section",
    }, name)

    if ok and section then
        return section
    end

    ok, section = tryCall(parent, {
        "CreateSection",
        "AddSection",
        "NewSection",
        "Section",
    }, {
        Name = name,
        Title = name,
    })

    if ok and section then
        return section
    end

    -- Some UI libraries put controls directly on the tab.
    return parent
end

local function createButton(parent, label, callback)
    local ok, control

    ok, control = tryCall(parent, {
        "CreateButton",
        "AddButton",
        "Button",
    }, {
        Name = label,
        Title = label,
        Callback = callback,
    })

    if ok then
        return control
    end

    ok, control = tryCall(parent, {
        "CreateButton",
        "AddButton",
        "Button",
    }, label, callback)

    if ok then
        return control
    end

    error("[ReAdventuresV2] Existing UI does not expose a compatible button method.")
end

local function createInput(parent, label, placeholder, callback)
    local ok, control

    ok, control = tryCall(parent, {
        "CreateInput",
        "AddInput",
        "Input",
        "CreateTextbox",
        "AddTextbox",
        "Textbox",
    }, {
        Name = label,
        Title = label,
        PlaceholderText = placeholder or "",
        Placeholder = placeholder or "",
        Default = "",
        RemoveTextAfterFocusLost = false,
        Callback = callback,
    })

    if ok then
        return control
    end

    ok, control = tryCall(parent, {
        "CreateInput",
        "AddInput",
        "Input",
        "CreateTextbox",
        "AddTextbox",
        "Textbox",
    }, label, "", callback)

    if ok then
        return control
    end

    return nil
end

local function createDropdown(parent, label, options, callback)
    local ok, control

    ok, control = tryCall(parent, {
        "CreateDropdown",
        "AddDropdown",
        "Dropdown",
    }, {
        Name = label,
        Title = label,
        Options = options,
        Values = options,
        CurrentOption = options[1],
        Default = options[1],
        MultipleOptions = false,
        Multi = false,
        Callback = callback,
    })

    if ok then
        return control
    end

    ok, control = tryCall(parent, {
        "CreateDropdown",
        "AddDropdown",
        "Dropdown",
    }, label, options, callback)

    if ok then
        return control
    end

    return nil
end

local function createText(parent, title, content)
    local ok, control

    ok, control = tryCall(parent, {
        "CreateParagraph",
        "AddParagraph",
        "Paragraph",
    }, {
        Title = title,
        Content = content,
        Text = content,
    })

    if ok then
        return control
    end

    ok, control = tryCall(parent, {
        "CreateLabel",
        "AddLabel",
        "Label",
    }, title .. ": " .. tostring(content))

    if ok then
        return control
    end

    return nil
end

local function setText(control, title, content)
    if not control then
        return false
    end

    local candidates = {
        function()
            return control:Set({
                Title = title,
                Content = content,
                Text = content,
            })
        end,
        function()
            return control:SetText(content)
        end,
        function()
            return control:Update(content)
        end,
        function()
            return control:Refresh(content)
        end,
    }

    for _, fn in ipairs(candidates) do
        local ok = pcall(fn)
        if ok then
            return true
        end
    end

    return false
end

local function refreshDropdown(control, options)
    if not control then
        return false
    end

    local candidates = {
        function()
            return control:Refresh(options, true)
        end,
        function()
            return control:SetValues(options)
        end,
        function()
            return control:SetOptions(options)
        end,
        function()
            return control:Update(options)
        end,
    }

    for _, fn in ipairs(candidates) do
        local ok = pcall(fn)
        if ok then
            return true
        end
    end

    return false
end

local function normalizeDropdownValue(value)
    if type(value) == "table" then
        return value[1] or value.Value or value.value or value.Name or value.name
    end

    return value
end

local function displayName(item)
    local map = item.area or "unknown"
    local level = item.level or "unknown"
    return string.format("%s | %s | %s", item.name or "Macro", map, level)
end

function UI.AttachMacrosArea(window, app)
    assert(window ~= nil, "existing UI window is required")
    assert(app ~= nil, "Re Adventures V2 controller is required")

    local state = {
        macroName = "",
        renameText = "",
        importText = "",
        lastExport = nil,
        selectedId = nil,
        optionToId = {},
    }

    local macrosTab = createTab(window, "Macros")

    -- MACRO RECORDER
    local recorderSection = createSection(macrosTab, "Macro Recorder")

    createInput(recorderSection, "Macro Name", "Example: Namek Story", function(value)
        state.macroName = tostring(value or "")
    end)

    local statusControl = createText(recorderSection, "Recorder Status", "Stopped")

    createButton(recorderSection, "Record Macro", function()
        local name = state.macroName

        if name == "" then
            name = nil
        end

        local ok, result = app:StartRecording(name)

        if ok then
            setText(statusControl, "Recorder Status", "Recording")
        else
            setText(statusControl, "Recorder Status", "Could not start: " .. tostring(result))
        end
    end)

    createButton(recorderSection, "Stop & Save", function()
        local ok, macro, id = app:StopRecording()

        if ok and macro then
            state.selectedId = id
            setText(statusControl, "Recorder Status", "Saved: " .. tostring(macro.name))
        else
            setText(statusControl, "Recorder Status", "Stopped")
        end
    end)

    -- MACRO LIBRARY
    local librarySection = createSection(macrosTab, "Macro Library")

    local function buildOptions()
        local items = app:ListMacros()
        local options = {}
        state.optionToId = {}

        for _, item in ipairs(items) do
            local text = displayName(item)
            table.insert(options, text)
            state.optionToId[text] = item.id
        end

        if #options == 0 then
            table.insert(options, "No macros saved")
        end

        return options
    end

    local dropdown
    dropdown = createDropdown(librarySection, "Saved Macros", buildOptions(), function(value)
        local selected = normalizeDropdownValue(value)
        local id = state.optionToId[selected]

        if id then
            local ok = app:SelectMacro(id)
            if ok then
                state.selectedId = id
            end
        end
    end)

    local function refreshLibrary()
        local options = buildOptions()
        refreshDropdown(dropdown, options)

        local selected = app:GetSelectedMacroId()
        state.selectedId = selected
    end

    createButton(librarySection, "Refresh Macro List", refreshLibrary)

    createInput(librarySection, "Rename Selected", "New macro name", function(value)
        state.renameText = tostring(value or "")
    end)

    createButton(librarySection, "Apply Rename", function()
        local id = app:GetSelectedMacroId() or state.selectedId

        if id and state.renameText ~= "" then
            app:RenameMacro(id, state.renameText)
            refreshLibrary()
        end
    end)

    createButton(librarySection, "Delete Selected Macro", function()
        local id = app:GetSelectedMacroId() or state.selectedId

        if id then
            app:DeleteMacro(id)
            state.selectedId = nil
            refreshLibrary()
        end
    end)

    -- IMPORT / EXPORT
    local ioSection = createSection(macrosTab, "Import / Export")

    createInput(ioSection, "Import Macro JSON", "Paste macro JSON", function(value)
        state.importText = tostring(value or "")
    end)

    local ioStatus = createText(ioSection, "Import / Export Status", "Idle")

    createButton(ioSection, "Import Macro", function()
        if state.importText == "" then
            setText(ioStatus, "Import / Export Status", "No JSON provided")
            return
        end

        local ok, macro, id = pcall(function()
            local imported, importedId = app:ImportMacro(state.importText)
            return imported, importedId
        end)

        if ok and macro then
            state.selectedId = id
            setText(ioStatus, "Import / Export Status", "Imported: " .. tostring(macro.name))
            refreshLibrary()
        else
            setText(ioStatus, "Import / Export Status", "Import failed")
        end
    end)

    createButton(ioSection, "Export Selected Macro", function()
        local ok, result = pcall(function()
            return app:ExportSelectedMacro()
        end)

        if ok then
            state.lastExport = result
            setText(ioStatus, "Import / Export Status", "Export ready (" .. tostring(#result) .. " bytes)")
            print("[ReAdventuresV2][MacroExport]", result)
        else
            setText(ioStatus, "Import / Export Status", "Export failed")
        end
    end)

    -- STATUS / INFO
    local infoSection = createSection(macrosTab, "Macro Status")
    local infoControl = createText(infoSection, "Selected Macro", "None")

    local function updateInfo()
        local summary = app:GetMacrosSummary()
        local selected = app:GetSelectedMacro()

        if selected then
            local eventCount = type(selected.events) == "table" and #selected.events or 0
            local snapshotCount = type(selected.snapshots) == "table" and #selected.snapshots or 0
            local area = selected.map and selected.map.area or "unknown"
            local level = selected.map and selected.map.level or "unknown"

            local content = string.format(
                "%s | %s / %s | Events: %d | Snapshots: %d",
                tostring(selected.name),
                tostring(area),
                tostring(level),
                eventCount,
                snapshotCount
            )

            setText(infoControl, "Selected Macro", content)
        else
            setText(
                infoControl,
                "Selected Macro",
                "None | Saved: " .. tostring(summary.count)
            )
        end
    end

    createButton(infoSection, "Refresh Macro Info", updateInfo)

    -- Public handle for the Loader integration.
    local handle = {
        Tab = macrosTab,
        State = state,
        Refresh = function()
            refreshLibrary()
            updateInfo()
        end,
        GetLastExport = function()
            return state.lastExport
        end,
    }

    handle.Refresh()
    return handle
end

return UI
