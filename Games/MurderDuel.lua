-- ============================================================
-- CAT EMPIRE | FIVEM ESP ADAPTATION
-- ESP 2D ancorado no personagem, inspirado na source PlayerESP.cpp.
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

local PURPLE = Color3.fromRGB(121, 131, 207)

local State = {
    ESP = {
        Enabled = false,
        Box = true,
        Skeleton = false,
        Name = true,
        HealthBar = true,
        ArmorBar = false,
        WeaponName = false,
        Distance = true,
        Lines = false,
        TeamCheck = true,
        RenderingDistance = 500,
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
-- PLAYER ESP (adaptado da lógica do PlayerESP.cpp)
-- ============================================================

local ESP_GUI_NAME = "CAT_EMPIRE_PlayerESP"
local ESP_BLACK = Color3.fromRGB(0, 0, 0)
local ESP_WHITE = Color3.fromRGB(235, 235, 240)
local ESP_ACCENT = Color3.fromRGB(121, 131, 207)
local ESP_ARMOR = Color3.fromRGB(25, 120, 245)

local function GetESPGui()
    local gui = GetPlayerGui():FindFirstChild(ESP_GUI_NAME)
    if gui then
        return gui
    end

    gui = Instance.new("ScreenGui")
    gui.Name = ESP_GUI_NAME
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9996
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = GetPlayerGui()
    return gui
end

local function NewESPFrame(name, parent)
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.Visible = false
    frame.Parent = parent
    return frame
end

local function NewESPLabel(name, parent)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 12
    label.TextColor3 = ESP_WHITE
    label.TextStrokeColor3 = ESP_BLACK
    label.TextStrokeTransparency = 0.15
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Visible = false
    label.ZIndex = 20
    label.Parent = parent
    return label
end

local function NewLine(name, parent, thickness)
    local line = Instance.new("Frame")
    line.Name = name
    line.AnchorPoint = Vector2.new(0, 0.5)
    line.BackgroundColor3 = ESP_ACCENT
    line.BackgroundTransparency = 0
    line.BorderSizePixel = 0
    line.Size = UDim2.fromOffset(0, thickness or 1)
    line.Visible = false
    line.ZIndex = 12
    line.Parent = parent
    return line
end

local function SetLine(line, a, b, thickness, color)
    local delta = b - a
    local length = delta.Magnitude
    if length < 0.5 then
        line.Visible = false
        return
    end

    line.Position = UDim2.fromOffset(a.X, a.Y)
    line.Size = UDim2.fromOffset(length, thickness or 1)
    line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
    line.BackgroundColor3 = color or ESP_ACCENT
    line.Visible = true
end

local function FindPart(char, names)
    for _, name in ipairs(names) do
        local part = char:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            return part
        end
    end
    return nil
end

local function GetFootBottom(part)
    if not part then return nil end
    return part.Position - Vector3.new(0, part.Size.Y * 0.5, 0)
end

local function GetESPBounds(char)
    local head = FindPart(char, {"Head"}) or GetTargetPart(char)
    local root = GetTargetPart(char)
    if not head or not root then
        return nil
    end

    -- O FiveM calcula a caixa a partir da cabeça e dos pés.
    -- Aqui usamos os equivalentes R15/R6 do Roblox.
    local leftFoot = FindPart(char, {"LeftFoot", "LeftLowerLeg", "Left Leg"})
    local rightFoot = FindPart(char, {"RightFoot", "RightLowerLeg", "Right Leg"})

    local headTopWorld = head.Position + Vector3.new(0, math.max(head.Size.Y * 0.55, 0.35), 0)
    local headScreen, headVisible = ProjectToScreen(headTopWorld)
    local centerScreen, centerVisible = ProjectToScreen(root.Position)

    if not headScreen or not centerScreen or not headVisible or not centerVisible then
        return nil
    end

    local leftWorld = GetFootBottom(leftFoot)
    local rightWorld = GetFootBottom(rightFoot)

    if not leftWorld then
        leftWorld = root.Position - Vector3.new(0, 3, 0)
    end
    if not rightWorld then
        rightWorld = root.Position - Vector3.new(0, 3, 0)
    end

    local leftScreen, leftVisible = ProjectToScreen(leftWorld)
    local rightScreen, rightVisible = ProjectToScreen(rightWorld)
    if not leftScreen or not rightScreen or not leftVisible or not rightVisible then
        return nil
    end

    local rawHeight = math.max(leftScreen.Y, rightScreen.Y) - headScreen.Y
    if rawHeight <= 4 then
        return nil
    end

    -- Mesma proporção da source FiveM: Width = Height / 1.8;
    -- depois Height *= 1.2 para dar folga ao corpo.
    local width = rawHeight / 1.8
    local centerY = headScreen.Y + rawHeight / 2
    local height = rawHeight * 1.2
    local centerX = centerScreen.X

    return {
        X = centerX - width / 2,
        Y = centerY - height / 2,
        Width = width,
        Height = height,
        Center = Vector2.new(centerX, centerY),
        BottomCenter = Vector2.new(centerX, centerY + height / 2),
    }
end

local R15_BONES = {
    {{"HumanoidRootPart", "LowerTorso"}, {"UpperTorso", "Torso"}},
    {{"UpperTorso", "Torso"}, {"Head"}},
    {{"UpperTorso", "Torso"}, {"LeftUpperArm", "Left Arm"}},
    {{"LeftUpperArm", "Left Arm"}, {"LeftLowerArm", "Left Arm"}},
    {{"LeftLowerArm", "Left Arm"}, {"LeftHand", "Left Arm"}},
    {{"UpperTorso", "Torso"}, {"RightUpperArm", "Right Arm"}},
    {{"RightUpperArm", "Right Arm"}, {"RightLowerArm", "Right Arm"}},
    {{"RightLowerArm", "Right Arm"}, {"RightHand", "Right Arm"}},
    {{"HumanoidRootPart", "LowerTorso", "Torso"}, {"LeftUpperLeg", "Left Leg"}},
    {{"LeftUpperLeg", "Left Leg"}, {"LeftLowerLeg", "Left Leg"}},
    {{"LeftLowerLeg", "Left Leg"}, {"LeftFoot", "Left Leg"}},
    {{"HumanoidRootPart", "LowerTorso", "Torso"}, {"RightUpperLeg", "Right Leg"}},
    {{"RightUpperLeg", "Right Leg"}, {"RightLowerLeg", "Right Leg"}},
    {{"RightLowerLeg", "Right Leg"}, {"RightFoot", "Right Leg"}},
}

local function CreateESPData(char)
    local gui = GetESPGui()
    local data = {
        Skeleton = {},
    }

    data.BoxOutline = NewESPFrame("BoxOutline_" .. char.Name, gui)
    data.BoxOutline.BorderSizePixel = 3
    data.BoxOutline.BorderColor3 = ESP_BLACK
    data.BoxOutline.ZIndex = 8

    data.Box = NewESPFrame("Box_" .. char.Name, gui)
    data.Box.BorderSizePixel = 1
    data.Box.BorderColor3 = ESP_ACCENT
    data.Box.ZIndex = 9

    data.HealthBack = NewESPFrame("HealthBack_" .. char.Name, gui)
    data.HealthBack.BackgroundTransparency = 0
    data.HealthBack.BackgroundColor3 = ESP_BLACK
    data.HealthBack.ZIndex = 9

    data.Health = NewESPFrame("Health_" .. char.Name, gui)
    data.Health.BackgroundTransparency = 0
    data.Health.BackgroundColor3 = Color3.fromRGB(0, 255, 12)
    data.Health.ZIndex = 10

    data.ArmorBack = NewESPFrame("ArmorBack_" .. char.Name, gui)
    data.ArmorBack.BackgroundTransparency = 0
    data.ArmorBack.BackgroundColor3 = ESP_BLACK
    data.ArmorBack.ZIndex = 9

    data.Armor = NewESPFrame("Armor_" .. char.Name, gui)
    data.Armor.BackgroundTransparency = 0
    data.Armor.BackgroundColor3 = ESP_ARMOR
    data.Armor.ZIndex = 10

    data.Name = NewESPLabel("Name_" .. char.Name, gui)
    data.Weapon = NewESPLabel("Weapon_" .. char.Name, gui)
    data.Distance = NewESPLabel("Distance_" .. char.Name, gui)
    data.Line = NewLine("Line_" .. char.Name, gui, 1)

    for index = 1, #R15_BONES do
        data.Skeleton[index] = NewLine("Skeleton_" .. char.Name .. "_" .. index, gui, 1)
    end

    ESPObjects[char] = data
    return data
end

local function HideESPData(data)
    if not data then return end

    for _, key in ipairs({
        "BoxOutline", "Box", "HealthBack", "Health",
        "ArmorBack", "Armor", "Name", "Weapon", "Distance", "Line"
    }) do
        local object = data[key]
        if object then
            object.Visible = false
        end
    end

    for _, line in ipairs(data.Skeleton or {}) do
        line.Visible = false
    end
end

local function RemoveESP(char)
    local data = ESPObjects[char]
    if not data then return end

    for _, key in ipairs({
        "BoxOutline", "Box", "HealthBack", "Health",
        "ArmorBack", "Armor", "Name", "Weapon", "Distance", "Line"
    }) do
        local object = data[key]
        if object then
            pcall(function() object:Destroy() end)
        end
    end

    for _, line in ipairs(data.Skeleton or {}) do
        pcall(function() line:Destroy() end)
    end

    ESPObjects[char] = nil
end

local function ClearESP()
    for char in pairs(ESPObjects) do
        RemoveESP(char)
    end
end

local function GetArmorValue(char)
    local value = char:GetAttribute("Armor")
    if value == nil then
        local humanoid = GetHumanoid(char)
        if humanoid then
            value = humanoid:GetAttribute("Armor")
        end
    end
    return math.clamp(tonumber(value) or 0, 0, 100)
end

local function GetLocalScreenOrigin()
    local camera = GetCamera()
    if not camera then
        return Vector2.new(0, 0)
    end

    local myPart = GetTargetPart(LocalPlayer.Character)
    if myPart then
        local screen, visible = ProjectToScreen(myPart.Position)
        if screen and visible then
            return Vector2.new(screen.X, screen.Y)
        end
    end

    return Vector2.new(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y - 4)
end

local function UpdateSkeleton(char, data)
    if not State.ESP.Skeleton then
        for _, line in ipairs(data.Skeleton) do
            line.Visible = false
        end
        return
    end

    for index, pair in ipairs(R15_BONES) do
        local a = FindPart(char, pair[1])
        local b = FindPart(char, pair[2])
        local line = data.Skeleton[index]

        if a and b then
            local aScreen, aVisible = ProjectToScreen(a.Position)
            local bScreen, bVisible = ProjectToScreen(b.Position)

            if aScreen and bScreen and aVisible and bVisible then
                SetLine(
                    line,
                    Vector2.new(aScreen.X, aScreen.Y),
                    Vector2.new(bScreen.X, bScreen.Y),
                    1,
                    ESP_ACCENT
                )
            else
                line.Visible = false
            end
        else
            line.Visible = false
        end
    end
end

local function UpdatePlayerESP(char, data, myRoot)
    if not State.ESP.Enabled or not IsEnemy(char) then
        HideESPData(data)
        return
    end

    local targetRoot = GetTargetPart(char)
    local humanoid = GetHumanoid(char)
    if not targetRoot or not humanoid then
        HideESPData(data)
        return
    end

    local distance = GetDistance(myRoot.Position, targetRoot.Position)
    if distance > State.ESP.RenderingDistance then
        HideESPData(data)
        return
    end

    local bounds = GetESPBounds(char)
    if not bounds then
        HideESPData(data)
        return
    end

    local x = bounds.X
    local y = bounds.Y
    local width = bounds.Width
    local height = bounds.Height

    if State.ESP.Box then
        data.BoxOutline.Position = UDim2.fromOffset(x - 1, y - 1)
        data.BoxOutline.Size = UDim2.fromOffset(width + 2, height + 2)
        data.BoxOutline.Visible = true

        data.Box.Position = UDim2.fromOffset(x, y)
        data.Box.Size = UDim2.fromOffset(width, height)
        data.Box.Visible = true
    else
        data.BoxOutline.Visible = false
        data.Box.Visible = false
    end

    local bottomPadding = State.ESP.Box and 3 or 0

    if State.ESP.HealthBar then
        local maxHealth = math.max(humanoid.MaxHealth, 1)
        local ratio = math.clamp(humanoid.Health / maxHealth, 0, 1)
        local healthColor

        if humanoid.Health <= 0 then
            healthColor = Color3.fromRGB(255, 0, 0)
        elseif humanoid.Health <= maxHealth / 2 then
            healthColor = Color3.fromRGB(255, 255, 0)
        else
            healthColor = Color3.fromRGB(0, 255, 12)
        end

        data.HealthBack.Position = UDim2.fromOffset(x - 8, y - 1)
        data.HealthBack.Size = UDim2.fromOffset(4, height + 2)
        data.HealthBack.Visible = true

        data.Health.Position = UDim2.fromOffset(x - 7, y + height * (1 - ratio))
        data.Health.Size = UDim2.fromOffset(2, height * ratio)
        data.Health.BackgroundColor3 = healthColor
        data.Health.Visible = true
    else
        data.HealthBack.Visible = false
        data.Health.Visible = false
    end

    if State.ESP.ArmorBar then
        local armor = GetArmorValue(char)
        if armor > 0 then
            data.ArmorBack.Position = UDim2.fromOffset(x - 1, y + height + bottomPadding)
            data.ArmorBack.Size = UDim2.fromOffset(width + 2, 4)
            data.ArmorBack.Visible = true

            data.Armor.Position = UDim2.fromOffset(x, y + height + bottomPadding + 1)
            data.Armor.Size = UDim2.fromOffset(width * (armor / 100), 2)
            data.Armor.Visible = true
            bottomPadding += 5
        else
            data.ArmorBack.Visible = false
            data.Armor.Visible = false
        end
    else
        data.ArmorBack.Visible = false
        data.Armor.Visible = false
    end

    local labelY = y + height + bottomPadding

    if State.ESP.Name then
        data.Name.Text = char.Name
        data.Name.Position = UDim2.fromOffset(x - 35, labelY)
        data.Name.Size = UDim2.fromOffset(width + 70, 14)
        data.Name.Visible = true
        labelY += 14
    else
        data.Name.Visible = false
    end

    if State.ESP.WeaponName then
        local tool = char:FindFirstChildOfClass("Tool")
        data.Weapon.Text = tool and tool.Name or "Unarmed"
        data.Weapon.Position = UDim2.fromOffset(x - 35, labelY)
        data.Weapon.Size = UDim2.fromOffset(width + 70, 14)
        data.Weapon.Visible = true
        labelY += 14
    else
        data.Weapon.Visible = false
    end

    if State.ESP.Distance then
        data.Distance.Text = string.format("%d studs", math.floor(distance + 0.5))
        data.Distance.Position = UDim2.fromOffset(x - 35, labelY)
        data.Distance.Size = UDim2.fromOffset(width + 70, 14)
        data.Distance.Visible = true
    else
        data.Distance.Visible = false
    end

    if State.ESP.Lines then
        SetLine(data.Line, GetLocalScreenOrigin(), bounds.Center, 1, ESP_ACCENT)
    else
        data.Line.Visible = false
    end

    UpdateSkeleton(char, data)
end

local function UpdateESP()
    if not State.ESP.Enabled then
        for _, data in pairs(ESPObjects) do
            HideESPData(data)
        end
        return
    end

    local myRoot = GetTargetPart(LocalPlayer.Character)
    if not myRoot then
        for _, data in pairs(ESPObjects) do
            HideESPData(data)
        end
        return
    end

    local current = {}

    for _, char in ipairs(GetCharacters()) do
        current[char] = true
        local data = ESPObjects[char] or CreateESPData(char)
        UpdatePlayerESP(char, data, myRoot)
    end

    for char in pairs(ESPObjects) do
        if not current[char] or not char.Parent then
            RemoveESP(char)
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

    ClearESP()
    DestroyNamedGui(ESP_GUI_NAME)
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
        Size = UDim2.fromOffset(660, 430),
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

    -- VISUALS - layout inspirado na source FiveM: Players ESP + Preview.
    local visualGrid = Tabs.Visuals:AddGroup({Columns = 2, Gap = 10})
    local visualLeft = visualGrid:AddElement()
    local visualRight = visualGrid:AddElement()

    visualLeft:AddSection("Players ESP")

    visualLeft:AddToggle("ESPEnabled", {
        Title = "Toggle",
        Default = false,
    })
    Fluent.Options.ESPEnabled:OnChanged(function(value)
        State.ESP.Enabled = value
        if not value then
            for _, data in pairs(ESPObjects) do HideESPData(data) end
        else
            UpdateESP()
        end
    end)

    visualLeft:AddSlider("ESPRenderDistance", {
        Title = "Rendering Distance",
        Min = 25,
        Max = 1000,
        Default = 500,
        Rounding = 0,
    })
    Fluent.Options.ESPRenderDistance:OnChanged(function(value)
        State.ESP.RenderingDistance = value
    end)

    visualLeft:AddToggle("ESPBox", {Title = "Box", Default = true})
    Fluent.Options.ESPBox:OnChanged(function(value) State.ESP.Box = value end)

    visualLeft:AddToggle("ESPSkeleton", {Title = "Skeleton", Default = false})
    Fluent.Options.ESPSkeleton:OnChanged(function(value) State.ESP.Skeleton = value end)

    visualLeft:AddToggle("ESPHealth", {Title = "Health Bar", Default = true})
    Fluent.Options.ESPHealth:OnChanged(function(value) State.ESP.HealthBar = value end)

    visualLeft:AddToggle("ESPArmor", {Title = "Armor Bar", Default = false})
    Fluent.Options.ESPArmor:OnChanged(function(value) State.ESP.ArmorBar = value end)

    visualLeft:AddToggle("ESPName", {Title = "Name", Default = true})
    Fluent.Options.ESPName:OnChanged(function(value) State.ESP.Name = value end)

    visualLeft:AddToggle("ESPWeapon", {Title = "Weapon Name", Default = false})
    Fluent.Options.ESPWeapon:OnChanged(function(value) State.ESP.WeaponName = value end)

    visualLeft:AddToggle("ESPDistance", {Title = "Distance", Default = true})
    Fluent.Options.ESPDistance:OnChanged(function(value) State.ESP.Distance = value end)

    visualLeft:AddToggle("ESPLines", {Title = "Lines", Default = false})
    Fluent.Options.ESPLines:OnChanged(function(value) State.ESP.Lines = value end)

    visualLeft:AddToggle("TeamCheck", {Title = "Team Check", Default = true})
    Fluent.Options.TeamCheck:OnChanged(function(value)
        State.ESP.TeamCheck = value
        if Fluent.Options.CombatTeamCheck
            and Fluent.Options.CombatTeamCheck.Value ~= value
        then
            Fluent.Options.CombatTeamCheck:SetValue(value)
        end
    end)

    -- Preview semelhante à coluna da direita do Interface.cpp, sem usar imagem.
    local previewSection = visualRight:AddSection("Preview")
    local preview = Instance.new("Frame")
    preview.Name = "ESPPreview"
    preview.BackgroundColor3 = Color3.fromRGB(7, 7, 9)
    preview.BorderSizePixel = 0
    preview.Size = UDim2.new(1, 0, 0, 230)
    preview.LayoutOrder = 2
    preview.Parent = previewSection

    local previewCorner = Instance.new("UICorner")
    previewCorner.CornerRadius = UDim.new(0, 4)
    previewCorner.Parent = preview

    local previewStroke = Instance.new("UIStroke")
    previewStroke.Color = Color3.fromRGB(35, 36, 42)
    previewStroke.Transparency = 0.15
    previewStroke.Thickness = 1
    previewStroke.Parent = preview

    local pBoxOutline = Instance.new("Frame")
    pBoxOutline.BackgroundTransparency = 1
    pBoxOutline.BorderColor3 = Color3.new(0, 0, 0)
    pBoxOutline.BorderSizePixel = 3
    pBoxOutline.Position = UDim2.new(0.5, -47, 0, 24)
    pBoxOutline.Size = UDim2.fromOffset(94, 156)
    pBoxOutline.Parent = preview

    local pBox = Instance.new("Frame")
    pBox.BackgroundTransparency = 1
    pBox.BorderColor3 = ESP_ACCENT
    pBox.BorderSizePixel = 1
    pBox.Position = UDim2.new(0.5, -46, 0, 25)
    pBox.Size = UDim2.fromOffset(92, 154)
    pBox.Parent = preview

    local pHealthBack = Instance.new("Frame")
    pHealthBack.BackgroundColor3 = Color3.new(0, 0, 0)
    pHealthBack.BorderSizePixel = 0
    pHealthBack.Position = UDim2.new(0.5, -54, 0, 24)
    pHealthBack.Size = UDim2.fromOffset(4, 156)
    pHealthBack.Parent = preview

    local pHealth = Instance.new("Frame")
    pHealth.BackgroundColor3 = Color3.fromRGB(0, 255, 12)
    pHealth.BorderSizePixel = 0
    pHealth.Position = UDim2.new(0.5, -53, 0, 54)
    pHealth.Size = UDim2.fromOffset(2, 125)
    pHealth.Parent = preview

    local pArmorBack = Instance.new("Frame")
    pArmorBack.BackgroundColor3 = Color3.new(0, 0, 0)
    pArmorBack.BorderSizePixel = 0
    pArmorBack.Position = UDim2.new(0.5, -47, 0, 183)
    pArmorBack.Size = UDim2.fromOffset(94, 4)
    pArmorBack.Parent = preview

    local pArmor = Instance.new("Frame")
    pArmor.BackgroundColor3 = ESP_ARMOR
    pArmor.BorderSizePixel = 0
    pArmor.Position = UDim2.new(0.5, -46, 0, 184)
    pArmor.Size = UDim2.fromOffset(72, 2)
    pArmor.Parent = preview

    local pName = Instance.new("TextLabel")
    pName.BackgroundTransparency = 1
    pName.Text = "username"
    pName.TextColor3 = Color3.fromRGB(235, 235, 240)
    pName.TextStrokeTransparency = 0.15
    pName.Font = Enum.Font.GothamMedium
    pName.TextSize = 11
    pName.Position = UDim2.new(0.5, -70, 0, 190)
    pName.Size = UDim2.fromOffset(140, 14)
    pName.Parent = preview

    local pDistance = pName:Clone()
    pDistance.Text = "0 studs"
    pDistance.Position = UDim2.new(0.5, -70, 0, 204)
    pDistance.Parent = preview

    local pLine = Instance.new("Frame")
    pLine.AnchorPoint = Vector2.new(0, 0.5)
    pLine.BackgroundColor3 = ESP_ACCENT
    pLine.BorderSizePixel = 0
    pLine.Position = UDim2.new(0.5, 0, 1, -5)
    pLine.Size = UDim2.fromOffset(0, 1)
    pLine.Parent = preview

    local function UpdatePreview()
        pBoxOutline.Visible = State.ESP.Box
        pBox.Visible = State.ESP.Box
        pHealthBack.Visible = State.ESP.HealthBar
        pHealth.Visible = State.ESP.HealthBar
        pArmorBack.Visible = State.ESP.ArmorBar
        pArmor.Visible = State.ESP.ArmorBar
        pName.Visible = State.ESP.Name
        pDistance.Visible = State.ESP.Distance

        if State.ESP.Lines then
            local a = Vector2.new(preview.AbsoluteSize.X * 0.5, preview.AbsoluteSize.Y - 5)
            local b = Vector2.new(preview.AbsoluteSize.X * 0.5, 102)
            local d = b - a
            pLine.Position = UDim2.fromOffset(a.X, a.Y)
            pLine.Size = UDim2.fromOffset(d.Magnitude, 1)
            pLine.Rotation = math.deg(math.atan2(d.Y, d.X))
            pLine.Visible = true
        else
            pLine.Visible = false
        end
    end

    for _, optionName in ipairs({
        "ESPBox", "ESPHealth", "ESPArmor", "ESPName", "ESPDistance", "ESPLines"
    }) do
        Fluent.Options[optionName]:OnChanged(UpdatePreview)
    end
    task.defer(UpdatePreview)

    visualRight:AddSection("Camera / FOV")
    visualRight:AddToggle("FOVCircle", {Title = "Draw FOV", Default = false})
    Fluent.Options.FOVCircle:OnChanged(function(value)
        State.Visual.FOVCircle = value
        UpdateFOVCircle()
    end)

    visualRight:AddSlider("FOVRadius", {
        Title = "FOV Radius", Min = 30, Max = 500, Default = 200, Rounding = 0,
    })
    Fluent.Options.FOVRadius:OnChanged(function(value)
        State.Visual.FOVRadius = value
        UpdateFOVCircle()
    end)

    visualRight:AddSlider("CameraFOV", {
        Title = "Camera FOV", Min = 40, Max = 120, Default = 70, Rounding = 0,
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
    local lineCountLabel = configRight:AddLabel("ESP Lines: 0")

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

            local lineCount = 0
            for _, data in pairs(ESPObjects) do
                if data.Line and data.Line.Visible then
                    lineCount += 1
                end
            end

            espCountLabel:SetText("ESP Objects: " .. espCount)
            lineCountLabel:SetText("ESP Lines: " .. lineCount)
        end
    end)
end

local function SetupConnections()
    table.insert(Connections, RunService.RenderStepped:Connect(function()
        if UIClosed then return end
        UpdateESP()
    end))

    table.insert(Connections, LocalPlayer.CharacterAdded:Connect(function()
        TargetData.Current = nil
        TargetData.Position = nil
        task.defer(UpdateESP)
    end))

    local characters = workspace:FindFirstChild("Characters")
    if characters then
        table.insert(Connections, characters.ChildRemoved:Connect(function(child)
            RemoveESP(child)
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
