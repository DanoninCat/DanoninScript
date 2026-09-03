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

local AimAssistController = require(Extensions:WaitForChild("AimAssistController"))
local TargetSelector = require(Extensions:WaitForChild("TargetSelector"))
local AimAdjuster = require(Extensions:WaitForChild("AimAdjuster"))
local AimMagnetism = require(Extensions:WaitForChild("AimMagnetism"))
local InputCategorizer = require(Extensions:WaitForChild("InputCategorizer"))
local AimAssistEnum = require(Extensions:WaitForChild("AimAssistEnum"))
local FOVController = require(Shared:WaitForChild("FOVController"))
local KnifeFlight = require(Shared:WaitForChild("KnifeFlight"))
local ThirdPerson = require(Shared:WaitForChild("ThirdPerson"))
local CrosshairSettings = require(Shared:WaitForChild("CrosshairSettings"))
local ShotPath = require(Util:WaitForChild("ShotPath"))
local RayCast = require(Util:WaitForChild("RayCast"))

-- ============================================================
-- [STATE - DESACOPLADO POR FUNCIONALIDADE]
-- ============================================================
local STATE = {
    ESP = {
        Enabled = false,
        Highlight = false,
        Distance = false,
        Tracers = false,
        TeamCheck = true,
        AliveCheck = true,
        VisibilityCheck = false,
    },
    Target = {
        Current = nil,
        Position = nil,
        Distance = 0,
        Angle = 0,
        IsVisible = false,
        IsValid = false,
    },
    Camera = {
        Controller = nil,
        Locked = false,
        Smoothing = 0.5,
    },
    Aim = {
        Enabled = false,
        Silent = false,
        Assist = false,
        Strength = 0.5,
        Radius = 200,
        Controller = nil,
    },
    Visual = {
        FOVCircle = false,
        FOVRadius = 200,
        CameraFOV = 70,
        TracerOrigin = "BottomCenter",
    },
    Combat = {
        AutoShoot = false,
        KnifePrediction = false,
        ShootCooldown = 0,
        LastShot = 0,
    },
    UI = {
        Visible = true,
        WindowRef = nil,
        Closed = false,
    }
}

-- ============================================================
-- [CLEANUP MANAGER]
-- ============================================================
local Connections = {}
local ESP_Objects = {}
local ESPLineObjects = {}
local fovCircleGui = nil

local function AddConnection(conn)
    table.insert(Connections, conn)
    return conn
end

local function CleanupAll()
    STATE.UI.Closed = true
    
    for _, conn in pairs(Connections) do
        pcall(function() conn:Disconnect() end)
    end
    Connections = {}
    
    if STATE.Aim.Controller then
        pcall(function() STATE.Aim.Controller:disable() end)
        STATE.Aim.Controller = nil
    end
    
    if STATE.Camera.Controller then
        pcall(function() STATE.Camera.Controller:disable() end)
        STATE.Camera.Controller = nil
    end
    
    for char, esp in pairs(ESP_Objects) do
        pcall(function()
            esp.highlight:Destroy()
            esp.billboard:Destroy()
        end)
    end
    ESP_Objects = {}
    
    for char, line in pairs(ESPLineObjects) do
        pcall(function() line:Destroy() end)
    end
    ESPLineObjects = {}
    
    if fovCircleGui then
        pcall(function() fovCircleGui:Destroy() end)
        fovCircleGui = nil
    end
    
    pcall(function()
        local gui = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("ESP_Lines")
        if gui then gui:Destroy() end
        local fov = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("FOVCircle")
        if fov then fov:Destroy() end
    end)
    
    if STATE.UI.WindowRef then
        pcall(function() STATE.UI.WindowRef:Destroy() end)
        STATE.UI.WindowRef = nil
    end
    
    STATE.Target.Current = nil
    STATE.Target.Position = nil
    STATE.Aim.Enabled = false
    STATE.Aim.Silent = false
    STATE.Aim.Assist = false
end

-- ============================================================
-- [TARGET PROVIDER - APENAS AQUISIÇÃO DE ALVO]
-- ============================================================
local TargetProvider = {}

function TargetProvider.GetCharacters()
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

function TargetProvider.IsEnemy(char)
    if not char then return false end
    if char == LocalPlayer.Character then return false end
    
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    if humanoid.Health <= 0 then return false end
    
    if STATE.ESP.TeamCheck then
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

function TargetProvider.IsAlive(char)
    if not char then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    return humanoid.Health > 0
end

function TargetProvider.GetHeadPosition(char)
    local head = char:FindFirstChild("Head")
    if head then return head.Position end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then return humanoid.TargetPoint end
    return char:GetPivot().Position
end

function TargetProvider.IsOnScreen(position)
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    return onScreen, screenPos
end

function TargetProvider.IsVisible(origin, targetPos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character}
    local result = workspace:Raycast(origin, (targetPos - origin).Unit * (targetPos - origin).Magnitude, params)
    return result == nil
end

function TargetProvider.GetClosestToCrosshair(maxDistance)
    local closest = nil
    local closestDist = maxDistance or 300
    local closestAngle = math.huge
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    
    for _, char in pairs(TargetProvider.GetCharacters()) do
        if TargetProvider.IsEnemy(char) and TargetProvider.IsAlive(char) then
            local headPos = TargetProvider.GetHeadPosition(char)
            local onScreen, screenPos = TargetProvider.IsOnScreen(headPos)
            
            if onScreen then
                local screenVec = Vector2.new(screenPos.X, screenPos.Y)
                local dist = (screenVec - mousePos).Magnitude
                local angle = math.deg(math.atan2(screenVec.Y - mousePos.Y, screenVec.X - mousePos.X))
                
                if dist < closestDist then
                    closestDist = dist
                    closestAngle = angle
                    closest = {
                        Character = char,
                        HeadPosition = headPos,
                        ScreenPosition = screenVec,
                        Distance = dist,
                        Angle = angle,
                        OnScreen = onScreen,
                    }
                end
            end
        end
    end
    
    return closest
end

function TargetProvider.GetBestTarget()
    local result = TargetProvider.GetClosestToCrosshair(STATE.Aim.Radius)
    
    if result then
        local origin = Camera.CFrame.Position
        local visible = TargetProvider.IsVisible(origin, result.HeadPosition)
        result.IsVisible = visible
        result.IsValid = visible and result.Distance <= STATE.Aim.Radius
        STATE.Target.Current = result
        STATE.Target.Position = result.HeadPosition
        STATE.Target.Distance = result.Distance
        STATE.Target.Angle = result.Angle
        STATE.Target.IsVisible = visible
        STATE.Target.IsValid = result.IsValid
        return result
    else
        STATE.Target.Current = nil
        STATE.Target.Position = nil
        STATE.Target.IsValid = false
        return nil
    end
end

-- ============================================================
-- [CAMERA CONTROLLER - ÚNICO DONO DA CÂMERA]
-- ============================================================
local CameraController = {}

function CameraController.Setup()
    if STATE.Camera.Controller then
        pcall(function() STATE.Camera.Controller:disable() end)
        STATE.Camera.Controller = nil
    end
    
    local controller = AimAssistController.new()
    local Characters = workspace:FindFirstChild("Characters")
    if Characters then
        controller:setCharacterFolder(Characters)
    end
    controller:setRange(STATE.Aim.Radius)
    controller:setFieldOfView(STATE.Aim.Radius)
    controller:setSortingBehavior(AimAssistEnum.AimAssistSortingBehavior.Angle)
    controller:setIgnoreLineOfSight(false)
    controller:setType(AimAssistEnum.AimAssistType.Rotational)
    controller:setMethodStrength(AimAssistEnum.AimAssistMethod.Centering, STATE.Aim.Strength)
    controller:setMethodStrength(AimAssistEnum.AimAssistMethod.Tracking, STATE.Aim.Strength * 0.5)
    controller:setMethodStrength(AimAssistEnum.AimAssistMethod.Friction, STATE.Aim.Strength * 0.3)
    
    if LocalPlayer.Character then
        controller:setSubject(LocalPlayer.Character)
    end
    
    controller:enable()
    STATE.Camera.Controller = controller
    STATE.Camera.Locked = true
end

function CameraController.Disable()
    if STATE.Camera.Controller then
        pcall(function() STATE.Camera.Controller:disable() end)
        STATE.Camera.Controller = nil
    end
    STATE.Camera.Locked = false
end

function CameraController.Update()
    if not STATE.Camera.Locked then return end
    if not STATE.Camera.Controller then return end
    
    local target = STATE.Target.Current
    if target and target.IsValid then
        if STATE.Aim.Silent then
            local origin = Camera.CFrame.Position
            local lookDir = (target.HeadPosition - origin).Unit
            Camera.CFrame = CFrame.new(origin, origin + lookDir)
        elseif STATE.Aim.Assist then
            local origin = Camera.CFrame.Position
            local currentDir = Camera.CFrame.LookVector
            local targetDir = (target.HeadPosition - origin).Unit
            local smoothed = currentDir:Lerp(targetDir, STATE.Aim.Strength * 0.5)
            Camera.CFrame = CFrame.new(origin, origin + smoothed)
        end
    end
end

-- ============================================================
-- [SILENT AIM - INDEPENDENTE]
-- ============================================================
local SilentAim = {}

function SilentAim.Enabled()
    return STATE.Aim.Enabled and STATE.Aim.Silent
end

function SilentAim.GetTarget()
    return STATE.Target.Current
end

function SilentAim.GetAimPosition()
    local target = STATE.Target.Current
    if target and target.IsValid then
        return target.HeadPosition
    end
    return nil
end

function SilentAim.ShouldHit(targetPos)
    if not targetPos then return false end
    local origin = Camera.CFrame.Position
    local direction = (targetPos - origin).Unit
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character}
    local result = workspace:Raycast(origin, direction * 1000, params)
    if result and result.Instance then
        local char = result.Instance:FindFirstAncestorOfClass("Model")
        if char and TargetProvider.IsEnemy(char) then
            return true
        end
    end
    return false
end

-- ============================================================
-- [AIM ASSIST - INDEPENDENTE]
-- ============================================================
local AimAssist = {}

function AimAssist.Enabled()
    return STATE.Aim.Enabled and STATE.Aim.Assist
end

function AimAssist.GetTarget()
    return STATE.Target.Current
end

function AimAssist.GetStrength()
    return STATE.Aim.Strength
end

function AimAssist.Apply()
    if not AimAssist.Enabled() then return end
    local target = STATE.Target.Current
    if target and target.IsValid then
        CameraController.Update()
    end
end

-- ============================================================
-- [AIMBOT - INDEPENDENTE]
-- ============================================================
local Aimbot = {}

function Aimbot.Enabled()
    return STATE.Aim.Enabled
end

function Aimbot.Loop()
    while STATE.Aim.Enabled and not STATE.UI.Closed do
        TargetProvider.GetBestTarget()
        if STATE.Aim.Silent then
            SilentAim.GetTarget()
        end
        if STATE.Aim.Assist then
            AimAssist.Apply()
        end
        task.wait()
    end
end

-- ============================================================
-- [AUTO SHOOT - INDEPENDENTE]
-- ============================================================
local AutoShoot = {}

function AutoShoot.Enabled()
    return STATE.Combat.AutoShoot
end

function AutoShoot.Loop()
    while STATE.Combat.AutoShoot and not STATE.UI.Closed do
        if STATE.Aim.Enabled then
            local target = STATE.Target.Current
            if target and target.IsValid then
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
        task.wait(0.1)
    end
end

-- ============================================================
-- [KNIFE PREDICTION - INDEPENDENTE]
-- ============================================================
local KnifePrediction = {}

function KnifePrediction.Enabled()
    return STATE.Combat.KnifePrediction
end

function KnifePrediction.GetPrediction(targetPos, origin, speed)
    speed = speed or KnifeFlight.PARAMS.THROW_SPEED
    local dist = (targetPos - origin).Magnitude
    local time = dist / speed
    local gravity = KnifeFlight.PARAMS.GRAVITY_FACTOR
    local predictedY = targetPos.Y + (0.5 * workspace.Gravity * gravity * time * time)
    return Vector3.new(targetPos.X, predictedY, targetPos.Z)
end

function KnifePrediction.Loop()
    while STATE.Combat.KnifePrediction and not STATE.UI.Closed do
        if STATE.Aim.Enabled then
            local target = STATE.Target.Current
            if target and target.IsValid and LocalPlayer.Character then
                local origin = LocalPlayer.Character:GetPivot().Position
                local predicted = KnifePrediction.GetPrediction(target.HeadPosition, origin)
                local direction = (predicted - origin).Unit
                local state = KnifeFlight.newState(origin, direction * KnifeFlight.PARAMS.THROW_SPEED, 1, false)
                STATE.Target.Predicted = predicted
                STATE.Target.KnifeState = state
            end
        end
        task.wait(0.05)
    end
end

-- ============================================================
-- [ESP - INDEPENDENTE]
-- ============================================================
local ESP = {}

function ESP.Create(char)
    if STATE.UI.Closed then return end
    if ESP_Objects[char] then return end
    
    local esp = {}
    
    if STATE.ESP.Highlight then
        local highlight = Instance.new("Highlight")
        highlight.Name = "ESP_Highlight"
        highlight.FillColor = Color3.fromRGB(255, 0, 0)
        highlight.FillTransparency = 0.5
        highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
        highlight.OutlineTransparency = 0
        highlight.Parent = char
        esp.highlight = highlight
    end
    
    if STATE.ESP.Distance then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "ESP_Distance"
        billboard.Size = UDim2.new(0, 100, 0, 30)
        billboard.StudsOffset = Vector3.new(0, 2.5, 0)
        billboard.AlwaysOnTop = true
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(255, 0, 0)
        label.TextStrokeTransparency = 0
        label.TextSize = 16
        label.Font = Enum.Font.GothamBold
        label.Parent = billboard
        
        billboard.Parent = char
        esp.billboard = billboard
        esp.label = label
    end
    
    ESP_Objects[char] = esp
end

function ESP.Update()
    if STATE.UI.Closed then return end
    if not STATE.ESP.Enabled then 
        ESP.Clear()
        return 
    end
    
    for char, esp in pairs(ESP_Objects) do
        if not char.Parent or not TargetProvider.IsAlive(char) then
            pcall(function()
                if esp.highlight then esp.highlight:Destroy() end
                if esp.billboard then esp.billboard:Destroy() end
            end)
            ESP_Objects[char] = nil
            continue
        end
        
        local isEnemy = TargetProvider.IsEnemy(char)
        if not isEnemy and STATE.ESP.TeamCheck then
            pcall(function()
                if esp.highlight then esp.highlight:Destroy() end
                if esp.billboard then esp.billboard:Destroy() end
            end)
            ESP_Objects[char] = nil
            continue
        end
        
        if esp.highlight then
            esp.highlight.FillColor = isEnemy and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 200, 0)
            esp.highlight.OutlineColor = isEnemy and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 200, 0)
        end
        
        if esp.label then
            local dist = (char:GetPivot().Position - LocalPlayer.Character:GetPivot().Position).Magnitude
            esp.label.Text = string.format("%.0f studs", dist)
            esp.label.TextColor3 = isEnemy and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 200, 0)
        end
    end
    
    for _, char in pairs(TargetProvider.GetCharacters()) do
        if TargetProvider.IsEnemy(char) and TargetProvider.IsAlive(char) then
            if not ESP_Objects[char] then
                ESP.Create(char)
            end
        end
    end
end

function ESP.Clear()
    for char, esp in pairs(ESP_Objects) do
        pcall(function()
            if esp.highlight then esp.highlight:Destroy() end
            if esp.billboard then esp.billboard:Destroy() end
        end)
    end
    ESP_Objects = {}
end

-- ============================================================
-- [ESP LINES - INDEPENDENTE]
-- ============================================================
local ESPLines = {}

function ESPLines.Create(char)
    if STATE.UI.Closed then return end
    if ESPLineObjects[char] then return end
    
    local screenGui = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("ESP_Lines") or Instance.new("ScreenGui")
    screenGui.Name = "ESP_Lines"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    
    local line = Instance.new("Frame")
    line.Name = "Line_" .. char.Name
    line.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    line.BackgroundTransparency = 0.5
    line.BorderSizePixel = 0
    line.Parent = screenGui
    line.ZIndex = 999
    
    ESPLineObjects[char] = line
end

function ESPLines.Update()
    if STATE.UI.Closed then return end
    if not STATE.ESP.Tracers then
        ESPLines.Clear()
        return
    end
    
    for char, line in pairs(ESPLineObjects) do
        if not char.Parent or not TargetProvider.IsAlive(char) then
            pcall(function() line:Destroy() end)
            ESPLineObjects[char] = nil
            continue
        end
        
        if not TargetProvider.IsEnemy(char) and STATE.ESP.TeamCheck then
            pcall(function() line:Destroy() end)
            ESPLineObjects[char] = nil
            continue
        end
        
        local headPos = TargetProvider.GetHeadPosition(char)
        local onScreen, screenPos = TargetProvider.IsOnScreen(headPos)
        
        if onScreen then
            local originX, originY
            if STATE.Visual.TracerOrigin == "BottomCenter" then
                originX = Camera.ViewportSize.X / 2
                originY = Camera.ViewportSize.Y - 50
            elseif STATE.Visual.TracerOrigin == "Center" then
                originX = Camera.ViewportSize.X / 2
                originY = Camera.ViewportSize.Y / 2
            else
                originX = Camera.ViewportSize.X / 2
                originY = Camera.ViewportSize.Y / 2
            end
            
            local x1 = originX
            local y1 = originY
            local x2 = screenPos.X
            local y2 = screenPos.Y
            
            local dx = x2 - x1
            local dy = y2 - y1
            local length = math.sqrt(dx * dx + dy * dy)
            local angle = math.atan2(dy, dx)
            
            line.Size = UDim2.new(0, length, 0, 2)
            line.Position = UDim2.new(0, x1, 0, y1 - 1)
            line.Rotation = math.deg(angle)
            line.Visible = true
        else
            line.Visible = false
        end
    end
    
    for _, char in pairs(TargetProvider.GetCharacters()) do
        if TargetProvider.IsEnemy(char) and TargetProvider.IsAlive(char) then
            if not ESPLineObjects[char] then
                ESPLines.Create(char)
            end
        end
    end
end

function ESPLines.Clear()
    for char, line in pairs(ESPLineObjects) do
        pcall(function() line:Destroy() end)
    end
    ESPLineObjects = {}
    pcall(function()
        local gui = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("ESP_Lines")
        if gui then gui:Destroy() end
    end)
end

-- ============================================================
-- [FOV CIRCLE - INDEPENDENTE]
-- ============================================================
local FOVCircle = {}

function FOVCircle.Create(radius)
    FOVCircle.Destroy()
    if STATE.UI.Closed then return end
    
    local gui = Instance.new("ScreenGui")
    gui.Name = "FOVCircle"
    gui.ResetOnSpawn = false
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    
    local frame = Instance.new("Frame")
    frame.Name = "Circle"
    frame.Size = UDim2.new(0, radius * 2, 0, radius * 2)
    frame.Position = UDim2.new(0.5, -radius, 0.5, -radius)
    frame.BackgroundTransparency = 1
    frame.Parent = gui
    
    local outline = Instance.new("ImageLabel")
    outline.Size = UDim2.new(1, 0, 1, 0)
    outline.Position = UDim2.new(0, 0, 0, 0)
    outline.BackgroundTransparency = 1
    outline.Image = "rbxassetid://3570695787"
    outline.ImageColor3 = Color3.fromRGB(0, 255, 255)
    outline.ImageTransparency = 0.3
    outline.Parent = frame
    
    fovCircleGui = gui
end

function FOVCircle.Destroy()
    if fovCircleGui then
        pcall(function() fovCircleGui:Destroy() end)
        fovCircleGui = nil
    end
end

function FOVCircle.Update()
    if STATE.Visual.FOVCircle then
        FOVCircle.Create(STATE.Visual.FOVRadius)
    else
        FOVCircle.Destroy()
    end
end

-- ============================================================
-- [MAIN LOOP - ÚNICO RENDER STEP]
-- ============================================================
local function MainLoop()
    while not STATE.UI.Closed do
        TargetProvider.GetBestTarget()
        
        if STATE.ESP.Enabled then
            ESP.Update()
        end
        
        if STATE.ESP.Tracers then
            ESPLines.Update()
        end
        
        if STATE.Aim.Enabled and STATE.Aim.Assist then
            CameraController.Update()
        end
        
        task.wait()
    end
end

-- ============================================================
-- [UI SETUP]
-- ============================================================
local FluentLib = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local function SetupUI()
    if STATE.UI.Closed then return end
    if STATE.UI.WindowRef then
        pcall(function() STATE.UI.WindowRef:Destroy() end)
        STATE.UI.WindowRef = nil
    end
    
    STATE.UI.WindowRef = FluentLib:CreateWindow({
        Title = "MurderDuels",
        SubTitle = "FPS Exploit v3.0",
        TabWidth = 160,
        Size = UDim2.fromOffset(620, 480),
        Acrylic = true,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightControl,
    })
    
    STATE.UI.Visible = true
    
    local Tabs = {
        ESP = STATE.UI.WindowRef:AddTab({ Title = "ESP", Icon = "eye" }),
        Aim = STATE.UI.WindowRef:AddTab({ Title = "Aim", Icon = "crosshair" }),
        Visual = STATE.UI.WindowRef:AddTab({ Title = "Visual", Icon = "circle" }),
        Combat = STATE.UI.WindowRef:AddTab({ Title = "Combat", Icon = "swords" }),
    }
    local Options = FluentLib.Options
    
    -- ===== ESP TAB =====
    Tabs.ESP:AddSection("ESP Geral")
    
    Tabs.ESP:AddToggle("ESP_Enabled", {
        Title = "ESP Ativado",
        Default = false,
    })
    Options.ESP_Enabled:OnChanged(function(v)
        STATE.ESP.Enabled = v
        if not v then ESP.Clear() end
    end)
    
    Tabs.ESP:AddToggle("ESP_Highlight", {
        Title = "Highlight",
        Default = true,
    })
    Options.ESP_Highlight:OnChanged(function(v)
        STATE.ESP.Highlight = v
        if not v then
            for char, esp in pairs(ESP_Objects) do
                if esp.highlight then
                    pcall(function() esp.highlight:Destroy() end)
                    esp.highlight = nil
                end
            end
        end
    end)
    
    Tabs.ESP:AddToggle("ESP_Distance", {
        Title = "Distância",
        Default = true,
    })
    Options.ESP_Distance:OnChanged(function(v)
        STATE.ESP.Distance = v
        if not v then
            for char, esp in pairs(ESP_Objects) do
                if esp.billboard then
                    pcall(function() esp.billboard:Destroy() end)
                    esp.billboard = nil
                    esp.label = nil
                end
            end
        end
    end)
    
    Tabs.ESP:AddToggle("ESP_Tracers", {
        Title = "Tracers (Linhas)",
        Default = false,
    })
    Options.ESP_Tracers:OnChanged(function(v)
        STATE.ESP.Tracers = v
        if not v then ESPLines.Clear() end
    end)
    
    Tabs.ESP:AddSection("Filtros")
    
    Tabs.ESP:AddToggle("ESP_TeamCheck", {
        Title = "Team Check",
        Default = true,
    })
    Options.ESP_TeamCheck:OnChanged(function(v)
        STATE.ESP.TeamCheck = v
    end)
    
    -- ===== AIM TAB =====
    Tabs.Aim:AddSection("Configurações de Mira")
    
    Tabs.Aim:AddToggle("Aim_Enabled", {
        Title = "Aimbot Ativado",
        Default = false,
    })
    Options.Aim_Enabled:OnChanged(function(v)
        STATE.Aim.Enabled = v
        if v then
            CameraController.Setup()
            if not STATE.Aim.Silent and not STATE.Aim.Assist then
                STATE.Aim.Assist = true
            end
        else
            CameraController.Disable()
            STATE.Target.Current = nil
        end
    end)
    
    Tabs.Aim:AddToggle("Aim_Silent", {
        Title = "Silent Aim",
        Default = false,
    })
    Options.Aim_Silent:OnChanged(function(v)
        STATE.Aim.Silent = v
        if v then
            STATE.Aim.Assist = false
        end
    end)
    
    Tabs.Aim:AddToggle("Aim_Assist", {
        Title = "Aim Assist",
        Default = true,
    })
    Options.Aim_Assist:OnChanged(function(v)
        STATE.Aim.Assist = v
        if v then
            STATE.Aim.Silent = false
        end
    end)
    
    Tabs.Aim:AddSlider("Aim_Strength", {
        Title = "Força da Mira",
        Min = 0.1,
        Max = 1,
        Default = 0.5,
        Rounding = 2,
    })
    Options.Aim_Strength:OnChanged(function(v)
        STATE.Aim.Strength = v
        if STATE.Camera.Controller then
            STATE.Camera.Controller:setMethodStrength(AimAssistEnum.AimAssistMethod.Centering, v)
            STATE.Camera.Controller:setMethodStrength(AimAssistEnum.AimAssistMethod.Tracking, v * 0.5)
            STATE.Camera.Controller:setMethodStrength(AimAssistEnum.AimAssistMethod.Friction, v * 0.3)
        end
    end)
    
    Tabs.Aim:AddSlider("Aim_Radius", {
        Title = "FOV do Aimbot",
        Min = 50,
        Max = 500,
        Default = 200,
        Rounding = 0,
    })
    Options.Aim_Radius:OnChanged(function(v)
        STATE.Aim.Radius = v
        if STATE.Camera.Controller then
            STATE.Camera.Controller:setRange(v)
            STATE.Camera.Controller:setFieldOfView(v)
        end
    end)
    
    -- ===== VISUAL TAB =====
    Tabs.Visual:AddSection("FOV Circle")
    
    Tabs.Visual:AddToggle("Visual_FOVCircle", {
        Title = "Mostrar Círculo FOV",
        Default = false,
    })
    Options.Visual_FOVCircle:OnChanged(function(v)
        STATE.Visual.FOVCircle = v
        FOVCircle.Update()
    end)
    
    Tabs.Visual:AddSlider("Visual_FOVRadius", {
        Title = "Raio do FOV",
        Min = 30,
        Max = 500,
        Default = 200,
        Rounding = 0,
    })
    Options.Visual_FOVRadius:OnChanged(function(v)
        STATE.Visual.FOVRadius = v
        FOVCircle.Update()
    end)
    
    Tabs.Visual:AddSection("Câmera")
    
    Tabs.Visual:AddSlider("Visual_CameraFOV", {
        Title = "FOV da Câmera",
        Min = 40,
        Max = 120,
        Default = 70,
        Rounding = 0,
    })
    Options.Visual_CameraFOV:OnChanged(function(v)
        STATE.Visual.CameraFOV = v
        FOVController.SetBase(v)
    end)
    
    Tabs.Visual:AddSection("Tracer Origin")
    
    local originOptions = {
        ["Centro"] = "Center",
        ["Centro Inferior"] = "BottomCenter",
    }
    Tabs.Visual:AddDropdown("Visual_TracerOrigin", {
        Title = "Origem das Linhas",
        Values = originOptions,
        Default = "BottomCenter",
    })
    Options.Visual_TracerOrigin:OnChanged(function(v)
        STATE.Visual.TracerOrigin = v
    end)
    
    -- ===== COMBAT TAB =====
    Tabs.Combat:AddSection("Combate")
    
    Tabs.Combat:AddToggle("Combat_AutoShoot", {
        Title = "Auto Shoot",
        Default = false,
    })
    Options.Combat_AutoShoot:OnChanged(function(v)
        STATE.Combat.AutoShoot = v
        if v then
            AddConnection(RunService.Heartbeat:Connect(function()
                if STATE.Combat.AutoShoot and STATE.Aim.Enabled then
                    local target = STATE.Target.Current
                    if target and target.IsValid then
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
            end))
        end
    end)
    
    Tabs.Combat:AddToggle("Combat_KnifePrediction", {
        Title = "Knife Prediction",
        Default = false,
    })
    Options.Combat_KnifePrediction:OnChanged(function(v)
        STATE.Combat.KnifePrediction = v
    end)
    
    Tabs.Combat:AddSection("Third Person")
    
    Tabs.Combat:AddButton({
        Title = "Toggle Third Person",
        Callback = function()
            ThirdPerson.Toggle()
            FluentLib:Notify({
                Title = "Third Person",
                Content = "Toggled: " .. tostring(ThirdPerson.IsEnabled()),
                Duration = 2,
            })
        end,
    })
    
    -- ===== CLOSE BUTTON =====
    task.spawn(function()
        task.wait(0.5)
        if STATE.UI.WindowRef then
            local success, gui = pcall(function()
                return STATE.UI.WindowRef.Gui
            end)
            if success and gui then
                local closeBtn = Instance.new("TextButton")
                closeBtn.Name = "CloseButton"
                closeBtn.Size = UDim2.new(0, 30, 0, 30)
                closeBtn.Position = UDim2.new(1, -35, 0, 5)
                closeBtn.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
                closeBtn.BackgroundTransparency = 0.3
                closeBtn.Text = "✕"
                closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
                closeBtn.TextSize = 20
                closeBtn.Font = Enum.Font.GothamBold
                closeBtn.BorderSizePixel = 0
                closeBtn.Parent = gui
                closeBtn.MouseButton1Click:Connect(function()
                    CleanupAll()
                end)
                closeBtn.MouseEnter:Connect(function()
                    closeBtn.BackgroundTransparency = 0
                end)
                closeBtn.MouseLeave:Connect(function()
                    closeBtn.BackgroundTransparency = 0.3
                end)
            end
        end
    end)
end

-- ============================================================
-- [KEYBINDS]
-- ============================================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        if STATE.UI.WindowRef and STATE.UI.WindowRef.Visible then
            CleanupUI()
        else
            SetupUI()
        end
    end
end)

-- ============================================================
-- [CHARACTER ADDED]
-- ============================================================
LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    if STATE.Aim.Enabled then
        CameraController.Setup()
        if STATE.Camera.Controller then
            STATE.Camera.Controller:setSubject(char)
        end
    end
end)

-- ============================================================
-- [INICIALIZAÇÃO]
-- ============================================================
SetupUI()
FOVController.SetBase(STATE.Visual.CameraFOV)

AddConnection(RunService.Heartbeat:Connect(MainLoop))

FluentLib:Notify({
    Title = "MurderDuels",
    Content = "FPS Exploit v3.0 carregado! (Reescrito)",
    Duration = 4,
})

print("============================================================")
print("MURDERDUELS | FPS EXPLOIT v3.0")
print("============================================================")
print("[✓] Aimbot desacoplado do Silent Aim")
print("[✓] Silent Aim independente")
print("[✓] Aim Assist independente")
print("[✓] ESP com Highlight/Distance/Tracers separados")
print("[✓] FOV Circle com linha circular")
print("[✓] Knife Prediction independente")
print("[✓] Auto Shoot independente")
print("[✓] Único loop de renderização")
print("============================================================")
