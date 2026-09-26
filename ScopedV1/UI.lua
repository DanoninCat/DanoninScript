local UI = {}

local function set(app, patch)
    app:SetConfig(patch)
end

function UI.Attach(Window, app, Fluent)
    local config = app:GetConfig()

    local Aim = Window:AddTab({
        Title = "Aim",
        Icon = "crosshair",
    })

    Aim:AddSection("Aimbot")

    local aimEnabled = Aim:AddToggle("SC_AimEnabled", {
        Title = "Enable Aggressive Aim",
        Default = config.aimEnabled,
    })
    aimEnabled:OnChanged(function(value)
        set(app, {aimEnabled = value})
    end)

    local autoScope = Aim:AddToggle("SC_AutoScope", {
        Title = "Auto Scope",
        Description = "Uses AutoScopeEnabled from the second dump.",
        Default = config.autoScope,
    })
    autoScope:OnChanged(function(value)
        set(app, {autoScope = value})
    end)

    local aimMode = Aim:AddDropdown("SC_AimMode", {
        Title = "Aim Mode",
        Values = {"Always", "RMB"},
        Default = config.aimMode,
    })
    aimMode:OnChanged(function(value)
        set(app, {aimMode = value})
    end)

    local aimPart = Aim:AddDropdown("SC_AimPart", {
        Title = "Aim Part",
        Values = {"Head", "UpperTorso", "Torso", "HumanoidRootPart"},
        Default = config.aimPart,
    })
    aimPart:OnChanged(function(value)
        set(app, {aimPart = value})
    end)

    Aim:AddSection("Targeting")

    local fov = Aim:AddSlider("SC_FOV", {
        Title = "FOV",
        Default = config.fov,
        Min = 60,
        Max = 2000,
        Rounding = 0,
    })
    fov:OnChanged(function(value)
        set(app, {fov = tonumber(value) or 520})
    end)

    local strength = Aim:AddSlider("SC_Strength", {
        Title = "Aim Strength",
        Description = "100 = near-instant lock.",
        Default = math.floor(config.strength * 100 + 0.5),
        Min = 1,
        Max = 100,
        Rounding = 0,
    })
    strength:OnChanged(function(value)
        set(app, {strength = (tonumber(value) or 92) / 100})
    end)

    local prediction = Aim:AddSlider("SC_PredictionMs", {
        Title = "Prediction",
        Description = "Lead target in milliseconds.",
        Default = math.floor(config.predictionSeconds * 1000 + 0.5),
        Min = 0,
        Max = 100,
        Rounding = 0,
    })
    prediction:OnChanged(function(value)
        set(app, {predictionSeconds = (tonumber(value) or 35) / 1000})
    end)

    local maxDistance = Aim:AddSlider("SC_MaxDistance", {
        Title = "Max Aim Distance",
        Default = config.maxDistance,
        Min = 100,
        Max = 5000,
        Rounding = 0,
    })
    maxDistance:OnChanged(function(value)
        set(app, {maxDistance = tonumber(value) or 2500})
    end)

    local snap = Aim:AddToggle("SC_Snap", {
        Title = "Instant Snap",
        Default = config.snap,
    })
    snap:OnChanged(function(value)
        set(app, {snap = value})
    end)

    local sticky = Aim:AddToggle("SC_Sticky", {
        Title = "Sticky Target",
        Default = config.stickyTarget,
    })
    sticky:OnChanged(function(value)
        set(app, {stickyTarget = value})
    end)

    local visibility = Aim:AddToggle("SC_Visibility", {
        Title = "Wall Check",
        Default = config.visibilityCheck,
    })
    visibility:OnChanged(function(value)
        set(app, {visibilityCheck = value})
    end)

    local predictionToggle = Aim:AddToggle("SC_PredictionEnabled", {
        Title = "Movement Prediction",
        Default = config.prediction,
    })
    predictionToggle:OnChanged(function(value)
        set(app, {prediction = value})
    end)

    local teamCheck = Aim:AddToggle("SC_TeamCheck", {
        Title = "Team Check",
        Description = "Off by default because Scoped is FFA.",
        Default = config.teamCheck,
    })
    teamCheck:OnChanged(function(value)
        set(app, {teamCheck = value})
    end)

    local showFov = Aim:AddToggle("SC_ShowFOV", {
        Title = "Show FOV",
        Default = config.showFov,
    })
    showFov:OnChanged(function(value)
        set(app, {showFov = value})
    end)

    Aim:AddSection("Presets")

    Aim:AddButton({
        Title = "Aggressive",
        Callback = function()
            app:ApplyPreset("Aggressive")
            Fluent:Notify({Title = "Cat Empire", Content = "Aggressive preset applied", Duration = 2})
        end,
    })

    Aim:AddButton({
        Title = "Rage",
        Callback = function()
            app:ApplyPreset("Rage")
            Fluent:Notify({Title = "Cat Empire", Content = "Rage preset applied", Duration = 2})
        end,
    })

    Aim:AddButton({
        Title = "Legit",
        Callback = function()
            app:ApplyPreset("Legit")
            Fluent:Notify({Title = "Cat Empire", Content = "Legit preset applied", Duration = 2})
        end,
    })

    local ESP = Window:AddTab({
        Title = "ESP",
        Icon = "eye",
    })

    ESP:AddSection("ESP")

    local espEnabled = ESP:AddToggle("SC_ESPEnabled", {
        Title = "Enable ESP",
        Default = config.espEnabled,
    })
    espEnabled:OnChanged(function(value)
        set(app, {espEnabled = value})
    end)

    local box = ESP:AddToggle("SC_Box", {
        Title = "Box",
        Default = config.box,
    })
    box:OnChanged(function(value)
        set(app, {box = value})
    end)

    local name = ESP:AddToggle("SC_Name", {
        Title = "Name",
        Default = config.name,
    })
    name:OnChanged(function(value)
        set(app, {name = value})
    end)

    local distance = ESP:AddToggle("SC_Distance", {
        Title = "Distance",
        Default = config.distance,
    })
    distance:OnChanged(function(value)
        set(app, {distance = value})
    end)

    local health = ESP:AddToggle("SC_HealthBar", {
        Title = "Health Bar",
        Default = config.healthBar,
    })
    health:OnChanged(function(value)
        set(app, {healthBar = value})
    end)

    local tracer = ESP:AddToggle("SC_Tracer", {
        Title = "Tracer",
        Default = config.tracer,
    })
    tracer:OnChanged(function(value)
        set(app, {tracer = value})
    end)

    local highlight = ESP:AddToggle("SC_Highlight", {
        Title = "Highlight / Chams",
        Description = "AlwaysOnTop fallback when Drawing is unavailable.",
        Default = config.highlight,
    })
    highlight:OnChanged(function(value)
        set(app, {highlight = value})
    end)

    local maxEspDistance = ESP:AddSlider("SC_MaxESPDistance", {
        Title = "Max ESP Distance",
        Default = config.maxEspDistance,
        Min = 100,
        Max = 6000,
        Rounding = 0,
    })
    maxEspDistance:OnChanged(function(value)
        set(app, {maxEspDistance = tonumber(value) or 3000})
    end)

    ESP:AddSection("Runtime")

    ESP:AddButton({
        Title = "Clear Current Target",
        Callback = function()
            app.currentTarget = nil
        end,
    })

    return {
        Aim = Aim,
        ESP = ESP,
    }
end

return UI
