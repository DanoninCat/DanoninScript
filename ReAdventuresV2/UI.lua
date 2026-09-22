-- Re Adventures V2 - Fluent UI integration
-- Adds a dedicated "Macros" tab to the SAME Fluent window used by Re Adventures.
-- Does not create a second ScreenGui or second window.

local UI = {}

local function setParagraph(paragraph, text)
    if not paragraph then
        return
    end

    pcall(function()
        paragraph:SetDesc(tostring(text))
    end)
end

local function safeNotify(Fluent, title, content, duration)
    if not Fluent or type(Fluent.Notify) ~= "function" then
        return
    end

    pcall(function()
        Fluent:Notify({
            Title = title,
            Content = content,
            Duration = duration or 3,
        })
    end)
end

local function displayName(item)
    return string.format(
        "%s | %s | %s",
        tostring(item.name or "Macro"),
        tostring(item.area or "unknown"),
        tostring(item.level or "unknown")
    )
end

function UI.AttachMacrosArea(Window, app, Fluent)
    assert(Window ~= nil, "existing Fluent window is required")
    assert(app ~= nil, "Re Adventures V2 controller is required")
    assert(Fluent ~= nil, "Fluent instance is required")

    local Options = Fluent.Options
    local state = {
        selectedId = nil,
        optionToId = {},
        lastExport = nil,
    }

    local Tab = Window:AddTab({
        Title = "Macros",
        Icon = "list",
    })

    -- =========================================================
    -- MACRO RECORDER
    -- =========================================================
    Tab:AddSection("Macro Recorder")

    Tab:AddInput("RE_MacroName", {
        Title = "Macro Name",
        Placeholder = "Ex: Namek Story",
    })

    local recorderStatus = Tab:AddParagraph({
        Title = "Recorder Status",
        Content = "Stopped",
    })

    Tab:AddButton({
        Title = "Record Macro",
        Callback = function()
            local name = Options.RE_MacroName and Options.RE_MacroName.Value or ""
            if name == "" then
                name = nil
            end

            local ok, result = app:StartRecording(name)

            if ok then
                setParagraph(recorderStatus, "Recording...")
                safeNotify(Fluent, "Macros", "Recording started.", 2)
            else
                setParagraph(recorderStatus, "Could not start: " .. tostring(result))
                safeNotify(Fluent, "Macros", "Could not start recording.", 3)
            end
        end,
    })

    Tab:AddButton({
        Title = "Stop & Save Macro",
        Callback = function()
            local ok, macro, id = app:StopRecording()

            if ok and macro then
                state.selectedId = id
                setParagraph(
                    recorderStatus,
                    string.format(
                        "Saved: %s | %.2fs | %d events",
                        tostring(macro.name),
                        tonumber(macro.duration) or 0,
                        type(macro.events) == "table" and #macro.events or 0
                    )
                )
                safeNotify(Fluent, "Macros", "Macro saved: " .. tostring(macro.name), 3)
            else
                setParagraph(recorderStatus, "Stopped")
            end
        end,
    })

    -- =========================================================
    -- MACRO LIBRARY
    -- =========================================================
    Tab:AddSection("Macro Library")

    local macroDropdown = Tab:AddDropdown("RE_MacroSelected", {
        Title = "Saved Macros",
        Values = { "No macros saved" },
        Default = "No macros saved",
    })

    local macroInfo = Tab:AddParagraph({
        Title = "Selected Macro",
        Content = "None",
    })

    local function buildMacroOptions()
        local items = app:ListMacros()
        local values = {}
        state.optionToId = {}

        for _, item in ipairs(items) do
            local label = displayName(item)
            table.insert(values, label)
            state.optionToId[label] = item.id
        end

        if #values == 0 then
            table.insert(values, "No macros saved")
        end

        return values
    end

    local function updateMacroInfo()
        local macro = app:GetSelectedMacro()

        if not macro then
            setParagraph(macroInfo, "None")
            return
        end

        local eventCount = type(macro.events) == "table" and #macro.events or 0
        local snapshotCount = type(macro.snapshots) == "table" and #macro.snapshots or 0

        setParagraph(
            macroInfo,
            string.format(
                "%s\nMap: %s / %s\nDuration: %.2fs\nEvents: %d | Snapshots: %d",
                tostring(macro.name),
                tostring(macro.map and macro.map.area or "unknown"),
                tostring(macro.map and macro.map.level or "unknown"),
                tonumber(macro.duration) or 0,
                eventCount,
                snapshotCount
            )
        )
    end

    local function refreshLibrary()
        local values = buildMacroOptions()

        pcall(function()
            macroDropdown:SetValues(values)
        end)

        if values[1] ~= "No macros saved" then
            local selectedId = app:GetSelectedMacroId()
            local selectedLabel

            for label, id in pairs(state.optionToId) do
                if id == selectedId then
                    selectedLabel = label
                    break
                end
            end

            if selectedLabel then
                pcall(function()
                    macroDropdown:SetValue(selectedLabel)
                end)
            end
        end

        updateMacroInfo()
    end

    macroDropdown:OnChanged(function(value)
        if value == "No macros saved" then
            return
        end

        local id = state.optionToId[value]

        if id then
            local ok = app:SelectMacro(id)

            if ok then
                state.selectedId = id
                updateMacroInfo()
            end
        end
    end)

    Tab:AddButton({
        Title = "Refresh Macro List",
        Callback = refreshLibrary,
    })

    Tab:AddInput("RE_MacroRename", {
        Title = "Rename Selected Macro",
        Placeholder = "New macro name",
    })

    Tab:AddButton({
        Title = "Apply Rename",
        Callback = function()
            local id = app:GetSelectedMacroId() or state.selectedId
            local name = Options.RE_MacroRename and Options.RE_MacroRename.Value or ""

            if not id then
                safeNotify(Fluent, "Macros", "Select a macro first.", 2)
                return
            end

            if name == "" then
                safeNotify(Fluent, "Macros", "Enter a new macro name.", 2)
                return
            end

            local ok, result = app:RenameMacro(id, name)

            if ok then
                safeNotify(Fluent, "Macros", "Macro renamed.", 2)
                refreshLibrary()
            else
                safeNotify(Fluent, "Macros", tostring(result), 3)
            end
        end,
    })

    Tab:AddButton({
        Title = "Delete Selected Macro",
        Callback = function()
            local id = app:GetSelectedMacroId() or state.selectedId

            if not id then
                safeNotify(Fluent, "Macros", "Select a macro first.", 2)
                return
            end

            local ok = app:DeleteMacro(id)

            if ok then
                state.selectedId = nil
                safeNotify(Fluent, "Macros", "Macro deleted.", 2)
                refreshLibrary()
            end
        end,
    })

    -- =========================================================
    -- IMPORT / EXPORT
    -- =========================================================
    Tab:AddSection("Import / Export")

    Tab:AddInput("RE_MacroImport", {
        Title = "Import Macro JSON",
        Placeholder = "Paste macro JSON here",
    })

    local ioStatus = Tab:AddParagraph({
        Title = "Import / Export Status",
        Content = "Idle",
    })

    Tab:AddButton({
        Title = "Import Macro",
        Callback = function()
            local json = Options.RE_MacroImport and Options.RE_MacroImport.Value or ""

            if json == "" then
                setParagraph(ioStatus, "No JSON provided.")
                return
            end

            local ok, macro, id = pcall(function()
                local imported, importedId = app:ImportMacro(json)
                return imported, importedId
            end)

            if ok and macro then
                state.selectedId = id
                setParagraph(ioStatus, "Imported: " .. tostring(macro.name))
                safeNotify(Fluent, "Macros", "Macro imported.", 2)
                refreshLibrary()
            else
                setParagraph(ioStatus, "Import failed.")
                safeNotify(Fluent, "Macros", "Invalid macro JSON.", 3)
            end
        end,
    })

    Tab:AddButton({
        Title = "Export Selected Macro",
        Callback = function()
            local ok, json = pcall(function()
                return app:ExportSelectedMacro()
            end)

            if not ok or type(json) ~= "string" then
                setParagraph(ioStatus, "Export failed.")
                safeNotify(Fluent, "Macros", "Select a macro first.", 2)
                return
            end

            state.lastExport = json
            setParagraph(ioStatus, "Export ready: " .. tostring(#json) .. " bytes")
            print("[ReAdventuresV2][MacroExport]", json)
            safeNotify(Fluent, "Macros", "Macro exported to console output.", 3)
        end,
    })

    -- =========================================================
    -- MACRO STATUS
    -- =========================================================
    Tab:AddSection("Macro Status")

    local runtimeStatus = Tab:AddParagraph({
        Title = "Runtime",
        Content = "Loading state...",
    })

    local function refreshRuntime()
        local snapshot = app:GetState()
        local summary = app:GetMacrosSummary()

        setParagraph(
            runtimeStatus,
            string.format(
                "Map: %s / %s\nWave: %s | Money: %s | Life: %s/%s\nUnits: %s | Enemies: %s\nSaved Macros: %s | Recording: %s",
                tostring(snapshot.map.area or "unknown"),
                tostring(snapshot.map.level or "unknown"),
                tostring(snapshot.match.wave or 0),
                tostring(snapshot.player.money or "?"),
                tostring(snapshot.player.baseLife or "?"),
                tostring(snapshot.player.baseMaxLife or "?"),
                tostring(snapshot.counters.unitsPlaced or 0),
                tostring(snapshot.counters.enemiesAlive or 0),
                tostring(summary.count or 0),
                tostring(summary.recording == true)
            )
        )
    end

    Tab:AddButton({
        Title = "Refresh Macro Status",
        Callback = function()
            refreshLibrary()
            refreshRuntime()
        end,
    })

    refreshLibrary()
    refreshRuntime()

    return {
        Tab = Tab,
        Refresh = function()
            refreshLibrary()
            refreshRuntime()
        end,
        GetLastExport = function()
            return state.lastExport
        end,
        SetImportText = function(value)
            pcall(function()
                Options.RE_MacroImport:SetValue(tostring(value or ""))
            end)
        end,
    }
end

return UI
