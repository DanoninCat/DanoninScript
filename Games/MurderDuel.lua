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
        TabWidth = 112,
        Size = UDim2.fromOffset(760, 460),
        Acrylic = false,
        Animated = false,
        Theme = "CAT EMPIRE",
        MinimizeKey = Enum.KeyCode.Unknown,
        ScreenGuiName = "CAT_EMPIRE",
    })

    WindowRef = Window

    local Tabs = {
        Combat = Window:AddTab({Title = "Combat", Icon = "pc", SubTabs = {"Aimbot"}}),
        Visuals = Window:AddTab({Title = "Visuals", Icon = "eye", SubTabs = {"Players", "Vehicles"}}),
        Exploits = Window:AddTab({Title = "Misc", Icon = "folder", SubTabs = {"Player", "Others", "Teleport"}}),
        Cloud = Window:AddTab({Title = "Players", Icon = "players"}),
        Config = Window:AddTab({Title = "Settings", Icon = "settings"}),
    }

    local combatGrid = Tabs.Combat:AddGroup({Columns = 2, Gap = 8})
    local combatLeft = combatGrid:AddElement()
    local combatRight = combatGrid:AddElement()

    combatLeft:AddSection("Aimbot")
    combatLeft:AddToggle("AimbotEnabled", {Title = "Aimbot", Default = false})
    Fluent.Options.AimbotEnabled:OnChanged(function(value)
        State.Aim.Enabled = value
        RefreshCombatTracking()
    end)

    combatRight:AddSection("Target Filters")
    combatRight:AddToggle("CombatTeamCheck", {Title = "Team Check", Default = false})
    Fluent.Options.CombatTeamCheck:OnChanged(function(value)
        State.Filters.TeamCheck = value
        if Fluent.Options.TeamCheck and Fluent.Options.TeamCheck.Value ~= value then
            Fluent.Options.TeamCheck:SetValue(value)
        end
    end)

    -- VISUALS
    local visualGrid = Tabs.Visuals:AddGroup({Columns = 2, Gap = 10})
    local visualLeft = visualGrid:AddElement()
    local visualRight = visualGrid:AddElement()
    local UpdatePreview

    visualLeft:AddSection("Players ESP")
    visualLeft:AddSlider("ESPRenderDistance", {Title = "Rendering Distance", Min = 25, Max = 1000, Default = 500, Rounding = 0})
    Fluent.Options.ESPRenderDistance:OnChanged(function(value)
        State.ESP.RenderingDistance = value
        UpdateESP()
    end)

    visualLeft:AddToggle("ESPBox", {Title = "Box", Default = false})
    Fluent.Options.ESPBox:OnChanged(function(value)
        State.ESP.Box = value
        RefreshESPEnabled()
        UpdateESP()
        UpdatePreview()
    end)

    visualLeft:AddToggle("ESPSkeleton", {Title = "Skeleton", Default = false})
    Fluent.Options.ESPSkeleton:OnChanged(function(value)
        State.ESP.Skeleton = value
        RefreshESPEnabled()
        UpdateESP()
        UpdatePreview()
    end)

    visualLeft:AddToggle("ESPName", {Title = "Name", Default = false})
    Fluent.Options.ESPName:OnChanged(function(value)
        State.ESP.Name = value
        RefreshESPEnabled()
        UpdateESP()
        UpdatePreview()
    end)

    visualLeft:AddToggle("ESPDistance", {Title = "Distance", Default = false})
    Fluent.Options.ESPDistance:OnChanged(function(value)
        State.ESP.Distance = value
        RefreshESPEnabled()
        UpdateESP()
        UpdatePreview()
    end)

    visualLeft:AddToggle("ESPLines", {Title = "Lines", Default = false})
    Fluent.Options.ESPLines:OnChanged(function(value)
        State.ESP.Lines = value
        RefreshESPEnabled()
        UpdateESP()
        UpdatePreview()
    end)

    visualLeft:AddToggle("TeamCheck", {Title = "Team Check", Default = false})
    Fluent.Options.TeamCheck:OnChanged(function(value)
        State.Filters.TeamCheck = value
        if Fluent.Options.CombatTeamCheck and Fluent.Options.CombatTeamCheck.Value ~= value then
            Fluent.Options.CombatTeamCheck:SetValue(value)
        end
        UpdateESP()
    end)

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
            local a = Vector2.new(preview.AbsoluteSize.X * 0.5, preview.AbsoluteSize.Y - 5)
            local b = Vector2.new(preview.AbsoluteSize.X * 0.5, 102)
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
                local a = Vector2.new(preview.AbsoluteSize.X * pair[1].X, 25 + 154 * pair[1].Y)
                local b = Vector2.new(preview.AbsoluteSize.X * pair[2].X, 25 + 154 * pair[2].Y)
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

    for _, optionName in ipairs({"ESPBox", "ESPSkeleton", "ESPName", "ESPDistance", "ESPLines"}) do
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
    local colorNames = {"White", "Red", "Blue", "Purple", "Pink"}

    local function BindESPColorSelect(id, title, key, defaultIndex)
        visualRight:AddSelect(id, {Title = title, Icon = "", Values = colorNames, ColorMap = colorPresets, Default = defaultIndex})
        Fluent.Options[id]:OnChanged(function(value)
            ESP_COLORS[key] = colorPresets[value] or colorPresets.Purple
            UpdateESP()
            UpdatePreview()
        end)
    end

    BindESPColorSelect("BoxColor", "Box", "Box", 4)
    BindESPColorSelect("SkeletonColor", "Skeleton", "Skeleton", 4)
    BindESPColorSelect("LineColor", "Lines", "Lines", 4)
    BindESPColorSelect("NameColor", "Name", "Name", 1)
    BindESPColorSelect("DistanceColor", "Distance", "Distance", 1)

    visualRight:AddSection("FOV")
    visualRight:AddToggle("FOVCircle", {Title = "Draw FOV", Default = false})
    Fluent.Options.FOVCircle:OnChanged(function(value)
        State.Visual.FOVCircle = value
        UpdateFOVCircle()
    end)

    visualRight:AddSlider("FOVRadius", {Title = "FOV Radius", Min = 30, Max = 500, Default = 200, Rounding = 0})
    Fluent.Options.FOVRadius:OnChanged(function(value)
        SetSharedFOV(value)
    end)

    local function AddInfoCard(section, imageSource, titleText, bodyText)
        local rows = section and section:FindFirstChild("Rows")
        if not rows then
            return nil, nil
        end

        local card = Instance.new("Frame")
        card.Name = "InfoCard"
        card.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
        card.BorderSizePixel = 0
        card.Size = UDim2.new(1, 0, 0, 96)
        card.Parent = rows

        local cardCorner = Instance.new("UICorner")
        cardCorner.CornerRadius = UDim.new(0, 5)
        cardCorner.Parent = card

        local cardStroke = Instance.new("UIStroke")
        cardStroke.Color = Color3.fromRGB(31, 31, 42)
        cardStroke.Transparency = 0.15
        cardStroke.Thickness = 1
        cardStroke.Parent = card

        local image = Instance.new("ImageLabel")
        image.Name = "CardImage"
        image.BackgroundColor3 = Color3.fromRGB(8, 8, 11)
        image.BorderSizePixel = 0
        image.Image = imageSource or ""
        image.ScaleType = Enum.ScaleType.Crop
        image.Position = UDim2.fromOffset(8, 8)
        image.Size = UDim2.fromOffset(80, 80)
        image.Parent = card

        local imageCorner = Instance.new("UICorner")
        imageCorner.CornerRadius = UDim.new(0, 6)
        imageCorner.Parent = image

        local title = Instance.new("TextLabel")
        title.Name = "CardTitle"
        title.BackgroundTransparency = 1
        title.BorderSizePixel = 0
        title.Text = tostring(titleText or "")
        title.TextColor3 = Color3.fromRGB(255, 255, 255)
        title.TextSize = 12
        title.Font = Enum.Font.GothamBold
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Position = UDim2.fromOffset(98, 8)
        title.Size = UDim2.new(1, -106, 0, 20)
        title.Parent = card

        local body = Instance.new("TextLabel")
        body.Name = "CardBody"
        body.BackgroundTransparency = 1
        body.BorderSizePixel = 0
        body.Text = tostring(bodyText or "")
        body.TextColor3 = Color3.fromRGB(218, 218, 228)
        body.TextSize = 10
        body.Font = Enum.Font.Gotham
        body.TextXAlignment = Enum.TextXAlignment.Left
        body.TextYAlignment = Enum.TextYAlignment.Top
        body.TextWrapped = true
        body.Position = UDim2.fromOffset(98, 30)
        body.Size = UDim2.new(1, -106, 1, -36)
        body.Parent = card

        return card, body
    end

    local function CreateTextInput(section, placeholder)
        local rows = section and section:FindFirstChild("Rows")
        if not rows then
            return nil
        end

        local row = Instance.new("Frame")
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.Size = UDim2.new(1, 0, 0, 34)
        row.Parent = rows

        local input = Instance.new("TextBox")
        input.Name = "CustomBackgroundURL"
        input.BackgroundColor3 = Color3.fromRGB(13, 13, 20)
        input.BorderSizePixel = 0
        input.ClearTextOnFocus = false
        input.PlaceholderText = placeholder or "https://..."
        input.PlaceholderColor3 = Color3.fromRGB(120, 120, 138)
        input.Text = ""
        input.TextColor3 = Color3.fromRGB(235, 235, 240)
        input.TextSize = 10
        input.Font = Enum.Font.Gotham
        input.TextXAlignment = Enum.TextXAlignment.Left
        input.Position = UDim2.fromOffset(2, 3)
        input.Size = UDim2.new(1, -4, 1, -6)
        input.Parent = row

        local inputCorner = Instance.new("UICorner")
        inputCorner.CornerRadius = UDim.new(0, 4)
        inputCorner.Parent = input

        local inputStroke = Instance.new("UIStroke")
        inputStroke.Color = Color3.fromRGB(31, 31, 42)
        inputStroke.Transparency = 0.15
        inputStroke.Thickness = 1
        inputStroke.Parent = input

        local inputPadding = Instance.new("UIPadding")
        inputPadding.PaddingLeft = UDim.new(0, 8)
        inputPadding.PaddingRight = UDim.new(0, 8)
        inputPadding.Parent = input

        return input
    end

    local function ResolveGameName()
        local gameName = "Murder Duel"
        pcall(function()
            local info = MarketplaceService:GetProductInfo(game.PlaceId)
            if info and type(info.Name) == "string" and info.Name ~= "" then
                gameName = info.Name
            end
        end)
        return gameName
    end

    local function ShortJobId()
        local id = tostring(game.JobId or "")
        if id == "" then
            return "N/A"
        end
        if #id > 18 then
            return string.sub(id, 1, 18) .. "..."
        end
        return id
    end

    local miscGrid = Tabs.Exploits:AddGroup({Columns = 2, Gap = 10})
    local miscLeft = miscGrid:AddElement()
    local miscRight = miscGrid:AddElement()

    local serverSection = miscLeft:AddSection("Servidor Atual")
    local _, serverInfoBody = AddInfoCard(
        serverSection,
        "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150",
        ResolveGameName(),
        string.format(
            "Jogadores: %d/%d\nPlace ID: %s\nServer ID: %s",
            #Players:GetPlayers(),
            tonumber(Players.MaxPlayers) or 0,
            tostring(game.PlaceId),
            ShortJobId()
        )
    )

    local accountSection = miscRight:AddSection("Sua Conta")
    AddInfoCard(
        accountSection,
        "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150",
        LocalPlayer.DisplayName,
        string.format(
            "Display Name: %s\nNickname: @%s\nUser ID: %d\nConta: %d dias",
            LocalPlayer.DisplayName,
            LocalPlayer.Name,
            LocalPlayer.UserId,
            LocalPlayer.AccountAge
        )
    )

    miscRight:AddSection("Comunidade")
    miscRight:AddParagraph({
        Title = "Discord",
        Content = "https://discord.gg/yykVnTjd2Y",
    })
    miscRight:AddButton({Title = "Copiar Discord", Callback = function()
        local env = (getgenv and getgenv()) or _G
        local clipboard = (env and env.setclipboard) or rawget(_G, "setclipboard")
        if type(clipboard) == "function" then
            pcall(clipboard, "https://discord.gg/yykVnTjd2Y")
            Fluent:Notify({Title = "CAT EMPIRE", Content = "Link do Discord copiado.", Duration = 2})
        else
            Fluent:Notify({Title = "CAT EMPIRE", Content = "Clipboard indisponível neste executor.", Duration = 3})
        end
    end})

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

    local configGrid = Tabs.Config:AddGroup({Columns = 1, Gap = 8})
    local configLeft = configGrid:AddElement()

    configLeft:AddSection("Developer")
    configLeft:AddParagraph({Title = "Dev", Content = "Danonin"})

    configLeft:AddSection("Interface")
    local initialUIScale = math.floor((Window:GetScale() * 100) + 0.5)
    configLeft:AddSlider("UISize", {Title = "UI Size", Min = 50, Max = 110, Default = initialUIScale, Rounding = 0})
    Fluent.Options.UISize:OnChanged(function(value)
        Window:SetScale(value / 100)
    end)

    local panelAccentPresets = {
        Crimson = Color3.fromRGB(220, 30, 60),
        Purple = Color3.fromRGB(92, 72, 255),
        Blue = Color3.fromRGB(45, 120, 255),
        Pink = Color3.fromRGB(230, 70, 180),
        White = Color3.fromRGB(225, 225, 235),
    }
    local panelFontPresets = {
        Gotham = Enum.Font.Gotham,
        SourceSans = Enum.Font.SourceSans,
        Code = Enum.Font.Code,
        Arial = Enum.Font.Arial,
        SciFi = Enum.Font.SciFi,
    }

    local defaultAccent = Color3.fromRGB(220, 30, 60)
    local defaultAccentDark = Color3.fromRGB(120, 15, 35)
    local defaultAccentSoft = Color3.fromRGB(235, 70, 95)
    local currentAccent = defaultAccent
    local currentAccentDark = defaultAccentDark
    local currentAccentSoft = defaultAccentSoft
    local currentFont = Enum.Font.Gotham

    local function SameColor(a, b)
        return math.abs(a.R - b.R) < 0.004
            and math.abs(a.G - b.G) < 0.004
            and math.abs(a.B - b.B) < 0.004
    end

    local function Darken(color)
        return Color3.new(color.R * 0.72, color.G * 0.72, color.B * 0.72)
    end

    local function Soften(color)
        return Color3.new(
            math.min(1, color.R * 1.24 + 0.04),
            math.min(1, color.G * 1.24 + 0.04),
            math.min(1, color.B * 1.24 + 0.04)
        )
    end

    local function RefreshPanelAccent(previousAccent, previousDark, previousSoft)
        if not Window.Gui or not Window.Gui.Parent then
            return
        end

        previousAccent = previousAccent or currentAccent
        previousDark = previousDark or currentAccentDark
        previousSoft = previousSoft or currentAccentSoft

        for _, object in ipairs(Window.Gui:GetDescendants()) do
            if object:IsA("GuiObject") then
                local background = object.BackgroundColor3
                if SameColor(background, defaultAccent) or SameColor(background, currentAccent) or SameColor(background, previousAccent) then
                    object.BackgroundColor3 = currentAccent
                elseif SameColor(background, defaultAccentDark) or SameColor(background, currentAccentDark) or SameColor(background, previousDark) then
                    object.BackgroundColor3 = currentAccentDark
                elseif SameColor(background, defaultAccentSoft) or SameColor(background, currentAccentSoft) or SameColor(background, previousSoft) then
                    object.BackgroundColor3 = currentAccentSoft
                end
            end

            if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
                if SameColor(object.TextColor3, defaultAccent) or SameColor(object.TextColor3, previousAccent) then
                    object.TextColor3 = currentAccent
                end
            end

            if object:IsA("UIStroke") then
                if SameColor(object.Color, defaultAccent) or SameColor(object.Color, previousAccent) then
                    object.Color = currentAccent
                elseif SameColor(object.Color, defaultAccentDark) or SameColor(object.Color, previousDark) then
                    object.Color = currentAccentDark
                elseif SameColor(object.Color, defaultAccentSoft) or SameColor(object.Color, previousSoft) then
                    object.Color = currentAccentSoft
                end
            end

            if object:IsA("ScrollingFrame") and (SameColor(object.ScrollBarImageColor3, defaultAccent) or SameColor(object.ScrollBarImageColor3, previousAccent)) then
                object.ScrollBarImageColor3 = currentAccent
            end
        end
    end

    local function ApplyPanelAccent(name)
        local previousAccent = currentAccent
        local previousDark = currentAccentDark
        local previousSoft = currentAccentSoft
        local newAccent = panelAccentPresets[name] or panelAccentPresets.Crimson
        currentAccent = newAccent
        currentAccentDark = Darken(newAccent)
        currentAccentSoft = Soften(newAccent)
        RefreshPanelAccent(previousAccent, previousDark, previousSoft)
    end

    local function RefreshPanelFont()
        if not Window.Gui or not Window.Gui.Parent then
            return
        end
        for _, object in ipairs(Window.Gui:GetDescendants()) do
            if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
                object.Font = currentFont
            end
        end
    end

    local function ApplyPanelFont(name)
        currentFont = panelFontPresets[name] or Enum.Font.Gotham
        RefreshPanelFont()
    end

    local backgroundLayer = Instance.new("ImageLabel")
    backgroundLayer.Name = "CAT_EMPIRE_Background"
    backgroundLayer.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
    backgroundLayer.BackgroundTransparency = 1
    backgroundLayer.BorderSizePixel = 0
    backgroundLayer.Image = ""
    backgroundLayer.ImageTransparency = 1
    backgroundLayer.ScaleType = Enum.ScaleType.Crop
    backgroundLayer.Size = UDim2.fromScale(1, 1)
    backgroundLayer.ZIndex = 0
    backgroundLayer.Parent = Window.Root

    local backgroundGradient = Instance.new("UIGradient")
    backgroundGradient.Enabled = false
    backgroundGradient.Rotation = 35
    backgroundGradient.Parent = backgroundLayer

    local function SetBaseTransparency(value)
        local sidebar = Window.SidebarVisual or Window.Sidebar
        local content = Window.ContentVisual or Window.Content
        if sidebar then sidebar.BackgroundTransparency = value end
        if content then content.BackgroundTransparency = value end
    end

    local backgroundPresets = {
        None = {
            A = Color3.fromRGB(8, 8, 10),
            B = Color3.fromRGB(8, 8, 11),
        },
        Purple = {
            A = Color3.fromRGB(24, 14, 52),
            B = Color3.fromRGB(8, 8, 14),
        },
        Blue = {
            A = Color3.fromRGB(10, 28, 55),
            B = Color3.fromRGB(7, 9, 18),
        },
        Red = {
            A = Color3.fromRGB(52, 12, 18),
            B = Color3.fromRGB(12, 7, 9),
        },
        Midnight = {
            A = Color3.fromRGB(7, 12, 28),
            B = Color3.fromRGB(4, 4, 8),
        },
    }

    local function ApplyBackgroundPreset(name)
        local preset = backgroundPresets[name] or backgroundPresets.None
        backgroundLayer.Image = ""
        backgroundLayer.ImageTransparency = 1

        if name == "None" then
            backgroundLayer.BackgroundTransparency = 1
            backgroundGradient.Enabled = false
            SetBaseTransparency(0)
            return
        end

        backgroundLayer.BackgroundTransparency = 0
        backgroundLayer.BackgroundColor3 = preset.A
        backgroundGradient.Color = ColorSequence.new(preset.A, preset.B)
        backgroundGradient.Enabled = true
        SetBaseTransparency(0.18)
    end

    local function SimpleHash(value)
        local hash = 5381
        for index = 1, #value do
            hash = (hash * 33 + string.byte(value, index)) % 2147483647
        end
        return tostring(hash)
    end

    local function ResolveCustomBackground(url)
        url = tostring(url or "")
        if url == "" then
            return nil, "Informe um link de imagem."
        end

        if string.match(url, "^rbxassetid://") or string.match(url, "^rbxthumb://") then
            return url
        end

        if not string.match(url, "^https?://") then
            return nil, "Use um link http(s), rbxassetid:// ou rbxthumb://."
        end

        local env = (getgenv and getgenv()) or _G
        local assetFn = (env and (env.getcustomasset or env.getsynasset))
            or rawget(_G, "getcustomasset")
            or rawget(_G, "getsynasset")
        local writeFn = (env and env.writefile) or rawget(_G, "writefile")

        if type(assetFn) ~= "function" or type(writeFn) ~= "function" then
            return nil, "Executor sem suporte a getcustomasset/writefile para links externos."
        end

        local extension = string.match(string.lower(url), "%.([%a%d]+)[%?#]?") or "png"
        if extension ~= "png" and extension ~= "jpg" and extension ~= "jpeg" and extension ~= "webp" then
            extension = "png"
        end

        local fileName = "CAT_EMPIRE_background_" .. SimpleHash(url) .. "." .. extension
        local ok, err = pcall(function()
            writeFn(fileName, game:HttpGet(url))
        end)
        if not ok then
            return nil, "Falha ao baixar background: " .. tostring(err)
        end

        local okAsset, asset = pcall(assetFn, fileName)
        if not okAsset or not asset then
            return nil, "Falha ao carregar a imagem local."
        end

        return asset
    end

    configLeft:AddDropdown("PanelColor", {
        Title = "Cor do Painel",
        Values = {"Crimson", "Purple", "Blue", "Pink", "White"},
        Default = 1,
    })
    Fluent.Options.PanelColor:OnChanged(ApplyPanelAccent)

    configLeft:AddDropdown("PanelFont", {
        Title = "Fonte",
        Values = {"Gotham", "SourceSans", "Code", "Arial", "SciFi"},
        Default = 1,
    })
    Fluent.Options.PanelFont:OnChanged(ApplyPanelFont)

    configLeft:AddDropdown("PanelBackground", {
        Title = "Background",
        Values = {"None", "Purple", "Blue", "Red", "Midnight"},
        Default = 1,
    })
    Fluent.Options.PanelBackground:OnChanged(ApplyBackgroundPreset)

    local customBackgroundSection = configLeft:AddSection("Background Personalizado")
    local customBackgroundInput = CreateTextInput(customBackgroundSection, "Cole o link direto da imagem")
    configLeft:AddButton({Title = "Aplicar Background do Link", Callback = function()
        local asset, err = ResolveCustomBackground(customBackgroundInput and customBackgroundInput.Text or "")
        if not asset then
            Fluent:Notify({Title = "CAT EMPIRE", Content = tostring(err or "Background inválido."), Duration = 3})
            return
        end

        backgroundGradient.Enabled = false
        backgroundLayer.BackgroundTransparency = 1
        backgroundLayer.Image = asset
        backgroundLayer.ImageTransparency = 0.32
        SetBaseTransparency(0.24)
        Fluent:Notify({Title = "CAT EMPIRE", Content = "Background personalizado aplicado.", Duration = 2})
    end})

    local panelKeybind = Enum.KeyCode.LeftControl
    local waitingForKeybind = false
    local keybindLabel = configLeft:AddLabel("Keybind: LeftControl")

    configLeft:AddButton({Title = "Alterar Keybind", Callback = function()
        waitingForKeybind = true
        keybindLabel:SetText("Keybind: pressione uma tecla...")
    end})

    table.insert(Connections, UserInputService.InputBegan:Connect(function(input, processed)
        if UIClosed then
            return
        end

        if waitingForKeybind then
            if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
                if input.KeyCode == Enum.KeyCode.Escape then
                    waitingForKeybind = false
                    keybindLabel:SetText("Keybind: " .. panelKeybind.Name)
                    return
                end

                panelKeybind = input.KeyCode
                waitingForKeybind = false
                keybindLabel:SetText("Keybind: " .. panelKeybind.Name)
            end
            return
        end

        if not processed and input.KeyCode == panelKeybind then
            Window:ToggleMinimize()
        end
    end))

    configLeft:AddParagraph({Title = "Open / Close", Content = "Use o botão CE ou o keybind configurado acima."})
    configLeft:AddButton({Title = "Unload CAT EMPIRE", Callback = function()
        Cleanup()
    end})

    task.spawn(function()
        while not UIClosed do
            task.wait(0.5)

            if serverInfoBody then
                serverInfoBody.Text = string.format(
                    "Jogadores: %d/%d\nPlace ID: %s\nServer ID: %s",
                    #Players:GetPlayers(),
                    tonumber(Players.MaxPlayers) or 0,
                    tostring(game.PlaceId),
                    ShortJobId()
                )
            end

            RefreshPanelAccent()
            RefreshPanelFont()

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
                if row then
                    playerRows[index]:SetText(string.format("%s  [%d]", row.Player.DisplayName or row.Player.Name, math.floor(row.Distance + 0.5)))
                else
                    playerRows[index]:SetText("-")
                end
            end

            local nearest = rows[1]
            if nearest then
                nearestNameLabel:SetText("Name: " .. (nearest.Player.DisplayName or nearest.Player.Name))
                nearestDistanceLabel:SetText("Distance: " .. string.format("%d", math.floor(nearest.Distance + 0.5)))
            else
                nearestNameLabel:SetText("Name: --")
                nearestDistanceLabel:SetText("Distance: --")
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
