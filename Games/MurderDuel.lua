-- ============================================================
-- MURDER DUELS | FPS EXPLOIT HUB v3.0
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Extensions = ReplicatedStorage:WaitForChild("Extensions")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = ReplicatedStorage:WaitForChild("Util")

local FOVController = require(Shared:WaitForChild("FOVController"))
local ThirdPerson = require(Shared:WaitForChild("ThirdPerson"))
local RayCast = require(Util:WaitForChild("RayCast"))

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local State = {
    ESP = {
        Enabled = false,
        Highlight = false,
        Distance = false,
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
    },
    Visual = {
        FOVCircle = false,
        FOVRadius = 200,
        CameraFOV = 70,
        TracerOrigin = "BottomCenter",
    },
    UI = {
        Visible = true,
        Minimized = false,
    }
}

local ESPObjects = {}
local TracerObjects = {}
local Connections = {}
local Loops = {}
local WindowRef = nil
local UIClosed = false
local TargetData = {
    Current = nil,
    Position = nil,
    Distance = 0,
    Angle = 0,
    Visible = false,
}

local function Cleanup()
    UIClosed = true
    for _, conn in pairs(Connections) do
        pcall(function() conn:Disconnect() end)
    end
    Connections = {}
    for _, loop in pairs(Loops) do
        loop = false
    end
    Loops = {}
    for char, data in pairs(ESPObjects) do
        pcall(function()
            if data.Highlight then data.Highlight:Destroy() end
            if data.Distance then data.Distance:Destroy() end
        end)
    end
    ESPObjects = {}
    for _, tracer in pairs(TracerObjects) do
        pcall(function() tracer:Destroy() end)
    end
    TracerObjects = {}
    if WindowRef then
        pcall(function() WindowRef:Destroy() end)
        WindowRef = nil
    end
    TargetData.Current = nil
    TargetData.Position = nil
end

local function GetCharacters()
    local chars = {}
    local Characters = workspace:FindFirstChild("Characters")
    if Characters then
        for _, child in pairs(Characters:GetChildren()) do
            if child:IsA("Model") and child ~= LocalPlayer.Character then
                table.insert(chars, child)
            end
        end
    end
    return chars
end

local function IsEnemy(char)
    if not char then return false end
    if char == LocalPlayer.Character then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    if State.ESP.TeamCheck then
        local myChar = LocalPlayer.Character
        if myChar then
            local mySide = myChar:GetAttribute("MatchSide")
            local theirSide = char:GetAttribute("MatchSide")
            if mySide and theirSide and mySide == theirSide then
                return false
            end
        end
    end
    return true
end

local function GetHeadPosition(char)
    local head = char:FindFirstChild("Head")
    if head then return head.Position end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then return humanoid.TargetPoint end
    return char:GetPivot().Position
end

local function GetDistance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

local function IsOnScreen(position)
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    return onScreen, screenPos
end

local function GetClosestTarget()
    local closest = nil
    local closestDist = State.Aim.Radius
    local closestAngle = 999
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    
    for _, char in pairs(GetCharacters()) do
        if IsEnemy(char) then
            local head = char:FindFirstChild("Head")
            if head then
                local screenPos, onScreen = IsOnScreen(head.Position)
                if onScreen then
                    local screenVec = Vector2.new(screenPos.X, screenPos.Y)
                    local dist = (screenVec - mousePos).Magnitude
                    if dist < closestDist then
                        local angle = math.deg(math.atan2(screenPos.Y - mousePos.Y, screenPos.X - mousePos.X))
                        if math.abs(angle) < closestAngle then
                            closestDist = dist
                            closestAngle = math.abs(angle)
                            closest = char
                        end
                    end
                end
            end
        end
    end
    
    return closest
end

local function CreateESP(char)
    if ESPObjects[char] then return end
    local data = {}
    
    if State.ESP.Highlight then
        local highlight = Instance.new("Highlight")
        highlight.FillColor = Color3.fromRGB(255, 0, 0)
        highlight.FillTransparency = 0.5
        highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
        highlight.OutlineTransparency = 0
        highlight.Parent = char
        data.Highlight = highlight
    end
    
    if State.ESP.Distance then
        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(0, 100, 0, 30)
        billboard.StudsOffset = Vector3.new(0, 2.5, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = char
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(255, 0, 0)
        label.TextStrokeTransparency = 0
        label.TextSize = 16
        label.Font = Enum.Font.GothamBold
        label.Parent = billboard
        
        data.Distance = billboard
        data.Label = label
    end
    
    ESPObjects[char] = data
end

local function RemoveESP(char)
    local data = ESPObjects[char]
    if data then
        pcall(function()
            if data.Highlight then data.Highlight:Destroy() end
            if data.Distance then data.Distance:Destroy() end
        end)
        ESPObjects[char] = nil
    end
end

local function UpdateESP()
    if not State.ESP.Enabled then
        for char in pairs(ESPObjects) do
            RemoveESP(char)
        end
        return
    end
    
    local currentChars = {}
    for _, char in pairs(GetCharacters()) do
        currentChars[char] = true
        if IsEnemy(char) then
            if not ESPObjects[char] then
                CreateESP(char)
            end
            local data = ESPObjects[char]
            if data and data.Label then
                local dist = GetDistance(char:GetPivot().Position, LocalPlayer.Character:GetPivot().Position)
                data.Label.Text = string.format("%.0f", dist)
            end
        else
            if ESPObjects[char] then
                RemoveESP(char)
            end
        end
    end
    
    for char in pairs(ESPObjects) do
        if not currentChars[char] then
            RemoveESP(char)
        end
    end
end

local function CreateTracer(char)
    if TracerObjects[char] then return end
    
    local screenGui = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("Tracers")
    if not screenGui then
        screenGui = Instance.new("ScreenGui")
        screenGui.Name = "Tracers"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    
    local line = Instance.new("Frame")
    line.Name = "Tracer_" .. char.Name
    line.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    line.BackgroundTransparency = 0.3
    line.BorderSizePixel = 0
    line.Parent = screenGui
    line.ZIndex = 999
    line.Visible = true
    
    TracerObjects[char] = line
end

local function RemoveTracer(char)
    local line = TracerObjects[char]
    if line then
        pcall(function() line:Destroy() end)
        TracerObjects[char] = nil
    end
end

local function UpdateTracers()
    if not State.ESP.Tracers then
        for char in pairs(TracerObjects) do
            RemoveTracer(char)
        end
        return
    end
    
    local viewportX = Camera.ViewportSize.X
    local viewportY = Camera.ViewportSize.Y
    local originX = viewportX / 2
    local originY = viewportY * 0.85
    
    if State.Visual.TracerOrigin == "Center" then
        originX = viewportX / 2
        originY = viewportY / 2
    elseif State.Visual.TracerOrigin == "Bottom" then
        originX = viewportX / 2
        originY = viewportY * 0.95
    end
    
    local currentChars = {}
    for _, char in pairs(GetCharacters()) do
        currentChars[char] = true
        if IsEnemy(char) then
            if not TracerObjects[char] then
                CreateTracer(char)
            end
            local line = TracerObjects[char]
            local headPos = GetHeadPosition(char)
            local screenPos, onScreen = IsOnScreen(headPos)
            
            if onScreen then
                local dx = screenPos.X - originX
                local dy = screenPos.Y - originY
                local length = math.sqrt(dx * dx + dy * dy)
                local angle = math.atan2(dy, dx)
                
                line.Size = UDim2.new(0, length, 0, 2)
                line.Position = UDim2.new(0, originX, 0, originY - 1)
                line.Rotation = math.deg(angle)
                line.Visible = true
                line.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
                line.BackgroundTransparency = 0.3
            else
                line.Visible = false
            end
        else
            if TracerObjects[char] then
                RemoveTracer(char)
            end
        end
    end
    
    for char in pairs(TracerObjects) do
        if not currentChars[char] then
            RemoveTracer(char)
        end
    end
end

local function CreateFOVCircle()
    local radius = State.Visual.FOVRadius
    
    local gui = Instance.new("ScreenGui")
    gui.Name = "FOVCircle"
    gui.ResetOnSpawn = false
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, radius * 2, 0, radius * 2)
    frame.Position = UDim2.new(0.5, -radius, 0.5, -radius)
    frame.BackgroundTransparency = 1
    frame.Parent = gui
    
    local circle = Instance.new("ImageLabel")
    circle.Size = UDim2.new(1, 0, 1, 0)
    circle.Position = UDim2.new(0, 0, 0, 0)
    circle.BackgroundTransparency = 1
    circle.Image = "rbxassetid://3570695787"
    circle.ImageColor3 = Color3.fromRGB(0, 255, 255)
    circle.ImageTransparency = 0.3
    circle.Parent = frame
    
    return gui
end

local function UpdateFOVCircle()
    if State.Visual.FOVCircle then
        local existing = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("FOVCircle")
        if existing then existing:Destroy() end
        CreateFOVCircle()
    else
        local existing = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("FOVCircle")
        if existing then existing:Destroy() end
    end
end

local function AimLoop()
    while not UIClosed and State.Aim.Enabled do
        task.wait()
        local target = GetClosestTarget()
        if target then
            TargetData.Current = target
            TargetData.Position = GetHeadPosition(target)
            TargetData.Distance = GetDistance(LocalPlayer.Character:GetPivot().Position, TargetData.Position)
            
            local screenPos, onScreen = IsOnScreen(TargetData.Position)
            local mousePos = Vector2.new(Mouse.X, Mouse.Y)
            TargetData.Angle = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
            TargetData.Visible = onScreen
            
            if State.Aim.Silent then
                local tool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
                if tool then
                    local direction = (TargetData.Position - Camera.CFrame.Position).Unit
                    Camera.CFrame = CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + direction)
                end
            elseif State.Aim.Assist then
                local screenPos2, onScreen2 = IsOnScreen(TargetData.Position)
                if onScreen2 then
                    local targetScreen = Vector2.new(screenPos2.X, screenPos2.Y)
                    local mousePos2 = Vector2.new(Mouse.X, Mouse.Y)
                    local diff = targetScreen - mousePos2
                    local strength = State.Aim.Strength * State.Aim.Smoothing
                    local newMousePos = mousePos2 + diff * strength
                    Mouse.X = newMousePos.X
                    Mouse.Y = newMousePos.Y
                end
            end
        else
            TargetData.Current = nil
            TargetData.Position = nil
        end
    end
end

local function AutoShootLoop()
    while not UIClosed do
        task.wait(0.1)
        if State.Aim.Enabled and TargetData.Current then
            local tool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
            if tool then
                pcall(function()
                    tool:Activate()
                    task.wait(0.05)
                    tool:Deactivate()
                end)
            end
        end
    end
end

local function MainLoop()
    while not UIClosed do
        task.wait(0.1)
        if State.ESP.Enabled then
            UpdateESP()
        end
        if State.ESP.Tracers then
            UpdateTracers()
        end
    end
end

local FluentWindow
local function CreateUI()
    FluentWindow = Fluent:CreateWindow({
        Title = "MurderDuels",
        SubTitle = "FPS Exploit v3.0",
        TabWidth = 160,
        Size = UDim2.fromOffset(620, 480),
        Acrylic = true,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightControl,
    })
    WindowRef = FluentWindow
    
    local Tabs = {
        ESP = FluentWindow:AddTab({ Title = "ESP", Icon = "eye" }),
        Aim = FluentWindow:AddTab({ Title = "Aim", Icon = "crosshair" }),
        Visual = FluentWindow:AddTab({ Title = "Visual", Icon = "circle" }),
        Diagnostics = FluentWindow:AddTab({ Title = "Debug", Icon = "bug" }),
    }
    
    Tabs.ESP:AddSection("ESP Geral")
    
    Tabs.ESP:AddToggle("ESPEnabled", {
        Title = "ESP Ativado",
        Default = false,
    })
    Fluent.Options.ESPEnabled:OnChanged(function(v)
        State.ESP.Enabled = v
        if not v then
            for char in pairs(ESPObjects) do
                RemoveESP(char)
            end
            for char in pairs(TracerObjects) do
                RemoveTracer(char)
            end
        end
    end)
    
    Tabs.ESP:AddToggle("ESPHighlight", {
        Title = "Highlight",
        Default = true,
    })
    Fluent.Options.ESPHighlight:OnChanged(function(v)
        State.ESP.Highlight = v
        for char in pairs(ESPObjects) do
            RemoveESP(char)
        end
        if State.ESP.Enabled then
            for _, char in pairs(GetCharacters()) do
                if IsEnemy(char) then
                    CreateESP(char)
                end
            end
        end
    end)
    
    Tabs.ESP:AddToggle("ESPDistance", {
        Title = "Distância",
        Default = true,
    })
    Fluent.Options.ESPDistance:OnChanged(function(v)
        State.ESP.Distance = v
        for char in pairs(ESPObjects) do
            RemoveESP(char)
        end
        if State.ESP.Enabled then
            for _, char in pairs(GetCharacters()) do
                if IsEnemy(char) then
                    CreateESP(char)
                end
            end
        end
    end)
    
    Tabs.ESP:AddSection("ESP Lines")
    
    Tabs.ESP:AddToggle("ESPTracers", {
        Title = "Tracers",
        Default = false,
    })
    Fluent.Options.ESPTracers:OnChanged(function(v)
        State.ESP.Tracers = v
        if not v then
            for char in pairs(TracerObjects) do
                RemoveTracer(char)
            end
        end
    end)
    
    Tabs.ESP:AddDropdown("TracerOrigin", {
        Title = "Origem",
        Values = {"Center", "BottomCenter", "Bottom"},
        Default = 2,
    })
    Fluent.Options.TracerOrigin:OnChanged(function(v)
        State.Visual.TracerOrigin = v
    end)
    
    Tabs.ESP:AddSection("Filtros")
    
    Tabs.ESP:AddToggle("TeamCheck", {
        Title = "Team Check",
        Default = true,
    })
    Fluent.Options.TeamCheck:OnChanged(function(v)
        State.ESP.TeamCheck = v
    end)
    
    Tabs.Aim:AddSection("Aimbot")
    
    Tabs.Aim:AddToggle("AimbotEnabled", {
        Title = "Aimbot Ativado",
        Default = false,
    })
    Fluent.Options.AimbotEnabled:OnChanged(function(v)
        State.Aim.Enabled = v
        if v then
            task.spawn(AimLoop)
        end
    end)
    
    Tabs.Aim:AddToggle("SilentAim", {
        Title = "Silent Aim",
        Default = false,
    })
    Fluent.Options.SilentAim:OnChanged(function(v)
        State.Aim.Silent = v
        if v then
            State.Aim.Assist = false
            Fluent.Options.AimAssist:SetValue(false)
        end
    end)
    
    Tabs.Aim:AddToggle("AimAssist", {
        Title = "Aim Assist",
        Default = false,
    })
    Fluent.Options.AimAssist:OnChanged(function(v)
        State.Aim.Assist = v
        if v then
            State.Aim.Silent = false
            Fluent.Options.SilentAim:SetValue(false)
        end
    end)
    
    Tabs.Aim:AddSlider("AimStrength", {
        Title = "Força",
        Min = 0.1,
        Max = 1,
        Default = 0.5,
        Rounding = 2,
    })
    Fluent.Options.AimStrength:OnChanged(function(v)
        State.Aim.Strength = v
    end)
    
    Tabs.Aim:AddSlider("AimSmoothing", {
        Title = "Suavidade",
        Min = 0.1,
        Max = 1,
        Default = 0.35,
        Rounding = 2,
    })
    Fluent.Options.AimSmoothing:OnChanged(function(v)
        State.Aim.Smoothing = v
    end)
    
    Tabs.Aim:AddSlider("AimFOV", {
        Title = "FOV do Aimbot",
        Min = 50,
        Max = 500,
        Default = 200,
        Rounding = 0,
    })
    Fluent.Options.AimFOV:OnChanged(function(v)
        State.Aim.Radius = v
    end)
    
    Tabs.Aim:AddSection("Auto")
    
    Tabs.Aim:AddToggle("AutoShoot", {
        Title = "Auto Shoot",
        Default = false,
    })
    Fluent.Options.AutoShoot:OnChanged(function(v)
        if v then
            task.spawn(AutoShootLoop)
        end
    end)
    
    Tabs.Visual:AddSection("FOV Circle")
    
    Tabs.Visual:AddToggle("FOVCircle", {
        Title = "Mostrar Círculo",
        Default = false,
    })
    Fluent.Options.FOVCircle:OnChanged(function(v)
        State.Visual.FOVCircle = v
        UpdateFOVCircle()
    end)
    
    Tabs.Visual:AddSlider("FOVRadius", {
        Title = "Raio",
        Min = 30,
        Max = 500,
        Default = 200,
        Rounding = 0,
    })
    Fluent.Options.FOVRadius:OnChanged(function(v)
        State.Visual.FOVRadius = v
        UpdateFOVCircle()
    end)
    
    Tabs.Visual:AddSection("Câmera")
    
    Tabs.Visual:AddSlider("CameraFOV", {
        Title = "FOV da Câmera",
        Min = 40,
        Max = 120,
        Default = 70,
        Rounding = 0,
    })
    Fluent.Options.CameraFOV:OnChanged(function(v)
        State.Visual.CameraFOV = v
        FOVController.SetBase(v)
    end)
    
    Tabs.Visual:AddButton({
        Title = "Toggle Third Person",
        Callback = function()
            ThirdPerson.Toggle()
        end,
    })
    
    Tabs.Diagnostics:AddSection("Status")
    
    local targetLabel = Tabs.Diagnostics:AddLabel("Target: None")
    local distanceLabel = Tabs.Diagnostics:AddLabel("Distance: --")
    local angleLabel = Tabs.Diagnostics:AddLabel("Angle: --")
    local visibleLabel = Tabs.Diagnostics:AddLabel("Visible: --")
    local espCountLabel = Tabs.Diagnostics:AddLabel("ESP Objects: 0")
    local tracerCountLabel = Tabs.Diagnostics:AddLabel("Tracers: 0")
    
    task.spawn(function()
        while not UIClosed do
            task.wait(0.5)
            if TargetData.Current then
                targetLabel:SetText("Target: " .. TargetData.Current.Name)
                distanceLabel:SetText("Distance: " .. string.format("%.0f", TargetData.Distance))
                angleLabel:SetText("Angle: " .. string.format("%.1f", TargetData.Angle))
                visibleLabel:SetText("Visible: " .. tostring(TargetData.Visible))
            else
                targetLabel:SetText("Target: None")
                distanceLabel:SetText("Distance: --")
                angleLabel:SetText("Angle: --")
                visibleLabel:SetText("Visible: --")
            end
            
            local espCount = 0
            for _ in pairs(ESPObjects) do espCount = espCount + 1 end
            espCountLabel:SetText("ESP Objects: " .. espCount)
            
            local tracerCount = 0
            for _ in pairs(TracerObjects) do tracerCount = tracerCount + 1 end
            tracerCountLabel:SetText("Tracers: " .. tracerCount)
        end
    end)
    
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -35, 0, 5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    closeBtn.BackgroundTransparency = 0.3
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 20
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.BorderSizePixel = 0
    
    local success, gui = pcall(function() return FluentWindow.Gui end)
    if success and gui then
        closeBtn.Parent = gui
        closeBtn.MouseButton1Click:Connect(Cleanup)
        closeBtn.MouseEnter:Connect(function() closeBtn.BackgroundTransparency = 0 end)
        closeBtn.MouseLeave:Connect(function() closeBtn.BackgroundTransparency = 0.3 end)
    end
end

local function SetupConnections()
    table.insert(Connections, RunService.RenderStepped:Connect(function()
        if not UIClosed then
            if State.ESP.Enabled then
                UpdateESP()
            end
            if State.ESP.Tracers then
                UpdateTracers()
            end
        end
    end))
    
    table.insert(Connections, LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.5)
        TargetData.Current = nil
        TargetData.Position = nil
    end))
    
    table.insert(Connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.RightControl then
            if WindowRef and WindowRef.Visible then
                if State.UI.Minimized then
                    State.UI.Minimized = false
                    WindowRef.Visible = true
                else
                    State.UI.Minimized = true
                    WindowRef.Visible = false
                end
            end
        end
    end))
end

local function Init()
    Cleanup()
    UIClosed = false
    CreateUI()
    SetupConnections()
    task.spawn(MainLoop)
    
    Fluent:Notify({
        Title = "MurderDuels",
        Content = "FPS Exploit v3.0 carregado!",
        Duration = 4,
    })
end

local function ToggleUI()
    if WindowRef and WindowRef.Visible then
        Cleanup()
    else
        Init()
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        ToggleUI()
    end
end)

Init()
