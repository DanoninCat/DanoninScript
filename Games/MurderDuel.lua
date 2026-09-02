-- ============================================================
-- CAT EMPIRE | ESP FIXED EDITION
-- UI preta/roxa + ESPs independentes e corrigidas.
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = ReplicatedStorage:WaitForChild("Util")

local FOVController = require(Shared:WaitForChild("FOVController"))
local ThirdPerson = require(Shared:WaitForChild("ThirdPerson"))
local RayCast = require(Util:WaitForChild("RayCast"))

local Fluent = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Libs/Fluent.lua",
    true
))()

local PURPLE = Color3.fromRGB(164, 82, 255)

local State = {
    ESP = {
        Enabled = false,
        Highlight = true,
        Distance = true,
        Tracers = false,
        TeamCheck = true,
    },

    Aim = {
        Enabled = false,
        Silent = false,
        Assist = false,
        Strength = 0.5,
        Radius = 200,
        Target = nil,
        Smoothing = 0.35,
        AutoShoot = false,
    },

    Visual = {
        FOVCircle = false,
        FOVRadius = 200,
        CameraFOV = 70,
        TracerOrigin = "BottomCenter",
    },
}

local ESPObjects = {}
local TracerObjects = {}
local Connections = {}

local WindowRef = nil
local UIClosed = false

local TargetData = {
    Current = nil,
    Position = nil,
    Distance = 0,
    Angle = 0,
    Visible = false,
}

local function GetCamera()
    return workspace.CurrentCamera
end

local function GetPlayerGui()
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function DestroyNamedGui(name)
    local gui = GetPlayerGui():FindFirstChild(name)
    if gui then
        gui:Destroy()
    end
end

local function DisconnectAll()
    for _, connection in ipairs(Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(Connections)
end

local function GetCharacters()
    local result = {}
    local folder = workspace:FindFirstChild("Characters")

    if not folder then
        return result
    end

    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model") and child ~= LocalPlayer.Character then
            table.insert(result, child)
        end
    end

    return result
end

local function GetHumanoid(char)
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

local function IsAlive(char)
    local humanoid = GetHumanoid(char)
    return humanoid ~= nil and humanoid.Health > 0
end

local function IsEnemy(char)
    if not char or char == LocalPlayer.Character then
        return false
    end

    if not IsAlive(char) then
        return false
    end

    if State.ESP.TeamCheck then
        local myChar = LocalPlayer.Character
        if myChar then
            local mySide = myChar:GetAttribute("MatchSide")
            local theirSide = char:GetAttribute("MatchSide")

            if mySide ~= nil and theirSide ~= nil and mySide == theirSide then
                return false
            end
        end
    end

    return true
end

local function GetTargetPart(char)
    if not char then return nil end

    return char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("Head")
end

local function GetHeadPosition(char)
    local head = char and char:FindFirstChild("Head")
    if head then
        return head.Position
    end

    local part = GetTargetPart(char)
    if part then
        return part.Position
    end

    if char then
        return char:GetPivot().Position
    end

    return Vector3.zero
end

local function ProjectToScreen(worldPosition)
    local camera = GetCamera()
    if not camera then
        return nil, false
    end

    local screenPosition, onScreen = camera:WorldToViewportPoint(worldPosition)
    local visible = onScreen and screenPosition.Z > 0

    return screenPosition, visible
end

local function GetDistance(a, b)
    return (a - b).Magnitude
end

-- ============================================================
-- ESP: HIGHLIGHT + DISTANCE
-- ============================================================

local function DestroyHighlight(data)
    if data and data.Highlight then
        pcall(function()
            data.Highlight:Destroy()
        end)
        data.Highlight = nil
    end
end

local function DestroyDistance(data)
    if data and data.Distance then
        pcall(function()
            data.Distance:Destroy()
        end)
        data.Distance = nil
        data.Label = nil
    end
end

local function RemoveESP(char)
    local data = ESPObjects[char]
    if not data then return end

    DestroyHighlight(data)
    DestroyDistance(data)
    ESPObjects[char] = nil
end

local function EnsureESPData(char)
    local data = ESPObjects[char]
    if not data then
        data = {}
        ESPObjects[char] = data
    end
    return data
end

local function EnsureHighlight(char, data)
    if not State.ESP.Highlight then
        DestroyHighlight(data)
        return
    end

    if data.Highlight and data.Highlight.Parent then
        data.Highlight.Enabled = true
        return
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "CAT_EMPIRE_Highlight"
    highlight.Adornee = char
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = PURPLE
    highlight.FillTransparency = 0.72
    highlight.OutlineColor = PURPLE
    highlight.OutlineTransparency = 0.05
    highlight.Enabled = true
    highlight.Parent = char

    data.Highlight = highlight
end

local function EnsureDistance(char, data)
    if not State.ESP.Distance then
        DestroyDistance(data)
        return
    end

    local adornee = char:FindFirstChild("Head") or GetTargetPart(char)
    if not adornee then
        DestroyDistance(data)
        return
    end

    if data.Distance and data.Distance.Parent then
        data.Distance.Adornee = adornee
        return
    end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "CAT_EMPIRE_Distance"
    billboard.Adornee = adornee
    billboard.Size = UDim2.fromOffset(110, 24)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = 10000
    billboard.Parent = GetPlayerGui()

    local label = Instance.new("TextLabel")
    label.Name = "Distance"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Text = ""
    label.TextColor3 = PURPLE
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0.25
    label.TextSize = 12
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.Parent = billboard

    data.Distance = billboard
    data.Label = label
end

local function UpdateESP()
    local myChar = LocalPlayer.Character

    if not State.ESP.Enabled or not myChar then
        for char in pairs(ESPObjects) do
            RemoveESP(char)
        end
        return
    end

    local myRoot = GetTargetPart(myChar)
    if not myRoot then
        return
    end

    local current = {}

    for _, char in ipairs(GetCharacters()) do
        current[char] = true

        if IsEnemy(char) then
            local data = EnsureESPData(char)

            EnsureHighlight(char, data)
            EnsureDistance(char, data)

            if data.Label then
                local targetPart = GetTargetPart(char)
                if targetPart then
                    local distance = GetDistance(myRoot.Position, targetPart.Position)
                    data.Label.Text = string.format("%.0f", distance)
                else
                    data.Label.Text = ""
                end
            end

            -- Se os dois tipos estiverem desligados, não mantém uma entrada vazia.
            if not data.Highlight and not data.Distance then
                ESPObjects[char] = nil
            end
        else
            RemoveESP(char)
        end
    end

    for char in pairs(ESPObjects) do
        if not current[char] then
            RemoveESP(char)
        end
    end
end

-- ============================================================
-- TRACERS
-- ============================================================

local function GetTracerGui()
    local playerGui = GetPlayerGui()
    local gui = playerGui:FindFirstChild("CAT_EMPIRE_Tracers")

    if gui then
        return gui
    end

    gui = Instance.new("ScreenGui")
    gui.Name = "CAT_EMPIRE_Tracers"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9997
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui

    return gui
end

local function CreateTracer(char)
    if TracerObjects[char] then
        return TracerObjects[char]
    end

    local line = Instance.new("Frame")
    line.Name = "Tracer_" .. char.Name
    line.AnchorPoint = Vector2.new(0, 0.5)
    line.BackgroundColor3 = PURPLE
    line.BackgroundTransparency = 0.28
    line.BorderSizePixel = 0
    line.Size = UDim2.fromOffset(0, 1)
    line.Visible = false
    line.ZIndex = 10
    line.Parent = GetTracerGui()

    TracerObjects[char] = line
    return line
end

local function RemoveTracer(char)
    local line = TracerObjects[char]
    if not line then return end

    pcall(function()
        line:Destroy()
    end)
    TracerObjects[char] = nil
end

local function ClearTracers()
    for char in pairs(TracerObjects) do
        RemoveTracer(char)
    end
end

local function GetTracerOrigin(viewportSize)
    if State.Visual.TracerOrigin == "Center" then
        return Vector2.new(viewportSize.X * 0.5, viewportSize.Y * 0.5)
    end

    if State.Visual.TracerOrigin == "Bottom" then
        return Vector2.new(viewportSize.X * 0.5, viewportSize.Y - 2)
    end

    -- BottomCenter
    return Vector2.new(viewportSize.X * 0.5, viewportSize.Y * 0.90)
end

local function UpdateTracers()
    if not State.ESP.Enabled or not State.ESP.Tracers then
        ClearTracers()
        return
    end

    local camera = GetCamera()
    if not camera then
        ClearTracers()
        return
    end

    local origin = GetTracerOrigin(camera.ViewportSize)
    local current = {}

    for _, char in ipairs(GetCharacters()) do
        current[char] = true

        if IsEnemy(char) then
            local targetPart = GetTargetPart(char)
            local line = CreateTracer(char)

            if targetPart then
                local screenPos, onScreen = ProjectToScreen(targetPart.Position)

                if onScreen and screenPos then
                    local target = Vector2.new(screenPos.X, screenPos.Y)
                    local delta = target - origin
                    local length = delta.Magnitude

                    if length > 0.5 then
                        line.Position = UDim2.fromOffset(origin.X, origin.Y)
                        line.Size = UDim2.fromOffset(length, 1)
                        line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
                        line.Visible = true
                    else
                        line.Visible = false
                    end
                else
                    line.Visible = false
                end
            else
                line.Visible = false
            end
        else
            RemoveTracer(char)
        end
    end

    for char in pairs(TracerObjects) do
        if not current[char] then
            RemoveTracer(char)
        end
    end
end

-- ============================================================
-- FOV CIRCLE
-- ============================================================

local function CreateFOVCircle()
    DestroyNamedGui("FOVCircle")

    local gui = Instance.new("ScreenGui")
    gui.Name = "FOVCircle"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9998
    gui.Parent = GetPlayerGui()

    local circle = Instance.new("Frame")
    circle.Name = "Outline"
    circle.AnchorPoint = Vector2.new(0.5, 0.5)
    circle.Size = UDim2.fromOffset(State.Visual.FOVRadius * 2, State.Visual.FOVRadius * 2)
    circle.Position = UDim2.fromScale(0.5, 0.5)
    circle.BackgroundTransparency = 1
    circle.BorderSizePixel = 0
    circle.Parent = gui

    local round = Instance.new("UICorner")
    round.CornerRadius = UDim.new(1, 0)
    round.Parent = circle

    local outline = Instance.new("UIStroke")
    outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    outline.Color = PURPLE
    outline.Thickness = 1
    outline.Transparency = 0.12
    outline.Parent = circle

    return gui
end

local function UpdateFOVCircle()
    if State.Visual.FOVCircle then
        CreateFOVCircle()
    else
        DestroyNamedGui("FOVCircle")
    end
end

-- ============================================================
-- TARGET / AIM (mantido)
-- ============================================================

local function GetClosestTarget()
    local closest = nil
    local closestDist = State.Aim.Radius
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)

    for _, char in ipairs(GetCharacters()) do
        if IsEnemy(char) then
            local head = char:FindFirstChild("Head") or GetTargetPart(char)
            if head then
                local screenPos, onScreen = ProjectToScreen(head.Position)

                if onScreen and screenPos then
                    local distance = (
                        Vector2.new(screenPos.X, screenPos.Y) - mousePos
                    ).Magnitude

                    if distance < closestDist then
                        closestDist = distance
                        closest = char
                    end
                end
            end
        end
    end

    return closest
end

local AimLoopRunning = false

local function AimLoop()
    if AimLoopRunning then return end
    AimLoopRunning = true

    while not UIClosed do
        RunService.RenderStepped:Wait()

        if not State.Aim.Enabled then
            TargetData.Current = nil
            TargetData.Position = nil
            break
        end

        local target = GetClosestTarget()
        local myChar = LocalPlayer.Character

        if target and myChar then
            local targetPosition = GetHeadPosition(target)
            local myRoot = GetTargetPart(myChar)
            local screenPos, onScreen = ProjectToScreen(targetPosition)

            TargetData.Current = target
            TargetData.Position = targetPosition
            TargetData.Visible = onScreen

            if myRoot then
                TargetData.Distance = GetDistance(myRoot.Position, targetPosition)
            end

            if screenPos then
                local mousePos = Vector2.new(Mouse.X, Mouse.Y)
                TargetData.Angle = (
                    Vector2.new(screenPos.X, screenPos.Y) - mousePos
                ).Magnitude
            end

            -- Mantém o comportamento que já existia no script.
            local camera = GetCamera()

            if State.Aim.Silent and camera then
                local tool = myChar:FindFirstChildOfClass("Tool")
                if tool then
                    local direction = (targetPosition - camera.CFrame.Position).Unit
                    camera.CFrame = CFrame.new(
                        camera.CFrame.Position,
                        camera.CFrame.Position + direction
                    )
                end
            elseif State.Aim.Assist and screenPos and onScreen then
                local mousePos = Vector2.new(Mouse.X, Mouse.Y)
                local targetScreen = Vector2.new(screenPos.X, screenPos.Y)
                local diff = targetScreen - mousePos
                local strength = State.Aim.Strength * State.Aim.Smoothing
                local newMousePos = mousePos + diff * strength

                pcall(function()
                    Mouse.X = newMousePos.X
                    Mouse.Y = newMousePos.Y
                end)
            end
        else
            TargetData.Current = nil
            TargetData.Position = nil
            TargetData.Visible = false
        end
    end

    AimLoopRunning = false
end

local AutoShootRunning = false

local function AutoShootLoop()
    if AutoShootRunning then return end
    AutoShootRunning = true

    while not UIClosed and State.Aim.AutoShoot do
        task.wait(0.1)

        if State.Aim.Enabled and TargetData.Current then
            local char = LocalPlayer.Character
            local tool = char and char:FindFirstChildOfClass("Tool")

            if tool then
                pcall(function()
                    tool:Activate()
                    task.wait(0.05)
                    tool:Deactivate()
                end)
            end
        end
    end

    AutoShootRunning = false
end

-- ============================================================
-- CLEANUP
-- ============================================================

local function Cleanup(skipWindow)
    UIClosed = true
    DisconnectAll()

    for char in pairs(ESPObjects) do
        RemoveESP(char)
    end

    ClearTracers()
    DestroyNamedGui("CAT_EMPIRE_Tracers")
    DestroyNamedGui("FOVCircle")

    TargetData.Current = nil
    TargetData.Position = nil

    if WindowRef and not skipWindow then
        pcall(function()
            WindowRef:Destroy()
        end)
    end

    WindowRef = nil
end

-- ============================================================
-- UI
-- ============================================================

local function CreateUI()
    local Window = Fluent:CreateWindow({
        Title = "CAT EMPIRE",
        SubTitle = "",
        TabWidth = 112,
        Size = UDim2.fromOffset(590, 390),
        Acrylic = false,
        Animated = false,
        Theme = "CAT EMPIRE",
        MinimizeKey = Enum.KeyCode.LeftControl,
        ScreenGuiName = "CAT_EMPIRE",
    })

    WindowRef = Window

    local Tabs = {
        Combat = Window:AddTab({Title = "Combat", Icon = "crosshair"}),
        Visuals = Window:AddTab({Title = "Visuals", Icon = "eye"}),
        Exploits = Window:AddTab({Title = "Exploits", Icon = "flask-conical"}),
        Cloud = Window:AddTab({Title = "Cloud", Icon = "cloud"}),
        Config = Window:AddTab({Title = "Config", Icon = "settings"}),
    }

    -- COMBAT
    local combatGrid = Tabs.Combat:AddGroup({Columns = 2, Gap = 8})
    local combatLeft = combatGrid:AddElement()
    local combatRight = combatGrid:AddElement()

    combatLeft:AddSection("Aimbot")
    combatLeft:AddToggle("AimbotEnabled", {
        Title = "Aimbot",
        Default = false,
    })

    Fluent.Options.AimbotEnabled:OnChanged(function(value)
        State.Aim.Enabled = value

        if value then
            task.spawn(AimLoop)
        else
            TargetData.Current = nil
            TargetData.Position = nil
        end
    end)

    combatLeft:AddToggle("AimAssist", {
        Title = "Aim Assist",
        Default = false,
    })

    Fluent.Options.AimAssist:OnChanged(function(value)
        State.Aim.Assist = value

        if value and Fluent.Options.SilentAim then
            State.Aim.Silent = false
            Fluent.Options.SilentAim:SetValue(false)
        end
    end)

    combatLeft:AddSlider("AimFOV", {
        Title = "Aim FOV",
        Min = 50,
        Max = 500,
        Default = 200,
        Rounding = 0,
    })

    Fluent.Options.AimFOV:OnChanged(function(value)
        State.Aim.Radius = value
    end)

    combatLeft:AddSection("Smoothing")

    combatLeft:AddSlider("AimStrength", {
        Title = "Aim Strength",
        Min = 0.1,
        Max = 1,
        Default = 0.5,
        Rounding = 2,
    })

    Fluent.Options.AimStrength:OnChanged(function(value)
        State.Aim.Strength = value
    end)

    combatLeft:AddSlider("AimSmoothing", {
        Title = "Smooth",
        Min = 0.1,
        Max = 1,
        Default = 0.35,
        Rounding = 2,
    })

    Fluent.Options.AimSmoothing:OnChanged(function(value)
        State.Aim.Smoothing = value
    end)

    combatRight:AddSection("Silent Aim / Trigger")

    combatRight:AddToggle("SilentAim", {
        Title = "Silent Aim",
        Default = false,
    })

    Fluent.Options.SilentAim:OnChanged(function(value)
        State.Aim.Silent = value

        if value and Fluent.Options.AimAssist then
            State.Aim.Assist = false
            Fluent.Options.AimAssist:SetValue(false)
        end
    end)

    combatRight:AddToggle("AutoShoot", {
        Title = "Trigger / Auto Shoot",
        Default = false,
    })

    Fluent.Options.AutoShoot:OnChanged(function(value)
        State.Aim.AutoShoot = value
        if value then
            task.spawn(AutoShootLoop)
        end
    end)

    combatRight:AddSection("Target Filters")

    combatRight:AddToggle("CombatTeamCheck", {
        Title = "Team Check",
        Default = true,
    })

    Fluent.Options.CombatTeamCheck:OnChanged(function(value)
        State.ESP.TeamCheck = value

        if Fluent.Options.TeamCheck and Fluent.Options.TeamCheck.Value ~= value then
            Fluent.Options.TeamCheck:SetValue(value)
        end
    end)

    -- VISUALS
    local visualGrid = Tabs.Visuals:AddGroup({Columns = 2, Gap = 8})
    local visualLeft = visualGrid:AddElement()
    local visualRight = visualGrid:AddElement()

    visualLeft:AddSection("ESP")

    visualLeft:AddToggle("ESPEnabled", {
        Title = "ESP Enabled",
        Default = false,
    })

    Fluent.Options.ESPEnabled:OnChanged(function(value)
        State.ESP.Enabled = value

        if not value then
            for char in pairs(ESPObjects) do
                RemoveESP(char)
            end
            ClearTracers()
        else
            UpdateESP()
        end
    end)

    visualLeft:AddToggle("ESPHighlight", {
        Title = "Highlight",
        Default = true,
    })

    Fluent.Options.ESPHighlight:OnChanged(function(value)
        State.ESP.Highlight = value
        UpdateESP()
    end)

    visualLeft:AddToggle("ESPDistance", {
        Title = "Distance",
        Default = true,
    })

    Fluent.Options.ESPDistance:OnChanged(function(value)
        State.ESP.Distance = value
        UpdateESP()
    end)

    visualLeft:AddToggle("TeamCheck", {
        Title = "Team Check",
        Default = true,
    })

    Fluent.Options.TeamCheck:OnChanged(function(value)
        State.ESP.TeamCheck = value

        if Fluent.Options.CombatTeamCheck
            and Fluent.Options.CombatTeamCheck.Value ~= value
        then
            Fluent.Options.CombatTeamCheck:SetValue(value)
        end

        UpdateESP()
        UpdateTracers()
    end)

    visualRight:AddSection("ESP Lines")

    visualRight:AddToggle("ESPTracers", {
        Title = "Tracers",
        Default = false,
    })

    Fluent.Options.ESPTracers:OnChanged(function(value)
        State.ESP.Tracers = value

        if value then
            UpdateTracers()
        else
            ClearTracers()
        end
    end)

    visualRight:AddDropdown("TracerOrigin", {
        Title = "Origin",
        Values = {"Bottom Center", "Center", "Bottom"},
        Default = 1,
    })

    Fluent.Options.TracerOrigin:OnChanged(function(value)
        if value == "Bottom Center" then
            State.Visual.TracerOrigin = "BottomCenter"
        else
            State.Visual.TracerOrigin = value
        end
    end)

    visualRight:AddSection("FOV")

    visualRight:AddToggle("FOVCircle", {
        Title = "Draw FOV",
        Default = false,
    })

    Fluent.Options.FOVCircle:OnChanged(function(value)
        State.Visual.FOVCircle = value
        UpdateFOVCircle()
    end)

    visualRight:AddSlider("FOVRadius", {
        Title = "FOV Radius",
        Min = 30,
        Max = 500,
        Default = 200,
        Rounding = 0,
    })

    Fluent.Options.FOVRadius:OnChanged(function(value)
        State.Visual.FOVRadius = value
        UpdateFOVCircle()
    end)

    visualRight:AddSlider("CameraFOV", {
        Title = "Camera FOV",
        Min = 40,
        Max = 120,
        Default = 70,
        Rounding = 0,
    })

    Fluent.Options.CameraFOV:OnChanged(function(value)
        State.Visual.CameraFOV = value
        FOVController.SetBase(value)
    end)

    -- EXPLOITS
    Tabs.Exploits:AddSection("Camera")
    Tabs.Exploits:AddButton({
        Title = "Toggle Third Person",
        Callback = function()
            ThirdPerson.Toggle()
        end,
    })

    -- CLOUD
    Tabs.Cloud:AddSection("CAT EMPIRE")
    Tabs.Cloud:AddParagraph({
        Title = "Cloud",
        Content = "Interface slot reserved for profiles/configurations.",
    })

    -- CONFIG
    local configGrid = Tabs.Config:AddGroup({Columns = 2, Gap = 8})
    local configLeft = configGrid:AddElement()
    local configRight = configGrid:AddElement()

    configLeft:AddSection("Interface")
    configLeft:AddParagraph({
        Title = "Hotkey",
        Content = "Left Control • minimize / restore",
    })

    configLeft:AddButton({
        Title = "Unload CAT EMPIRE",
        Callback = function()
            Cleanup()
        end,
    })

    configRight:AddSection("Diagnostics")

    local targetLabel = configRight:AddLabel("Target: None")
    local distanceLabel = configRight:AddLabel("Distance: --")
    local visibleLabel = configRight:AddLabel("Visible: --")
    local espCountLabel = configRight:AddLabel("ESP Objects: 0")
    local tracerCountLabel = configRight:AddLabel("Tracers: 0")

    task.spawn(function()
        while not UIClosed do
            task.wait(0.5)

            if TargetData.Current then
                targetLabel:SetText("Target: " .. TargetData.Current.Name)
                distanceLabel:SetText(
                    "Distance: " .. string.format("%.0f", TargetData.Distance)
                )
                visibleLabel:SetText("Visible: " .. tostring(TargetData.Visible))
            else
                targetLabel:SetText("Target: None")
                distanceLabel:SetText("Distance: --")
                visibleLabel:SetText("Visible: --")
            end

            local espCount = 0
            for _ in pairs(ESPObjects) do
                espCount += 1
            end

            local tracerCount = 0
            for _ in pairs(TracerObjects) do
                tracerCount += 1
            end

            espCountLabel:SetText("ESP Objects: " .. espCount)
            tracerCountLabel:SetText("Tracers: " .. tracerCount)
        end
    end)
end

local function SetupConnections()
    table.insert(Connections, RunService.RenderStepped:Connect(function()
        if UIClosed then return end

        UpdateESP()
        UpdateTracers()
    end))

    table.insert(Connections, LocalPlayer.CharacterAdded:Connect(function()
        TargetData.Current = nil
        TargetData.Position = nil

        task.defer(function()
            UpdateESP()
            UpdateTracers()
        end)
    end))

    local characters = workspace:FindFirstChild("Characters")
    if characters then
        table.insert(Connections, characters.ChildRemoved:Connect(function(child)
            RemoveESP(child)
            RemoveTracer(child)
        end))
    end
end

local function Init()
    -- Remove restos de uma execução anterior.
    local env = (getgenv and getgenv()) or _G

    if type(env.CAT_EMPIRE_CLEANUP) == "function" then
        pcall(env.CAT_EMPIRE_CLEANUP)
    end

    UIClosed = false

    CreateUI()
    SetupConnections()

    env.CAT_EMPIRE_CLEANUP = function()
        Cleanup(true)
    end

    Fluent:Notify({
        Title = "CAT EMPIRE",
        Content = "ESP system fixed",
        Duration = 3,
    })
end

Init()
