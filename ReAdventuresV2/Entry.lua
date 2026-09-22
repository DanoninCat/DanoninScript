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

        pcall(function()
            SaveManager:LoadAutoloadConfig()
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
