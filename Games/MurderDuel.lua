local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local Fluent = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Libs/Fluent.lua",
    true
))()

local State = {
    Filters = {
        TeamCheck = false,
    },
    ESP = {
        Enabled = false,
        Box = false,
        Skeleton = false,
        Name = false,
        Distance = false,
        Lines = false,
        RenderingDistance = 500,
    },
    Aim = {
        Enabled = false,
    },
    Visual = {
        FOVCircle = false,
        FOVRadius = 200,
        TracerOrigin = "BottomCenter",
    },
}

local ESPObjects = {}
local Connections = {}
local WindowRef = nil
local UIClosed = false
local IsCleaningUp = false

-- ============================================================
-- TARGET DATA (APENAS ARMAZENAMENTO)
-- ============================================================

local TargetData = {
    Current = nil,
    Position = nil,
    Distance = 0,
    Angle = 0,
    OnScreen = false,
    LineOfSight = false,
    IsValid = false,
    Mode = "None",
}

-- ============================================================
-- PLAYER CACHE
-- ============================================================

local PlayerCache = {}
local PlayerConnections = {}

local function RegisterCharacter(player, character)
    if character then
        PlayerCache[character] = player
    end
end

local function UnregisterCharacter(character)
    if character then
        PlayerCache[character] = nil
    end
end

local function UnregisterPlayer(player)
    for character, cachedPlayer in pairs(PlayerCache) do
        if cachedPlayer == player then
            PlayerCache[character] = nil
        end
    end
end

local function GetPlayerFromCharacter(char)
    if not char then
        return nil
    end

    local cached = PlayerCache[char]
    if cached and cached.Parent == Players then
        return cached
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character == char then
            RegisterCharacter(player, char)
            return player
        end
    end

    local userId = char:GetAttribute("UserId")
        or char:GetAttribute("PlayerUserId")
        or char:GetAttribute("OwnerUserId")

    if userId ~= nil then
        for _, player in ipairs(Players:GetPlayers()) do
            if player.UserId == tonumber(userId) then
                RegisterCharacter(player, char)
                return player
            end
        end
    end

    local byName = Players:FindFirstChild(char.Name)
    if byName and byName:IsA("Player") then
        RegisterCharacter(byName, char)
        return byName
    end

    return nil
end

local function CleanupPlayerConnections(player)
    local conns = PlayerConnections[player]
    if conns then
        for _, conn in ipairs(conns) do
            pcall(function() conn:Disconnect() end)
        end
        PlayerConnections[player] = nil
    end
end

local function BindPlayer(player)
    CleanupPlayerConnections(player)
    RegisterCharacter(player, player.Character)
    local conns = {}
    table.insert(conns, player.CharacterAdded:Connect(function(character)
        RegisterCharacter(player, character)
    end))
    table.insert(conns, player.CharacterRemoving:Connect(function(character)
        UnregisterCharacter(character)
    end))
    PlayerConnections[player] = conns
end

local function SetupPlayerCache()
    for _, player in ipairs(Players:GetPlayers()) do
        BindPlayer(player)
    end
    table.insert(Connections, Players.PlayerAdded:Connect(BindPlayer))
    table.insert(Connections, Players.PlayerRemoving:Connect(function(player)
        CleanupPlayerConnections(player)
        UnregisterPlayer(player)
    end))
end

local ESP_COLORS = {
    Box = Color3.fromRGB(78, 91, 222),
    Skeleton = Color3.fromRGB(78, 91, 222),
    Lines = Color3.fromRGB(78, 91, 222),
    Name = Color3.fromRGB(235, 235, 240),
    Distance = Color3.fromRGB(235, 235, 240),
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
        pcall(function() connection:Disconnect() end)
    end
    table.clear(Connections)
    for player, conns in pairs(PlayerConnections) do
        for _, conn in ipairs(conns) do
            pcall(function() conn:Disconnect() end)
        end
    end
    table.clear(PlayerConnections)
end

local IsAlive

local function GetHumanoid(char)
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

IsAlive = function(char)
    local humanoid = GetHumanoid(char)
    return humanoid ~= nil and humanoid.Health > 0
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
    return screenPosition, onScreen and screenPosition.Z > 0
end

local function GetDistance(a, b)
    return (a - b).Magnitude
end

local function GetESPCharacters()
    local result = {}
    local folder = workspace:FindFirstChild("Characters")
    if not folder then
        return result
    end
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model") and child ~= LocalPlayer.Character then
            local player = GetPlayerFromCharacter(child)
            if player and player ~= LocalPlayer then
                table.insert(result, child)
            end
        end
    end
    return result
end

local function AreSameTeam(a, b)
    if not a or not b then
        return false
    end

    local aSide = a:GetAttribute("MatchSide")
    local bSide = b:GetAttribute("MatchSide")

    if aSide ~= nil and bSide ~= nil then
        return aSide == bSide
    end

    local aPlayer = GetPlayerFromCharacter(a)
    local bPlayer = GetPlayerFromCharacter(b)

    if aPlayer and bPlayer and aPlayer.Team and bPlayer.Team then
        return aPlayer.Team == bPlayer.Team
    end

    return false
end

local function IsEnemy(char)
    if not char or char == LocalPlayer.Character then
        return false
    end

    if not IsAlive(char) then
        return false
    end

    if State.Filters.TeamCheck then
        local myChar = LocalPlayer.Character
        if myChar and AreSameTeam(myChar, char) then
            return false
        end
    end

    return true
end

local function GetAimScreenPoint()
    local camera = GetCamera()
    if not camera then
        return Vector2.new(Mouse.X, Mouse.Y)
    end
    return Vector2.new(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y * 0.5)
end

local UpdateFOVCircle

local function SetSharedFOV(value)
    State.Visual.FOVRadius = math.clamp(tonumber(value) or 200, 30, 500)
    UpdateFOVCircle()
end

local function IsTargetVisible(origin, targetPos, targetChar)
    local delta = targetPos - origin
    local distance = delta.Magnitude

    if distance < 0.1 then
        return true
    end

    local direction = delta.Unit

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character}

    local result = workspace:Raycast(origin, direction * distance, params)

    if not result then
        return true
    end

    local hitInstance = result.Instance
    if not hitInstance then
        return true
    end

    if targetChar and hitInstance:IsDescendantOf(targetChar) then
        return true
    end

    local hitChar = hitInstance:FindFirstAncestorOfClass("Model")
    if hitChar and hitChar == targetChar then
        return true
    end

    return false
end

local function GetCandidateMetadata(char)
    local head = char:FindFirstChild("Head") or GetTargetPart(char)
    if not head then
        return nil
    end

    local screenPos, onScreen = ProjectToScreen(head.Position)
    if not onScreen or not screenPos then
        return nil
    end

    local aimPoint = GetAimScreenPoint()
    local screenDistance = (Vector2.new(screenPos.X, screenPos.Y) - aimPoint).Magnitude

    if screenDistance > State.Visual.FOVRadius then
        return nil
    end

    local camera = GetCamera()
    if not camera then
        return nil
    end

    local origin = camera.CFrame.Position
    local lineOfSight = IsTargetVisible(origin, head.Position, char)

    if not lineOfSight then
        return nil
    end

    return {
        Character = char,
        Position = head.Position,
        ScreenPosition = Vector2.new(screenPos.X, screenPos.Y),
        ScreenDistance = screenDistance,
        OnScreen = onScreen,
        LineOfSight = lineOfSight,
    }
end

local function GetClosestTarget()
    local closest = nil
    local closestDist = State.Visual.FOVRadius

    for _, char in ipairs(GetESPCharacters()) do
        if IsEnemy(char) then
            local metadata = GetCandidateMetadata(char)
            if metadata and metadata.ScreenDistance < closestDist then
                closestDist = metadata.ScreenDistance
                closest = metadata
            end
        end
    end

    return closest
end

local function ApplyAimbot(camera, targetPosition)
    local origin = camera.CFrame.Position
    local direction = (targetPosition - origin).Unit
    camera.CFrame = CFrame.new(origin, origin + direction)
    return true
end

local CombatRenderStepName = "CAT_EMPIRE_Combat"
local CombatBound = false

local function ResetTargetData()
    TargetData.Current = nil
    TargetData.Position = nil
    TargetData.Distance = 0
    TargetData.Angle = 0
    TargetData.OnScreen = false
    TargetData.LineOfSight = false
    TargetData.IsValid = false
    TargetData.Mode = "None"
end

local function UpdateCamera()
    local camera = GetCamera()
    if not camera or not State.Aim.Enabled then
        return
    end

    if not TargetData.IsValid or not TargetData.Position then
        return
    end

    ApplyAimbot(camera, TargetData.Position)
end

local function CombatTrackingLoop(_deltaTime)
    if UIClosed then
        return
    end

    if not State.Aim.Enabled then
        ResetTargetData()
        return
    end

    local candidate = GetClosestTarget()
    local myChar = LocalPlayer.Character

    if candidate and myChar then
        TargetData.Current = candidate.Character
        TargetData.Position = candidate.Position
        TargetData.Distance = GetDistance(myChar:GetPivot().Position, candidate.Position)
        TargetData.Angle = candidate.ScreenDistance
        TargetData.OnScreen = candidate.OnScreen
        TargetData.LineOfSight = candidate.LineOfSight
        TargetData.IsValid = true
        TargetData.Mode = "Aimbot"
        UpdateCamera()
    else
        ResetTargetData()
    end
end

local function ResetCombatState()
    ResetTargetData()
end

local function StartCombatLoop()
    if CombatBound then
        return
    end

    local success, err = pcall(function()
        RunService:BindToRenderStep(
            CombatRenderStepName,
            Enum.RenderPriority.Camera.Value + 5,
            CombatTrackingLoop
        )
    end)

    if success then
        CombatBound = true
    else
        warn("[CAT_EMPIRE] Failed to bind CombatTrackingLoop:", err)
    end
end

local function StopCombatLoop()
    if CombatBound then
        local success, err = pcall(function()
            RunService:UnbindFromRenderStep(CombatRenderStepName)
        end)
        if not success then
            warn("[CAT_EMPIRE] Failed to unbind CombatTrackingLoop:", err)
        end
        CombatBound = false
    end

    ResetCombatState()
end

local function RefreshCombatTracking()
    if State.Aim.Enabled then
        StartCombatLoop()
    else
        StopCombatLoop()
    end
end

-- ============================================================
-- PLAYER ESP (PRESERVADO)
-- ============================================================

local ESP_GUI_NAME = "CAT_EMPIRE_PlayerESP"
local ESP_BLACK = Color3.fromRGB(0, 0, 0)
local ESP_WHITE = Color3.fromRGB(235, 235, 240)
local ESP_ACCENT = Color3.fromRGB(78, 91, 222)

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

    local head = char:FindFirstChild("Head")
    local leftFoot = FindPart(char, {"LeftFoot", "LeftLowerLeg", "Left Leg"})
    local rightFoot = FindPart(char, {"RightFoot", "RightLowerLeg", "Right Leg"})

    if head and (leftFoot or rightFoot) then
        local headTop = head.Position + Vector3.new(0, head.Size.Y * 0.5, 0)
        local footPoints = {}
        if leftFoot then table.insert(footPoints, GetFootBottom(leftFoot)) end
        if rightFoot then table.insert(footPoints, GetFootBottom(rightFoot)) end

        local headScreen = camera:WorldToViewportPoint(headTop)
        local lowestScreen = nil

        for _, point in ipairs(footPoints) do
            local screen = camera:WorldToViewportPoint(point)
            if screen.Z > 0 and (not lowestScreen or screen.Y > lowestScreen.Y) then
                lowestScreen = screen
            end
        end

        if headScreen.Z > 0 and lowestScreen then
            local rawHeight = lowestScreen.Y - headScreen.Y
            if rawHeight > 6 then
                local width = rawHeight / 1.8
                local height = rawHeight * 1.2
                local centerX = (headScreen.X + lowestScreen.X) * 0.5
                local centerY = (headScreen.Y + lowestScreen.Y) * 0.5
                return {
                    X = centerX - width * 0.5,
                    Y = centerY - height * 0.5,
                    Width = width,
                    Height = height,
                    Center = Vector2.new(centerX, centerY),
                    BottomCenter = Vector2.new(centerX, centerY + height * 0.5),
                    TopCenter = Vector2.new(centerX, centerY - height * 0.5),
                }
            end
        end
    end

    local ok, boxCFrame, boxSize = pcall(function()
        return char:GetBoundingBox()
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
        local screen = camera:WorldToViewportPoint(boxCFrame:PointToWorldSpace(localCorner))
        if screen.Z > 0 then
            minX = math.min(minX, screen.X)
            minY = math.min(minY, screen.Y)
            maxX = math.max(maxX, screen.X)
            maxY = math.max(maxY, screen.Y)
            valid = valid + 1
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

    return {
        X = minX,
        Y = minY,
        Width = width,
        Height = height,
        Center = Vector2.new((minX + maxX) * 0.5, (minY + maxY) * 0.5),
        BottomCenter = Vector2.new((minX + maxX) * 0.5, maxY),
        TopCenter = Vector2.new((minX + maxX) * 0.5, minY),
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
    if humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 then
        return R6_BONES
    end
    return R15_BONES
end

local function IsESPCharacterEligible(char)
    if not char or not char.Parent or char == LocalPlayer.Character or not IsAlive(char) then
        return false
    end
    local targetPlayer = GetPlayerFromCharacter(char)
    if not targetPlayer or targetPlayer == LocalPlayer then
        return false
    end
    if State.Filters.TeamCheck then
        local myChar = LocalPlayer.Character
        if myChar and AreSameTeam(myChar, char) then
            return false
        end
    end
    return true
end

local function GetESPDisplayName(char)
    local player = GetPlayerFromCharacter(char)
    if player then
        return (player.DisplayName and player.DisplayName ~= "") and player.DisplayName or player.Name
    end
    return char and char.Name or "NPC"
end

local function CreateESPData(char)
    local gui = GetESPGui()
    local data = {Skeleton = {}}

    data.BoxOutline = NewESPFrame("BoxOutline_" .. char.Name, gui)
    data.BoxOutline.ZIndex = 8
    data.BoxOutlineStroke = Instance.new("UIStroke")
    data.BoxOutlineStroke.Name = "Stroke"
    data.BoxOutlineStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    data.BoxOutlineStroke.Color = ESP_BLACK
    data.BoxOutlineStroke.Thickness = 4
    data.BoxOutlineStroke.Transparency = 0
    data.BoxOutlineStroke.Parent = data.BoxOutline

    data.Box = NewESPFrame("Box_" .. char.Name, gui)
    data.Box.ZIndex = 9
    data.BoxStroke = Instance.new("UIStroke")
    data.BoxStroke.Name = "Stroke"
    data.BoxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    data.BoxStroke.Color = ESP_COLORS.Box
    data.BoxStroke.Thickness = 2
    data.BoxStroke.Transparency = 0
    data.BoxStroke.Parent = data.Box

    data.Name = NewESPLabel("Name_" .. char.Name, gui)
    data.Distance = NewESPLabel("Distance_" .. char.Name, gui)
    data.Line = NewLine("Line_" .. char.Name, gui, 1)

    local maxBoneLines = math.max(#R15_BONES, #R6_BONES)
    for index = 1, maxBoneLines do
        data.Skeleton[index] = NewLine("Skeleton_" .. char.Name .. "_" .. index, gui, 1)
    end

    ESPObjects[char] = data
    return data
end

local function HideESPData(data)
    if not data then return end
    for _, key in ipairs({"BoxOutline", "Box", "Name", "Distance", "Line"}) do
        local object = data[key]
        if object then object.Visible = false end
    end
    for _, line in ipairs(data.Skeleton or {}) do
        line.Visible = false
    end
end

local function RemoveESP(char)
    local data = ESPObjects[char]
    if not data then return end
    for _, key in ipairs({"BoxOutline", "Box", "Name", "Distance", "Line"}) do
        local object = data[key]
        if object then pcall(function() object:Destroy() end) end
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
    return Vector2.new(camera.ViewportSize.X * 0.5, 2)
end

local function GetESPHeadTopScreen(char)
    local head = char and char:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then
        return nil
    end
    local topWorld = head.Position + Vector3.new(0, head.Size.Y * 0.5, 0)
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
                SetLine(line, Vector2.new(aScreen.X, aScreen.Y), Vector2.new(bScreen.X, bScreen.Y), 1, ESP_COLORS.Skeleton)
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
        labelY = labelY + 14
    else
        data.Name.Visible = false
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
        local headAnchor = GetESPHeadTopScreen(char) or bounds.TopCenter
        SetLine(data.Line, GetLocalScreenOrigin(), headAnchor, 1, ESP_COLORS.Lines)
    else
        data.Line.Visible = false
    end

    UpdateSkeleton(char, data)
end

local function RefreshESPEnabled()
    State.ESP.Enabled = State.ESP.Box
        or State.ESP.Skeleton
        or State.ESP.Name
        or State.ESP.Distance
        or State.ESP.Lines
    return State.ESP.Enabled
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

UpdateFOVCircle = function()
    if not State.Visual.FOVCircle then
        if FOVGui then
            pcall(function() FOVGui:Destroy() end)
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

    local aimPoint = GetAimScreenPoint()

    FOVFrame.Size = UDim2.fromOffset(State.Visual.FOVRadius * 2, State.Visual.FOVRadius * 2)
    FOVFrame.Position = UDim2.fromOffset(aimPoint.X, aimPoint.Y)

    if FOVStroke then
        FOVStroke.Color = ESP_COLORS.Box
    end
end

local function safeStep(stepName, fn)
    local ok, err = pcall(fn)
    if not ok then
        warn("[CAT_EMPIRE] Cleanup step '" .. stepName .. "' failed:", err)
    end
    return ok
end

local function Cleanup()
    if IsCleaningUp then
        return
    end

    IsCleaningUp = true
    UIClosed = true

    safeStep("DisconnectAll", DisconnectAll)
    safeStep("StopCombatLoop", StopCombatLoop)
    safeStep("ClearPlayerCache", function() table.clear(PlayerCache) end)
    safeStep("ClearESP", ClearESP)
    safeStep("DestroyESPGui", function() DestroyNamedGui(ESP_GUI_NAME) end)
    safeStep("DestroyFOVGui", function() DestroyNamedGui("FOVCircle") end)
    safeStep("ResetFOVGui", function()
        FOVGui = nil
        FOVFrame = nil
        FOVStroke = nil
    end)
    safeStep("ResetTargetData", ResetCombatState)

    if WindowRef then
        safeStep("DestroyWindow", function()
            pcall(function() WindowRef:Destroy() end)
            WindowRef = nil
        end)
    end

    IsCleaningUp = false
end

-- ============================================================
-- UI (COM DIAGNÓSTICO HONESTO)
-- ============================================================

local function CreateUI()
    local Window = Fluent:CreateWindow({
        Title = "CAT EMPIRE",
        SubTitle = "Murder Duel",
        TabWidth = 140,
        Size = UDim2.fromOffset(760, 460),
        Acrylic = true,
        Animated = true,
        Theme = "Crimson",
        MinimizeKey = Enum.KeyCode.LeftControl,
        ScreenGuiName = "CAT_EMPIRE",
    })

    WindowRef = Window

    local Tabs = {
        Combat = Window:AddTab({Title = "Combat", Icon = "solar/target-bold"}),
        Visuals = Window:AddTab({Title = "Visuals", Icon = "solar/eye-bold"}),
        Misc = Window:AddTab({Title = "Misc", Icon = "solar/widget-4-bold"}),
        Players = Window:AddTab({Title = "Players", Icon = "solar/users-group-rounded-bold"}),
        Settings = Window:AddTab({Title = "Settings", Icon = "solar/settings-bold"}),
    }

    local aimbotSection = Tabs.Combat:AddSection("Aimbot", "solar/target-bold")
    aimbotSection:AddToggle("AimbotEnabled", {
        Title = "Aimbot",
        Default = false,
        Callback = function(value)
            State.Aim.Enabled = value
            RefreshCombatTracking()
        end,
    })

    local combatFilterSection = Tabs.Combat:AddSection("Target Filters", "solar/filter-bold")
    combatFilterSection:AddToggle("CombatTeamCheck", {
        Title = "Team Check",
        Default = false,
        Callback = function(value)
            State.Filters.TeamCheck = value
            local other = Fluent.Options.TeamCheck
            if other and other.Value ~= value then
                other:SetValue(value)
            end
        end,
    })

    local espSection = Tabs.Visuals:AddSection("Players ESP", "solar/users-group-rounded-bold")
    espSection:AddSlider("ESPRenderDistance", {
        Title = "Rendering Distance",
        Min = 25,
        Max = 1000,
        Default = 500,
        Rounding = 0,
        Callback = function(value)
            State.ESP.RenderingDistance = value
            UpdateESP()
        end,
    })

    local function bindESPToggle(id, title, stateKey)
        espSection:AddToggle(id, {
            Title = title,
            Default = false,
            Callback = function(value)
                State.ESP[stateKey] = value
                RefreshESPEnabled()
                UpdateESP()
            end,
        })
    end

    bindESPToggle("ESPBox", "Box", "Box")
    bindESPToggle("ESPSkeleton", "Skeleton", "Skeleton")
    bindESPToggle("ESPName", "Name", "Name")
    bindESPToggle("ESPDistance", "Distance", "Distance")
    bindESPToggle("ESPLines", "Lines", "Lines")

    espSection:AddToggle("TeamCheck", {
        Title = "Team Check",
        Default = false,
        Callback = function(value)
            State.Filters.TeamCheck = value
            local other = Fluent.Options.CombatTeamCheck
            if other and other.Value ~= value then
                other:SetValue(value)
            end
            UpdateESP()
        end,
    })

    local colorPresets = {
        White = Color3.fromRGB(245, 245, 247),
        Red = Color3.fromRGB(235, 65, 75),
        Blue = Color3.fromRGB(35, 125, 255),
        Purple = Color3.fromRGB(118, 78, 255),
        Pink = Color3.fromRGB(255, 65, 150),
    }
    local colorNames = {"White", "Red", "Blue", "Purple", "Pink"}
    local colorsSection = Tabs.Visuals:AddSection("ESP Colors", "solar/palette-bold")

    local function bindESPColor(id, title, key, default)
        colorsSection:AddDropdown(id, {
            Title = title,
            Values = colorNames,
            Default = default,
            DropdownOutsideWindow = true,
            Callback = function(value)
                ESP_COLORS[key] = colorPresets[value] or colorPresets.Purple
                UpdateESP()
            end,
        })
    end

    bindESPColor("BoxColor", "Box", "Box", "Purple")
    bindESPColor("SkeletonColor", "Skeleton", "Skeleton", "Purple")
    bindESPColor("LineColor", "Lines", "Lines", "Purple")
    bindESPColor("NameColor", "Name", "Name", "White")
    bindESPColor("DistanceColor", "Distance", "Distance", "White")

    local fovSection = Tabs.Visuals:AddSection("FOV", "solar/radar-2-bold")
    fovSection:AddToggle("FOVCircle", {
        Title = "Draw FOV",
        Default = false,
        Callback = function(value)
            State.Visual.FOVCircle = value
            UpdateFOVCircle()
        end,
    })
    fovSection:AddSlider("FOVRadius", {
        Title = "FOV Radius",
        Min = 30,
        Max = 500,
        Default = 200,
        Rounding = 0,
        Callback = function(value)
            SetSharedFOV(value)
        end,
    })

    local function resolveGameName()
        local gameName = "Murder Duel"
        pcall(function()
            local info = MarketplaceService:GetProductInfo(game.PlaceId)
            if info and type(info.Name) == "string" and info.Name ~= "" then
                gameName = info.Name
            end
        end)
        return gameName
    end

    local function shortJobId()
        local id = tostring(game.JobId or "")
        if id == "" then
            return "N/A"
        end
        return #id > 18 and (string.sub(id, 1, 18) .. "...") or id
    end

    local serverSection = Tabs.Misc:AddSection("Servidor Atual", "solar/server-square-bold")
    serverSection:AddImage({
        Image = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150",
        AspectRatio = "4:1",
        Radius = 10,
    })
    local serverInfo = serverSection:AddParagraph({
        Title = resolveGameName(),
        Content = string.format(
            "Jogadores: %d/%d\nPlace ID: %s\nServer ID: %s",
            #Players:GetPlayers(),
            tonumber(Players.MaxPlayers) or 0,
            tostring(game.PlaceId),
            shortJobId()
        ),
    })

    local accountSection = Tabs.Misc:AddSection("Sua Conta", "solar/user-bold")
    accountSection:AddImage({
        Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150",
        AspectRatio = "4:1",
        Radius = 10,
    })
    accountSection:AddParagraph({
        Title = LocalPlayer.DisplayName,
        Content = string.format(
            "Display Name: %s\nNickname: @%s\nUser ID: %d\nConta: %d dias",
            LocalPlayer.DisplayName,
            LocalPlayer.Name,
            LocalPlayer.UserId,
            LocalPlayer.AccountAge
        ),
    })

    local communitySection = Tabs.Misc:AddSection("Comunidade", "solar/chat-round-bold")
    communitySection:AddDiscord({InviteCode = "yykVnTjd2Y"})
    communitySection:AddParagraph({
        Title = "Discord",
        Content = "https://discord.gg/yykVnTjd2Y",
    })
    communitySection:AddButton({
        Title = "Copiar Discord",
        Icon = "solar/copy-bold",
        Callback = function()
            local env = (getgenv and getgenv()) or _G
            local clipboard = (env and env.setclipboard) or rawget(_G, "setclipboard")
            if type(clipboard) == "function" then
                pcall(clipboard, "https://discord.gg/yykVnTjd2Y")
                Fluent:Notify({Title = "CAT EMPIRE", Content = "Link do Discord copiado.", Duration = 2})
            else
                Fluent:Notify({Title = "CAT EMPIRE", Content = "Clipboard indisponível.", Duration = 3})
            end
        end,
    })

    local listSection = Tabs.Players:AddSection("Players List", "solar/users-group-rounded-bold")
    local playerRows = {}
    for index = 1, 8 do
        playerRows[index] = listSection:AddParagraph({Title = "-", Content = ""})
    end

    local informationSection = Tabs.Players:AddSection("Information", "solar/info-circle-bold")
    local nearestName = informationSection:AddParagraph({Title = "Name: --", Content = ""})
    local nearestDistance = informationSection:AddParagraph({Title = "Distance: --", Content = ""})

    local developerSection = Tabs.Settings:AddSection("Developer", "solar/code-bold")
    developerSection:AddParagraph({Title = "Dev", Content = "Danonin"})

    Fluent.InterfaceManager:SetLibrary(Fluent)
    Fluent.InterfaceManager:SetFolder("CAT_EMPIRE")
    Fluent.SaveManager:SetLibrary(Fluent)
    Fluent.SaveManager:SetFolder("CAT_EMPIRE")
    Fluent.FloatingButtonManager:SetLibrary(Fluent)
    Fluent.FloatingButtonManager:SetFolder("CAT_EMPIRE/FloatingButtons")

    Fluent.InterfaceManager.Settings.Theme = "Crimson"
    Fluent.InterfaceManager.Settings.Animated = true
    Fluent.InterfaceManager.Settings.Transparency = true
    Fluent.InterfaceManager.Settings.MenuKeybind = "LeftControl"
    Fluent.InterfaceManager.Settings.Font = "GothamSSm"

    Fluent.InterfaceManager:BuildInterfaceSection(Tabs.Settings)
    Fluent.SaveManager:BuildConfigSection(Tabs.Settings)
    Fluent.FloatingButtonManager:BuildConfigSection(Tabs.Settings)

    local unloadSection = Tabs.Settings:AddSection("CAT EMPIRE", "solar/power-bold")
    unloadSection:AddButton({
        Title = "Unload CAT EMPIRE",
        Icon = "solar/power-bold",
        Callback = function()
            Cleanup()
        end,
    })

    task.spawn(function()
        while not UIClosed do
            task.wait(0.5)

            if serverInfo and serverInfo.SetDesc then
                serverInfo:SetDesc(string.format(
                    "Jogadores: %d/%d\nPlace ID: %s\nServer ID: %s",
                    #Players:GetPlayers(),
                    tonumber(Players.MaxPlayers) or 0,
                    tostring(game.PlaceId),
                    shortJobId()
                ))
            end

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
                                Distance = GetDistance(localRoot.Position, root.Position),
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
                local value = row
                    and string.format("%s  [%d]", row.Player.DisplayName or row.Player.Name, math.floor(row.Distance + 0.5))
                    or "-"
                if playerRows[index] and playerRows[index].SetTitle then
                    playerRows[index]:SetTitle(value)
                end
            end

            local nearest = rows[1]
            if nearest then
                nearestName:SetTitle("Name: " .. (nearest.Player.DisplayName or nearest.Player.Name))
                nearestDistance:SetTitle("Distance: " .. tostring(math.floor(nearest.Distance + 0.5)))
            else
                nearestName:SetTitle("Name: --")
                nearestDistance:SetTitle("Distance: --")
            end
        end
    end)
end

local function SetupConnections()
    SetupPlayerCache()

    table.insert(Connections, RunService.RenderStepped:Connect(function()
        if UIClosed then return end
        UpdateESP()
        if State.Visual.FOVCircle then
            UpdateFOVCircle()
        end
    end))

    table.insert(Connections, LocalPlayer.CharacterAdded:Connect(function()
        ResetCombatState()
        task.defer(UpdateESP)
    end))

    local characters = workspace:FindFirstChild("Characters")
    if characters then
        table.insert(Connections, characters.ChildRemoved:Connect(function(child)
            UnregisterCharacter(child)
            RemoveESP(child)
        end))
    end
end

local function Init()
    local env = (getgenv and getgenv()) or _G

    if type(env.CAT_EMPIRE_CLEANUP) == "function" then
        pcall(env.CAT_EMPIRE_CLEANUP)
    end

    UIClosed = false
    CombatBound = false

    env.CAT_EMPIRE_CLEANUP = function()
        Cleanup()
    end

    CreateUI()
    SetupConnections()

    Fluent:Notify({
        Title = "CAT EMPIRE",
        Content = "Visual systems loaded",
        Duration = 3,
    })
end

Init()
