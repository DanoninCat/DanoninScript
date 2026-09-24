return function(Core, UI)
    if game.PlaceId ~= 138271828389486 and game.PlaceId ~= 94823097601547 then
        return
    end

    local env = (getgenv and getgenv()) or _G
    local previous = env.__RE_ADVENTURES_V2
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

        UI.AttachRuntimeSettings(Settings, app, Fluent)

        SaveManager:SetLibrary(Fluent)
        InterfaceManager:SetLibrary(Fluent)
        SaveManager:IgnoreThemeSettings()
        SaveManager:SetIgnoreIndexes({"RE_MacroAutoPlay", "RE_MacroImport"})
        InterfaceManager:SetFolder("CatEmpire/ReAdventures")
        SaveManager:SetFolder("CatEmpire/ReAdventures/configs")
        InterfaceManager:BuildInterfaceSection(Settings)
        SaveManager:BuildConfigSection(Settings)

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

        pcall(function()
            SaveManager:LoadAutoloadConfig()
        end)

        pcall(function()
            SaveManager:Load("autosave")
        end)

        task.delay(0.35, function()
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
                kind = Fluent.Options.RE_ChallengerType
                    and Fluent.Options.RE_ChallengerType.Value
                    or "Normal",
                autoLoadMacro = not Fluent.Options.RE_ChallengerAutoMacro
                    or Fluent.Options.RE_ChallengerAutoMacro.Value == true,
                autoReturnLobby = not Fluent.Options.RE_ChallengerReturnLobby
                    or Fluent.Options.RE_ChallengerReturnLobby.Value == true,
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
        Challengers = areas.Challengers,
        Macros = areas.Macros,
        Webhook = areas.Webhook,
        Settings = Settings,
        Version = Core.VERSION,
    }

    return env.__RE_ADVENTURES_V2
end
