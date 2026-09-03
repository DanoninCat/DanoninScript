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
        Enabled = true,
        Box = true,
        Skeleton = true,
        Name = true,
        Distance = true,
        Lines = true,
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

local IsAlive

local function GetPlayerFromCharacter(char)
    if not char then
        return nil
    end

    -- Direct Roblox character match.
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character == char then
            return player
        end
    end

    -- Some games mirror player characters under workspace.Characters.
    local byName = Players:FindFirstChild(char.Name)
    if byName and byName:IsA("Player") then
        return byName
    end

    -- Attribute fallbacks for mirrored/custom character models.
    local userId = char:GetAttribute("UserId")
        or char:GetAttribute("PlayerUserId")
        or char:GetAttribute("OwnerUserId")

    if userId ~= nil then
        for _, player in ipairs(Players:GetPlayers()) do
            if player.UserId == tonumber(userId) then
                return player
            end
        end
    end

    return nil
end

local function GetESPCharacters()
    local result = {}
    local folder = workspace:FindFirstChild("Characters")

    if not folder then
        return result
    end

    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model")
            and child ~= LocalPlayer.Character
        then
            local player = GetPlayerFromCharacter(child)

            -- NPCs are intentionally ignored.
            -- The local player is intentionally ignored.
            if player and player ~= LocalPlayer then
                table.insert(result, child)
            end
        end
    end

    return result
end

local function IsESPCharacterEligible(char)
    if not char
        or not char.Parent
        or char == LocalPlayer.Character
        or not IsAlive(char)
    then
        return false
    end

    local targetPlayer = GetPlayerFromCharacter(char)

    -- No NPC ESP and no local-player ESP.
    if not targetPlayer or targetPlayer == LocalPlayer then
        return false
    end

    if State.ESP.TeamCheck then
        local myChar = LocalPlayer.Character
        if myChar then
            local mySide = myChar:GetAttribute("MatchSide")
            local theirSide = char:GetAttribute("MatchSide")

            if mySide ~= nil
                and theirSide ~= nil
                and mySide == theirSide
            then
                return false
            end
        end

        if LocalPlayer.Team ~= nil
            and targetPlayer.Team ~= nil
            and LocalPlayer.Team == targetPlayer.Team
        then
            return false
        end
    end

    return true
end

local function GetESPDisplayName(char)
    local player = GetPlayerFromCharacter(char)
    if player then
        if player.DisplayName and player.DisplayName ~= "" then
            return player.DisplayName
        end
        return player.Name
    end

    return char and char.Name or "NPC"
end

local function GetHumanoid(char)
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

IsAlive = function(char)
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
local ESP_ACCENT = Color3.fromRGB(78, 91, 222)
local ESP_ARMOR = Color3.fromRGB(25, 120, 245)

local ESP_COLORS = {
    Box = ESP_ACCENT,
    Skeleton = ESP_ACCENT,
    Lines = ESP_ACCENT,
    Name = ESP_WHITE,
    Distance = ESP_WHITE,
}

local function GetESPGui()
    local gui = GetPlayerGui():FindFirstChild(ESP_GUI_NAME)
    if gui then
        return gui
    end

    gui = Instance.new("ScreenGui")
    gui.Name = ESP_GUI_NAME
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 100
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
    label.TextSize = 11
    label.TextColor3 = ESP_WHITE
    label.TextStrokeColor3 = ESP_BLACK
    label.TextStrokeTransparency = 0
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
    -- Center-anchor is important in Roblox. Rotation around a left-anchored
    -- frame makes the visual endpoint drift away from the requested points.
    line.AnchorPoint = Vector2.new(0.5, 0.5)
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
    if not line or not a or not b then
        return
    end

    local delta = b - a
    local length = delta.Magnitude

    if length < 0.5 then
        line.Visible = false
        return
    end

    -- Position the frame at the exact midpoint of the two endpoints.
    -- This keeps both ends glued to A and B after Rotation is applied.
    local midpoint = (a + b) * 0.5

    line.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
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
    local camera = GetCamera()
    if not camera or not char then
        return nil
    end

    -- Primary path mirrors the FiveM source:
    -- Head + lowest foot -> height -> width = height / 1.8.
    local head = char:FindFirstChild("Head")
    local leftFoot = FindPart(char, {
        "LeftFoot", "LeftLowerLeg", "Left Leg"
    })
    local rightFoot = FindPart(char, {
        "RightFoot", "RightLowerLeg", "Right Leg"
    })

    if head and (leftFoot or rightFoot) then
        local headTop = head.Position + Vector3.new(
            0,
            head.Size.Y * 0.5,
            0
        )

        local footPoints = {}
        if leftFoot then
            table.insert(footPoints, GetFootBottom(leftFoot))
        end
        if rightFoot then
            table.insert(footPoints, GetFootBottom(rightFoot))
        end

        local headScreen = camera:WorldToViewportPoint(headTop)
        local lowestScreen = nil

        for _, point in ipairs(footPoints) do
            local screen = camera:WorldToViewportPoint(point)
            if screen.Z > 0
                and (
                    not lowestScreen
                    or screen.Y > lowestScreen.Y
                )
            then
                lowestScreen = screen
            end
        end

        if headScreen.Z > 0 and lowestScreen then
            local rawHeight = lowestScreen.Y - headScreen.Y

            if rawHeight > 6 then
                local width = rawHeight / 1.8
                local height = rawHeight * 1.2
                local centerX = (
                    headScreen.X + lowestScreen.X
                ) * 0.5
                local centerY = (
                    headScreen.Y + lowestScreen.Y
                ) * 0.5

                return {
                    X = centerX - width * 0.5,
                    Y = centerY - height * 0.5,
                    Width = width,
                    Height = height,
                    Center = Vector2.new(centerX, centerY),
                    BottomCenter = Vector2.new(
                        centerX,
                        centerY + height * 0.5
                    ),
                    TopCenter = Vector2.new(
                        centerX,
                        centerY - height * 0.5
                    ),
                }
            end
        end
    end

    -- Fallback for custom rigs.
    local ok, boxCFrame, boxSize = pcall(function()
        local cf, size = char:GetBoundingBox()
        return cf, size
    end)

    if not ok or not boxCFrame or not boxSize then
        return nil
    end

    local half = boxSize * 0.5
    local corners = {
        Vector3.new(-half.X, -half.Y, -half.Z),
        Vector3.new(-half.X, -half.Y,  half.Z),
        Vector3.new(-half.X,  half.Y, -half.Z),
        Vector3.new(-half.X,  half.Y,  half.Z),
        Vector3.new( half.X, -half.Y, -half.Z),
        Vector3.new( half.X, -half.Y,  half.Z),
        Vector3.new( half.X,  half.Y, -half.Z),
        Vector3.new( half.X,  half.Y,  half.Z),
    }

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local valid = 0

    for _, localCorner in ipairs(corners) do
        local screen = camera:WorldToViewportPoint(
            boxCFrame:PointToWorldSpace(localCorner)
        )

        if screen.Z > 0 then
            minX = math.min(minX, screen.X)
            minY = math.min(minY, screen.Y)
            maxX = math.max(maxX, screen.X)
            maxY = math.max(maxY, screen.Y)
            valid += 1
        end
    end

    if valid < 4 then
        return nil
    end

    local width = maxX - minX
    local height = maxY - minY

    if width < 3 or height < 6 then
        return nil
    end

    local centerX = (minX + maxX) * 0.5
    local centerY = (minY + maxY) * 0.5

    return {
        X = minX,
        Y = minY,
        Width = width,
        Height = height,
        Center = Vector2.new(centerX, centerY),
        BottomCenter = Vector2.new(centerX, maxY),
        TopCenter = Vector2.new(centerX, minY),
    }
end

local R15_BONES = {
    {{"LowerTorso"}, {"UpperTorso"}},
    {{"UpperTorso"}, {"Head"}},

    {{"UpperTorso"}, {"LeftUpperArm"}},
    {{"LeftUpperArm"}, {"LeftLowerArm"}},
    {{"LeftLowerArm"}, {"LeftHand"}},

    {{"UpperTorso"}, {"RightUpperArm"}},
    {{"RightUpperArm"}, {"RightLowerArm"}},
    {{"RightLowerArm"}, {"RightHand"}},

    {{"LowerTorso"}, {"LeftUpperLeg"}},
    {{"LeftUpperLeg"}, {"LeftLowerLeg"}},
    {{"LeftLowerLeg"}, {"LeftFoot"}},

    {{"LowerTorso"}, {"RightUpperLeg"}},
    {{"RightUpperLeg"}, {"RightLowerLeg"}},
    {{"RightLowerLeg"}, {"RightFoot"}},
}

local R6_BONES = {
    {{"Torso"}, {"Head"}},
    {{"Torso"}, {"Left Arm"}},
    {{"Torso"}, {"Right Arm"}},
    {{"Torso"}, {"Left Leg"}},
    {{"Torso"}, {"Right Leg"}},
}

local function GetSkeletonPairs(char)
    local humanoid = GetHumanoid(char)
    if humanoid
        and humanoid.RigType == Enum.HumanoidRigType.R6
    then
        return R6_BONES
    end
    return R15_BONES
end

local function CreateESPData(char)
    local gui = GetESPGui()
    local data = {
        Skeleton = {},
    }

    data.BoxOutline = NewESPFrame(
        "BoxOutline_" .. char.Name,
        gui
    )
    data.BoxOutline.ZIndex = 8

    data.BoxOutlineStroke = Instance.new("UIStroke")
    data.BoxOutlineStroke.Name = "Stroke"
    data.BoxOutlineStroke.ApplyStrokeMode =
        Enum.ApplyStrokeMode.Border
    data.BoxOutlineStroke.Color = ESP_BLACK
    data.BoxOutlineStroke.Thickness = 4
    data.BoxOutlineStroke.Transparency = 0
    data.BoxOutlineStroke.Parent = data.BoxOutline

    data.Box = NewESPFrame("Box_" .. char.Name, gui)
    data.Box.ZIndex = 9

    data.BoxStroke = Instance.new("UIStroke")
    data.BoxStroke.Name = "Stroke"
    data.BoxStroke.ApplyStrokeMode =
        Enum.ApplyStrokeMode.Border
    data.BoxStroke.Color = ESP_COLORS.Box
    data.BoxStroke.Thickness = 2
    data.BoxStroke.Transparency = 0
    data.BoxStroke.Parent = data.Box

    data.Name = NewESPLabel("Name_" .. char.Name, gui)
    data.Distance = NewESPLabel("Distance_" .. char.Name, gui)
    data.Line = NewLine("Line_" .. char.Name, gui, 1)

    local maxBoneLines = math.max(#R15_BONES, #R6_BONES)
    for index = 1, maxBoneLines do
        data.Skeleton[index] = NewLine(
            "Skeleton_" .. char.Name .. "_" .. index,
            gui,
            1
        )
    end

    ESPObjects[char] = data
    return data
end

local function HideESPData(data)
    if not data then return end

    for _, key in ipairs({
        "BoxOutline", "Box", "Name", "Distance", "Line"
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
        "BoxOutline", "Box", "Name", "Distance", "Line"
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


local function GetLocalScreenOrigin()
    local camera = GetCamera()
    if not camera then
        return Vector2.new(0, 0)
    end

    -- Reference style: snapline originates at the top-center of the screen.
    return Vector2.new(
        camera.ViewportSize.X * 0.5,
        2
    )
end

local function GetESPHeadTopScreen(char)
    local head = char and char:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then
        return nil
    end

    local topWorld = head.Position + Vector3.new(
        0,
        head.Size.Y * 0.5,
        0
    )

    local screenPos, visible = ProjectToScreen(topWorld)
    if not screenPos or not visible then
        return nil
    end

    return Vector2.new(screenPos.X, screenPos.Y)
end

local function UpdateSkeleton(char, data)
    if not State.ESP.Skeleton then
        for _, line in ipairs(data.Skeleton) do
            line.Visible = false
        end
        return
    end

    local bonePairs = GetSkeletonPairs(char)

    for index, pair in ipairs(bonePairs) do
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
                    ESP_COLORS.Skeleton
                )
            else
                line.Visible = false
            end
        else
            line.Visible = false
        end
    end

    for index = #bonePairs + 1, #data.Skeleton do
        data.Skeleton[index].Visible = false
    end
end

local function UpdatePlayerESP(char, data, myRoot)
    if not State.ESP.Enabled or not IsESPCharacterEligible(char) then
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

    if data.BoxStroke then
        data.BoxStroke.Color = ESP_COLORS.Box
    end
    data.Name.TextColor3 = ESP_COLORS.Name
    data.Distance.TextColor3 = ESP_COLORS.Distance

    if State.ESP.Box then
        data.BoxOutline.Position = UDim2.fromOffset(x, y)
        data.BoxOutline.Size = UDim2.fromOffset(width, height)
        data.BoxOutline.Visible = true

        data.Box.Position = UDim2.fromOffset(x, y)
        data.Box.Size = UDim2.fromOffset(width, height)
        data.Box.Visible = true
    else
        data.BoxOutline.Visible = false
        data.Box.Visible = false
    end

    local bottomPadding = State.ESP.Box and 5 or 2

    local labelY = y + height + bottomPadding

    if State.ESP.Name then
        data.Name.Text = GetESPDisplayName(char)
        data.Name.Position = UDim2.fromOffset(x - 35, labelY)
        data.Name.Size = UDim2.fromOffset(width + 70, 14)
        data.Name.Visible = true
        labelY += 14
    else
        data.Name.Visible = false
    end

    if State.ESP.Distance then
        data.Distance.Text = string.format(
            "%d studs",
            math.floor(distance + 0.5)
        )
        data.Distance.Position = UDim2.fromOffset(x - 35, labelY)
        data.Distance.Size = UDim2.fromOffset(width + 70, 14)
        data.Distance.Visible = true
    else
        data.Distance.Visible = false
    end

    if State.ESP.Lines then
        local headAnchor =
            GetESPHeadTopScreen(char)
            or bounds.TopCenter

        SetLine(
            data.Line,
            GetLocalScreenOrigin(),
            headAnchor,
            1,
            ESP_COLORS.Lines
        )
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

    for _, char in ipairs(GetESPCharacters()) do
        current[char] = true

        if IsESPCharacterEligible(char) then
            local data = ESPObjects[char] or CreateESPData(char)
            UpdatePlayerESP(char, data, myRoot)
        elseif ESPObjects[char] then
            HideESPData(ESPObjects[char])
        end
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

local FOVGui = nil
local FOVFrame = nil
local FOVStroke = nil

local function CreateFOVCircle()
    if FOVGui and FOVGui.Parent then
        return FOVGui
    end

    DestroyNamedGui("FOVCircle")

    local gui = Instance.new("ScreenGui")
    gui.Name = "FOVCircle"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 110
    gui.Parent = GetPlayerGui()

    local circle = Instance.new("Frame")
    circle.Name = "Outline"
    circle.AnchorPoint = Vector2.new(0.5, 0.5)
    circle.BackgroundTransparency = 1
    circle.BorderSizePixel = 0
    circle.Parent = gui

    local round = Instance.new("UICorner")
    round.CornerRadius = UDim.new(1, 0)
    round.Parent = circle

    local outline = Instance.new("UIStroke")
    outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    outline.Thickness = 1
    outline.Transparency = 0.05
    outline.Parent = circle

    FOVGui = gui
    FOVFrame = circle
    FOVStroke = outline

    return gui
end

local function UpdateFOVCircle()
    if not State.Visual.FOVCircle then
        if FOVGui then
            pcall(function()
                FOVGui:Destroy()
            end)
        end
        FOVGui = nil
        FOVFrame = nil
        FOVStroke = nil
        return
    end

    CreateFOVCircle()

    local camera = GetCamera()
    if not camera or not FOVFrame then
        return
    end

    FOVFrame.Size = UDim2.fromOffset(
        State.Visual.FOVRadius * 2,
        State.Visual.FOVRadius * 2
    )
    FOVFrame.Position = UDim2.fromOffset(
        camera.ViewportSize.X * 0.5,
        camera.ViewportSize.Y * 0.5
    )

    if FOVStroke then
        FOVStroke.Color = ESP_COLORS.Box
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

-- ============================================================
-- CLEANUP
-- ============================================================

local function Cleanup(skipWindow)
    UIClosed = true
    DisconnectAll()

    ClearESP()
    DestroyNamedGui(ESP_GUI_NAME)
    DestroyNamedGui("FOVCircle")
    FOVGui = nil
    FOVFrame = nil
    FOVStroke = nil

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
        Size = UDim2.fromOffset(760, 460),
        Acrylic = false,
        Animated = false,
        Theme = "CAT EMPIRE",
        MinimizeKey = Enum.KeyCode.LeftControl,
        ScreenGuiName = "CAT_EMPIRE",
    })

    WindowRef = Window

    local Tabs = {
        Combat = Window:AddTab({
            Title = "Combat",
            Icon = "pc",
            SubTabs = {"Aimbot", "Silent"},
        }),
        Visuals = Window:AddTab({
            Title = "Visuals",
            Icon = "eye",
            SubTabs = {"Players", "Vehicles"},
        }),
        Exploits = Window:AddTab({
            Title = "Misc",
            Icon = "folder",
            SubTabs = {"Player", "Others", "Teleport"},
        }),
        Cloud = Window:AddTab({Title = "Players", Icon = "players"}),
        Config = Window:AddTab({Title = "Settings", Icon = "settings"}),
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
            TargetData.Distance = 0
            TargetData.Angle = 0
            TargetData.Visible = false
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

    combatRight:AddSection("Aim Modes")

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
    local UpdatePreview

    visualLeft:AddSection("Players ESP")

    visualLeft:AddSlider("ESPRenderDistance", {
        Title = "Rendering Distance",
        Min = 25,
        Max = 1000,
        Default = 500,
        Rounding = 0,
    })
    Fluent.Options.ESPRenderDistance:OnChanged(function(value)
        State.ESP.RenderingDistance = value
        UpdateESP()
    end)

    visualLeft:AddToggle("ESPBox", {Title = "Box", Default = true})
    Fluent.Options.ESPBox:OnChanged(function(value)
        State.ESP.Box = value
        UpdateESP()
        UpdatePreview()
    end)

    visualLeft:AddToggle("ESPSkeleton", {Title = "Skeleton", Default = true})
    Fluent.Options.ESPSkeleton:OnChanged(function(value)
        State.ESP.Skeleton = value
        UpdateESP()
        UpdatePreview()
    end)

    visualLeft:AddToggle("ESPName", {Title = "Name", Default = true})
    Fluent.Options.ESPName:OnChanged(function(value)
        State.ESP.Name = value
        UpdateESP()
        UpdatePreview()
    end)

    visualLeft:AddToggle("ESPDistance", {Title = "Distance", Default = true})
    Fluent.Options.ESPDistance:OnChanged(function(value)
        State.ESP.Distance = value
        UpdateESP()
        UpdatePreview()
    end)

    visualLeft:AddToggle("ESPLines", {Title = "Lines", Default = true})
    Fluent.Options.ESPLines:OnChanged(function(value)
        State.ESP.Lines = value
        UpdateESP()
        UpdatePreview()
    end)

    visualLeft:AddToggle("TeamCheck", {Title = "Team Check", Default = true})
    Fluent.Options.TeamCheck:OnChanged(function(value)
        State.ESP.TeamCheck = value
        if Fluent.Options.CombatTeamCheck
            and Fluent.Options.CombatTeamCheck.Value ~= value
        then
            Fluent.Options.CombatTeamCheck:SetValue(value)
        end
        UpdateESP()
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
    pBox.BorderColor3 = ESP_COLORS.Box
    pBox.BorderSizePixel = 1
    pBox.Position = UDim2.new(0.5, -46, 0, 25)
    pBox.Size = UDim2.fromOffset(92, 154)
    pBox.Parent = preview

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

    local previewSkeleton = {}
    local skeletonPoints = {
        {Vector2.new(0.5, 0.26), Vector2.new(0.5, 0.52)},
        {Vector2.new(0.5, 0.34), Vector2.new(0.36, 0.47)},
        {Vector2.new(0.5, 0.34), Vector2.new(0.64, 0.47)},
        {Vector2.new(0.5, 0.52), Vector2.new(0.40, 0.75)},
        {Vector2.new(0.5, 0.52), Vector2.new(0.60, 0.75)},
    }

    for index = 1, #skeletonPoints do
        local line = Instance.new("Frame")
        line.Name = "PreviewSkeleton_" .. index
        line.AnchorPoint = Vector2.new(0.5, 0.5)
        line.BackgroundColor3 = ESP_COLORS.Skeleton
        line.BorderSizePixel = 0
        line.Visible = false
        line.Parent = preview
        previewSkeleton[index] = line
    end

    local pLine = Instance.new("Frame")
    pLine.AnchorPoint = Vector2.new(0, 0.5)
    pLine.BackgroundColor3 = ESP_ACCENT
    pLine.BorderSizePixel = 0
    pLine.Position = UDim2.new(0.5, 0, 1, -5)
    pLine.Size = UDim2.fromOffset(0, 1)
    pLine.Parent = preview

    UpdatePreview = function()
        pBox.BorderColor3 = ESP_COLORS.Box
        pName.TextColor3 = ESP_COLORS.Name
        pDistance.TextColor3 = ESP_COLORS.Distance
        pLine.BackgroundColor3 = ESP_COLORS.Lines

        pBoxOutline.Visible = State.ESP.Box
        pBox.Visible = State.ESP.Box
        pName.Visible = State.ESP.Name
        pDistance.Visible = State.ESP.Distance

        if State.ESP.Lines then
            local a = Vector2.new(
                preview.AbsoluteSize.X * 0.5,
                preview.AbsoluteSize.Y - 5
            )
            local b = Vector2.new(
                preview.AbsoluteSize.X * 0.5,
                102
            )

            pLine.AnchorPoint = Vector2.new(0.5, 0.5)
            local d = b - a
            local mid = (a + b) * 0.5
            pLine.Position = UDim2.fromOffset(mid.X, mid.Y)
            pLine.Size = UDim2.fromOffset(d.Magnitude, 1)
            pLine.Rotation = math.deg(math.atan2(d.Y, d.X))
            pLine.Visible = true
        else
            pLine.Visible = false
        end

        for index, pair in ipairs(skeletonPoints) do
            local line = previewSkeleton[index]
            line.BackgroundColor3 = ESP_COLORS.Skeleton

            if State.ESP.Skeleton and preview.AbsoluteSize.X > 0 then
                local a = Vector2.new(
                    preview.AbsoluteSize.X * pair[1].X,
                    25 + 154 * pair[1].Y
                )
                local b = Vector2.new(
                    preview.AbsoluteSize.X * pair[2].X,
                    25 + 154 * pair[2].Y
                )
                local d = b - a
                local mid = (a + b) * 0.5
                line.Position = UDim2.fromOffset(mid.X, mid.Y)
                line.Size = UDim2.fromOffset(d.Magnitude, 1)
                line.Rotation = math.deg(math.atan2(d.Y, d.X))
                line.Visible = true
            else
                line.Visible = false
            end
        end
    end

    for _, optionName in ipairs({
        "ESPBox", "ESPSkeleton",
        "ESPName", "ESPDistance", "ESPLines"
    }) do
        Fluent.Options[optionName]:OnChanged(UpdatePreview)
    end
    task.defer(UpdatePreview)
    visualRight:AddSection("ESP Colors")

    local colorPresets = {
        White = Color3.fromRGB(245, 245, 247),
        Red = Color3.fromRGB(235, 65, 75),
        Blue = Color3.fromRGB(35, 125, 255),
        Purple = Color3.fromRGB(118, 78, 255),
        Pink = Color3.fromRGB(255, 65, 150),
    }

    local colorNames = {
        "White", "Red", "Blue", "Purple", "Pink",
    }

    local function BindESPColorSelect(
        id,
        title,
        key,
        defaultIndex
    )
        visualRight:AddSelect(id, {
            Title = title,
            Icon = "🪣",
            Values = colorNames,
            ColorMap = colorPresets,
            Default = defaultIndex,
        })

        Fluent.Options[id]:OnChanged(function(value)
            ESP_COLORS[key] =
                colorPresets[value]
                or colorPresets.Purple
            UpdateESP()
            UpdatePreview()
        end)
    end

    BindESPColorSelect("BoxColor", "Box", "Box", 4)
    BindESPColorSelect("SkeletonColor", "Skeleton", "Skeleton", 4)
    BindESPColorSelect("LineColor", "Lines", "Lines", 4)
    BindESPColorSelect("NameColor", "Name", "Name", 1)
    BindESPColorSelect("DistanceColor", "Distance", "Distance", 1)



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
        pcall(function()
            FOVController.SetBase(value)
        end)
    end)

    -- EXPLOITS
    Tabs.Exploits:AddSection("Camera")
    Tabs.Exploits:AddButton({
        Title = "Toggle Third Person",
        Callback = function()
            pcall(function()
                ThirdPerson.Toggle()
            end)
        end,
    })

    -- PLAYERS - source-inspired live list and information.
    local playersGrid = Tabs.Cloud:AddGroup({Columns = 2, Gap = 10})
    local playersLeft = playersGrid:AddElement()
    local playersRight = playersGrid:AddElement()

    playersLeft:AddSection("Players List")
    local playerRows = {}
    for index = 1, 8 do
        playerRows[index] = playersLeft:AddLabel("-")
    end

    playersRight:AddSection("Information")
    local nearestNameLabel = playersRight:AddLabel("Name: --")
    local nearestDistanceLabel = playersRight:AddLabel("Distance: --")

    -- CONFIG
    local configGrid = Tabs.Config:AddGroup({Columns = 1, Gap = 8})
    local configLeft = configGrid:AddElement()

    configLeft:AddSection("Interface")

    local initialUIScale = math.floor(
        (Window:GetScale() * 100) + 0.5
    )

    configLeft:AddSlider("UISize", {
        Title = "UI Size",
        Min = 50,
        Max = 110,
        Default = initialUIScale,
        Rounding = 0,
    })
    Fluent.Options.UISize:OnChanged(function(value)
        Window:SetScale(value / 100)
    end)

    configLeft:AddParagraph({
        Title = "Open / Close",
        Content = "Use the floating CE button outside the panel.",
    })

    configLeft:AddParagraph({
        Title = "Desktop Hotkey",
        Content = "Left Control • minimize / restore",
    })

    configLeft:AddButton({
        Title = "Unload CAT EMPIRE",
        Callback = function()
            Cleanup()
        end,
    })

    task.spawn(function()
        while not UIClosed do
            task.wait(0.5)

            -- Source-inspired players list sorted by distance.
            local localRoot = GetTargetPart(LocalPlayer.Character)
            local rows = {}

            if localRoot then
                for _, player in ipairs(Players:GetPlayers()) do
                    if player ~= LocalPlayer and player.Character then
                        local root = GetTargetPart(player.Character)
                        local humanoid = GetHumanoid(player.Character)
                        if root and humanoid and humanoid.Health > 0 then
                            table.insert(rows, {
                                Player = player,
                                Character = player.Character,
                                Distance = GetDistance(
                                    localRoot.Position,
                                    root.Position
                                ),
                            })
                        end
                    end
                end
            end

            table.sort(rows, function(a, b)
                return a.Distance < b.Distance
            end)

            for index = 1, #playerRows do
                local row = rows[index]
                if row then
                    playerRows[index]:SetText(
                        string.format(
                            "%s  [%d]",
                            row.Player.DisplayName or row.Player.Name,
                            math.floor(row.Distance + 0.5)
                        )
                    )
                else
                    playerRows[index]:SetText("-")
                end
            end

            local nearest = rows[1]
            if nearest then
                nearestNameLabel:SetText(
                    "Name: " .. (
                        nearest.Player.DisplayName
                        or nearest.Player.Name
                    )
                )
                nearestDistanceLabel:SetText(
                    "Distance: " .. string.format(
                        "%d",
                        math.floor(nearest.Distance + 0.5)
                    )
                )
            else
                nearestNameLabel:SetText("Name: --")
                nearestDistanceLabel:SetText("Distance: --")
            end
        end
    end)
end

local function SetupConnections()
    table.insert(Connections, RunService.RenderStepped:Connect(function()
        if UIClosed then return end
        UpdateESP()
        if State.Visual.FOVCircle then
            UpdateFOVCircle()
        end
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
        Content = "Visual systems loaded",
        Duration = 3,
    })
end

Init()
