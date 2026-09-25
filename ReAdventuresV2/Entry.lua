return function(Core, UI)
    if game.PlaceId ~= 138271828389486 and game.PlaceId ~= 94823097601547 then
        return
    end

    local env = (getgenv and getgenv()) or _G

    -- Old queue_on_teleport registrations can all fetch the newest Loader.
    -- Never recycle a healthy interface just because another queued copy fired.
    local active = env.__RE_ADVENTURES_V2
    if active and active.App and active.App.running then
        return active
    end

    -- Protect the initialization window before env.__RE_ADVENTURES_V2 exists.
    -- Once the active app is published, the guard above becomes permanent for
    -- the current JobId and late queued copies simply return it.
    local boot = env.__RE_ADVENTURES_BOOT
    if boot
        and boot.jobId == game.JobId
        and os.clock() - (tonumber(boot.at) or 0) < 60
    then
        return active
    end

    env.__RE_ADVENTURES_BOOT = {
        jobId = game.JobId,
        at = os.clock(),
    }

    local previous = active
    if previous then
        if previous.App then previous.App:Stop() end
        if previous.Fluent and previous.Fluent.Destroy then pcall(function() previous.Fluent:Destroy() end) end
    end
    if not game:IsLoaded() then game.Loaded:Wait() end
    local player = game:GetService("Players").LocalPlayer
    if player then player:WaitForChild("PlayerGui", 20) end
    if game.PlaceId == 138271828389486 then
        local workspace = game:GetService("Workspace")
        for _, name in ipairs({"_DATA", "_MAP_CONFIG", "_UNITS"}) do workspace:WaitForChild(name, 10) end
    end
    local fluentSource = env["__CE_F_91A7"]

    if type(fluentSource) ~= "string" or fluentSource == "" then
        return
    end

    local okFluent, Fluent = pcall(function()
        return loadstring(fluentSource)()
    end)

    if not okFluent or not Fluent then
        return
    end

    local SaveManager
    local InterfaceManager

    pcall(function()
        SaveManager = loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua",
            true
        ))()
    end)

    pcall(function()
        InterfaceManager = loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua",
            true
        ))()
    end)

    local app = Core.new({
        recorder = {
            snapshotInterval = 1,
            maxSnapshots = 7200,
        },
    })

    app:Start()

    local Window = Fluent:CreateWindow({
        Title = "Cat Empire",
        SubTitle = "Re Adventures",
        TabWidth = 160,
        Size = UDim2.fromOffset(720, 480),
        Acrylic = true,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightControl,
    })

    local archivePath = "CatEmpire/ReAdventures/macros.json"
    local http = game:GetService("HttpService")
    local canSave = type(env.writefile) == "function" and type(env.makefolder) == "function"
    local function storageNotice(text)
        Fluent:Notify({Title = "Cat Empire", Content = text, Duration = 4})
    end
    if type(env.isfile) == "function" and type(env.readfile) == "function" and env.isfile(archivePath) then
        local ok, err = pcall(function()
            local archive = http:JSONDecode(env.readfile(archivePath))
            assert(type(archive) == "table" and archive.version == 1 and type(archive.macros) == "table", "Invalid macro archive")
            local library = Core.MacroLibrary.new()
            for _, macro in ipairs(archive.macros) do library:add(macro) end
            if archive.selectedId then library:select(archive.selectedId) end
            app.macros = library
        end)
        if not ok then storageNotice("Could not load saved macros: " .. tostring(err)) end
    end

    local areas = UI.Attach(Window, app, Fluent)
    table.insert(app.uiDisconnectors, app:On("macrosChanged", function()
        if not canSave then
            storageNotice("Macros are in memory. Use Export to keep a copy.")
            return
        end
        local ok, err = pcall(function()
            for _, folder in ipairs({"CatEmpire", "CatEmpire/ReAdventures"}) do
                if type(env.isfolder) ~= "function" or not env.isfolder(folder) then env.makefolder(folder) end
            end
            local archive = {version = 1, selectedId = app:GetSelectedMacroId(), macros = {}}
            for _, item in ipairs(app:ListMacros()) do table.insert(archive.macros, app:GetMacro(item.id)) end
            env.writefile(archivePath, http:JSONEncode(archive))
        end)
        if not ok then storageNotice("Could not save macros: " .. tostring(err)) end
    end))
    task.spawn(function()
        while app.running do
            if Fluent.Unloaded then app:Stop(); break end
            task.wait(0.5)
        end
    end)

    local Settings

    if SaveManager and InterfaceManager then
        Settings = Window:AddTab({
            Title = "Settings",
            Icon = "settings",
        })

        -- Append runtime controls to the interface's existing Settings tab.
        -- Do not create or replace a second test Settings interface.
        UI.AttachRuntimeSettings(Settings, app, Fluent)

        SaveManager:SetLibrary(Fluent)
        InterfaceManager:SetLibrary(Fluent)
        SaveManager:IgnoreThemeSettings()
        SaveManager:SetIgnoreIndexes({"RE_MacroAutoPlay", "RE_MacroImport"})
        InterfaceManager:SetFolder("CatEmpire/ReAdventures")
        SaveManager:SetFolder("CatEmpire/ReAdventures/configs")

        -- The Loader embeds Fluent but downloads InterfaceManager at runtime.
        -- Building the external manager's UI against a different Fluent version
        -- can stop after Runtime Automation. Load its saved values, then render
        -- the original controls with the already-running embedded Fluent API.
        pcall(function()
            InterfaceManager:LoadSettings()
        end)
        UI.AttachInterfaceSettings(Settings, Fluent, InterfaceManager)

        pcall(function()
            SaveManager:BuildConfigSection(Settings)
        end)

        local autoSaveReady = false
        local autoSaveQueued = false

        local function queueAutoSave()
            if not autoSaveReady or autoSaveQueued then
                return
            end

            autoSaveQueued = true

            task.delay(0.25, function()
                autoSaveQueued = false
                pcall(function()
                    SaveManager:Save("autosave")
                end)
            end)
        end

        -- Fluent OnChanged replaces the previous callback; subscribe to the
        -- controller event so autosave cannot disconnect the actual feature.
        table.insert(app.uiDisconnectors, app:On("webhookConfigChanged", queueAutoSave))
        table.insert(app.uiDisconnectors, app:On("challengerConfigChanged", queueAutoSave))
        table.insert(app.uiDisconnectors, app:On("runtimeConfigChanged", queueAutoSave))
        table.insert(app.uiDisconnectors, app:On("autoStoryConfigChanged", queueAutoSave))
        table.insert(app.uiDisconnectors, app:On("autoInfiniteConfigChanged", queueAutoSave))

        pcall(function()
            SaveManager:LoadAutoloadConfig()
        end)

        pcall(function()
            SaveManager:Load("autosave")
        end)

        task.delay(0.35, function()
            local function multiValue(option, allowed, fallback)
                local out = {}
                for _, name in ipairs(allowed) do out[name] = false end

                local value = option and option.Value
                if type(value) == "table" then
                    for key, item in pairs(value) do
                        if type(key) == "string" and out[key] ~= nil then
                            out[key] = item == true
                        elseif type(item) == "string" and out[item] ~= nil then
                            out[item] = true
                        end
                    end
                elseif type(value) == "string" and out[value] ~= nil then
                    out[value] = true
                end

                local any = false
                for _, enabledValue in pairs(out) do
                    if enabledValue then any = true break end
                end

                if not any and fallback and out[fallback] ~= nil then
                    out[fallback] = true
                end

                return out
            end

            local url = Fluent.Options.RE_WebhookURL
                and Fluent.Options.RE_WebhookURL.Value
                or ""

            local enabled = Fluent.Options.RE_WebhookEnabled
                and Fluent.Options.RE_WebhookEnabled.Value == true

            app:SetWebhookConfig({
                url = tostring(url or ""),
                enabled = enabled,
            })

            app:SetChallengerConfig({
                enabled = Fluent.Options.RE_ChallengerEnabled
                    and Fluent.Options.RE_ChallengerEnabled.Value == true,
                types = multiValue(
                    Fluent.Options.RE_ChallengerTypes,
                    {"Normal", "Daily"},
                    "Normal"
                ),
                priority = Fluent.Options.RE_ChallengerPriority
                    and Fluent.Options.RE_ChallengerPriority.Value
                    or "Normal",
                autoReady = not Fluent.Options.RE_ChallengerAutoReady
                    or Fluent.Options.RE_ChallengerAutoReady.Value == true,
                autoLoadMacro = not Fluent.Options.RE_ChallengerAutoMacro
                    or Fluent.Options.RE_ChallengerAutoMacro.Value == true,
                autoReturnLobby = not Fluent.Options.RE_ChallengerReturnLobby
                    or Fluent.Options.RE_ChallengerReturnLobby.Value == true,
            })

            app:SetAutoInfiniteConfig({
                autoReady = Fluent.Options.RE_InfiniteAutoReady
                    and Fluent.Options.RE_InfiniteAutoReady.Value == true,
                autoPlace = Fluent.Options.RE_InfiniteAutoPlaceEnabled
                    and Fluent.Options.RE_InfiniteAutoPlaceEnabled.Value == true,
                autoUpgrade = Fluent.Options.RE_InfiniteAutoUpgradeEnabled
                    and Fluent.Options.RE_InfiniteAutoUpgradeEnabled.Value == true,
                autoSellAll = Fluent.Options.RE_InfiniteSellAll
                    and Fluent.Options.RE_InfiniteSellAll.Value == true,
                sellWave = Fluent.Options.RE_InfiniteSellWave
                    and tonumber(Fluent.Options.RE_InfiniteSellWave.Value)
                    or 50,
                autoReplay = Fluent.Options.RE_InfiniteAutoReplay
                    and Fluent.Options.RE_InfiniteAutoReplay.Value == true,
                autoReturnLobby = Fluent.Options.RE_InfiniteReturnLobby
                    and Fluent.Options.RE_InfiniteReturnLobby.Value == true,
            })

            app:SetRuntimeConfig({
                antiAfk = Fluent.Options.RE_AntiAFK
                    and Fluent.Options.RE_AntiAFK.Value == true,
                autoReconnect = Fluent.Options.RE_AutoReconnect
                    and Fluent.Options.RE_AutoReconnect.Value == true,
                autoExecute = Fluent.Options.RE_AutoExecute
                    and Fluent.Options.RE_AutoExecute.Value == true,
            })

            autoSaveReady = true
        end)
    end

    pcall(function()
        Window:SelectTab(1)
    end)

    env.__RE_ADVENTURES_V2 = {
        App = app,
        Fluent = Fluent,
        Window = Window,
        AutoStory = areas.AutoStory,
        Infinite = areas.Infinite,
        Challengers = areas.Challengers,
        Macros = areas.Macros,
        Webhook = areas.Webhook,
        Settings = Settings,
        Version = Core.VERSION,
    }

    return env.__RE_ADVENTURES_V2
end
