return function(Core, UI)
    if game.PlaceId ~= 138271828389486 and game.PlaceId ~= 94823097601547 then
        return
    end

    local env = (getgenv and getgenv()) or _G
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

    local areas = UI.Attach(Window, app, Fluent)

    local Settings

    if SaveManager and InterfaceManager then
        Settings = Window:AddTab({
            Title = "Settings",
            Icon = "settings",
        })

        SaveManager:SetLibrary(Fluent)
        InterfaceManager:SetLibrary(Fluent)
        SaveManager:IgnoreThemeSettings()
        SaveManager:SetIgnoreIndexes({})
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

        local webhookUrlOption = Fluent.Options.RE_WebhookURL
        local webhookEnabledOption = Fluent.Options.RE_WebhookEnabled

        if webhookUrlOption and type(webhookUrlOption.OnChanged) == "function" then
            webhookUrlOption:OnChanged(queueAutoSave)
        end

        if webhookEnabledOption and type(webhookEnabledOption.OnChanged) == "function" then
            webhookEnabledOption:OnChanged(queueAutoSave)
        end

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

            autoSaveReady = true
        end)
    end

    pcall(function()
        Window:SelectTab(1)
    end)

    env.__RE_ADVENTURES_V2 = {
        App = app,
        Window = Window,
        AutoStory = areas.AutoStory,
        Macros = areas.Macros,
        Webhook = areas.Webhook,
        Settings = Settings,
        Version = Core.VERSION,
    }

    return env.__RE_ADVENTURES_V2
end
