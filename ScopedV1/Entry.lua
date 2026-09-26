return function(Core, UI)
    if game.PlaceId ~= 93466613073564 then
        return
    end

    local env = (getgenv and getgenv()) or _G
    local active = env.__CAT_EMPIRE_SCOPED

    if active and active.Version == Core.VERSION and active.App and active.App.running then
        return active
    end

    if active then
        if active.App then pcall(function() active.App:Stop() end) end
        if active.Fluent and active.Fluent.Destroy then
            pcall(function() active.Fluent:Destroy() end)
        end
    end

    if not game:IsLoaded() then
        game.Loaded:Wait()
    end

    local player = game:GetService("Players").LocalPlayer
    if player then
        player:WaitForChild("PlayerGui", 20)
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

    local SaveManager = Fluent.SaveManager
    local InterfaceManager = Fluent.InterfaceManager

    local app = Core.new()
    app:Start()

    local Window = Fluent:CreateWindow({
        Title = "Cat Empire",
        SubTitle = "Scoped",
        TabWidth = 160,
        Size = UDim2.fromOffset(720, 480),
        Acrylic = true,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightControl,
    })

    local tabs = UI.Attach(Window, app, Fluent)
    local Settings

    if SaveManager and InterfaceManager then
        Settings = Window:AddTab({
            Title = "Settings",
            Icon = "settings",
        })

        SaveManager:SetLibrary(Fluent)
        InterfaceManager:SetLibrary(Fluent)
        SaveManager:IgnoreThemeSettings()
        SaveManager:SetIgnoreIndexes({
            "DisableBGToggle",
            "InterfaceFont",
        })

        InterfaceManager:SetFolder("CatEmpire/Scoped")
        SaveManager:SetFolder("CatEmpire/Scoped/configs")

        InterfaceManager:BuildInterfaceSection(Settings)
        SaveManager:BuildConfigSection(Settings)

        local ready = false
        local queued = false

        local function autoSave()
            if not ready or queued then return end
            queued = true
            task.delay(0.25, function()
                queued = false
                pcall(function()
                    SaveManager:Save("autosave")
                end)
            end)
        end

        env.__CAT_EMPIRE_SCOPED_AUTOSAVE_DISCONNECT = app:On("configChanged", autoSave)

        pcall(function()
            SaveManager:LoadAutoloadConfig()
        end)

        pcall(function()
            SaveManager:Load("autosave")
        end)

        task.delay(0.35, function()
            ready = true
        end)
    end

    pcall(function()
        Window:SelectTab(1)
    end)

    task.spawn(function()
        while app.running do
            if Fluent.Unloaded then
                app:Stop()
                break
            end
            task.wait(0.5)
        end
    end)

    env.__CAT_EMPIRE_SCOPED = {
        App = app,
        Fluent = Fluent,
        Window = Window,
        Aim = tabs.Aim,
        ESP = tabs.ESP,
        Settings = Settings,
        Version = Core.VERSION,
    }

    return env.__CAT_EMPIRE_SCOPED
end
