local Helpers = {}

local function cleanClone(root)
    if not root then return nil end
    for _, object in ipairs(root:GetDescendants()) do
        if object:IsA("Script") or object:IsA("LocalScript") then
            object:Destroy()
        elseif object:IsA("BasePart") then
            object.Anchored = true
            object.CanCollide = false
            object.CanTouch = false
            object.CanQuery = false
            object.CastShadow = true
        elseif object:IsA("Humanoid") then
            object.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        end
    end
    return root
end

local function cloneArchivable(object)
    if not object then return nil end
    local old = object.Archivable
    object.Archivable = true
    local ok, clone = pcall(function() return object:Clone() end)
    object.Archivable = old
    if not ok then return nil end
    return clone
end

local function addRod(model, name, a, b, thickness, color)
    local delta = b - a
    if delta.Magnitude < 0.01 then return end

    local rod = Instance.new("Part")
    rod.Name = name
    rod.Size = Vector3.new(thickness, thickness, delta.Magnitude)
    rod.CFrame = CFrame.lookAt((a + b) * 0.5, b)
    rod.Anchored = true
    rod.CanCollide = false
    rod.CanTouch = false
    rod.CanQuery = false
    rod.CastShadow = false
    rod.Material = Enum.Material.Neon
    rod.Color = color
    rod.Parent = model
end

function Helpers.CreateESPPreview(localPlayer, colors)
    local character = localPlayer and localPlayer.Character
    local clone = cloneArchivable(character)

    if clone then
        clone.Name = "LocalPlayerESPPreview"
        cleanClone(clone)
        for _, child in ipairs(clone:GetChildren()) do
            if child:IsA("Tool") then child:Destroy() end
        end
        pcall(function() clone:PivotTo(CFrame.new()) end)
    else
        clone = Instance.new("Model")
        clone.Name = "ESPPreviewFallback"
        local body = Instance.new("Part")
        body.Size = Vector3.new(2, 5, 1)
        body.Anchored = true
        body.CanCollide = false
        body.Color = Color3.fromRGB(95, 95, 105)
        body.Parent = clone
    end

    local boxColor = (colors and colors.Box) or Color3.fromRGB(78, 91, 222)
    local skeletonColor = (colors and colors.Skeleton) or Color3.fromRGB(235, 235, 240)
    local tracerColor = (colors and colors.Lines) or Color3.fromRGB(78, 91, 222)

    local ok, boxCF, boxSize = pcall(function()
        return clone:GetBoundingBox()
    end)

    if ok and boxCF and boxSize then
        local half = boxSize * 0.5
        local corners = {
            boxCF:PointToWorldSpace(Vector3.new(-half.X,-half.Y,-half.Z)),
            boxCF:PointToWorldSpace(Vector3.new( half.X,-half.Y,-half.Z)),
            boxCF:PointToWorldSpace(Vector3.new(-half.X, half.Y,-half.Z)),
            boxCF:PointToWorldSpace(Vector3.new( half.X, half.Y,-half.Z)),
            boxCF:PointToWorldSpace(Vector3.new(-half.X,-half.Y, half.Z)),
            boxCF:PointToWorldSpace(Vector3.new( half.X,-half.Y, half.Z)),
            boxCF:PointToWorldSpace(Vector3.new(-half.X, half.Y, half.Z)),
            boxCF:PointToWorldSpace(Vector3.new( half.X, half.Y, half.Z)),
        }
        local edges = {
            {1,2},{3,4},{5,6},{7,8},
            {1,3},{2,4},{5,7},{6,8},
            {1,5},{2,6},{3,7},{4,8},
        }
        for i, edge in ipairs(edges) do
            addRod(clone, "ESP_Box_"..i, corners[edge[1]], corners[edge[2]], 0.035, boxColor)
        end

        local pairsToDraw = {
            {"Head","UpperTorso"},{"Head","Torso"},
            {"UpperTorso","LowerTorso"},
            {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
            {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
            {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
            {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
            {"Torso","Left Arm"},{"Torso","Right Arm"},{"Torso","Left Leg"},{"Torso","Right Leg"},
        }

        local drawn = {}
        local lineIndex = 0
        for _, pair in ipairs(pairsToDraw) do
            local a = clone:FindFirstChild(pair[1], true)
            local b = clone:FindFirstChild(pair[2], true)
            if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
                local key = pair[1]..">"..pair[2]
                if not drawn[key] then
                    drawn[key] = true
                    lineIndex = lineIndex + 1
                    addRod(clone, "ESP_Skeleton_"..lineIndex, a.Position, b.Position, 0.045, skeletonColor)
                end
            end
        end

        local target = clone:FindFirstChild("HumanoidRootPart", true)
            or clone:FindFirstChild("Torso", true)
            or clone:FindFirstChild("UpperTorso", true)

        if target and target:IsA("BasePart") then
            local start = boxCF.Position + Vector3.new(0, -half.Y - 1.5, half.Z + math.max(3, boxSize.Z * 2))
            addRod(clone, "ESP_Tracer", start, target.Position, 0.035, tracerColor)
        end
    end

    local camera = Instance.new("Camera")
    camera.FieldOfView = 30
    return clone, camera
end

local function wrapPreviewObject(object)
    local clone = cloneArchivable(object)
    if not clone then return nil end

    local model
    if clone:IsA("Model") then
        model = clone
    else
        model = Instance.new("Model")
        model.Name = "WeaponPreview"
        clone.Parent = model
    end

    cleanClone(model)
    pcall(function() model:PivotTo(CFrame.new()) end)
    return model
end

local function countParts(object)
    local count = 0
    for _, child in ipairs(object:GetDescendants()) do
        if child:IsA("BasePart") then count = count + 1 end
    end
    return count
end

function Helpers.FindWeaponVisual(localPlayer, replicatedStorage)
    local currentGun = tostring(localPlayer:GetAttribute("UseGun") or "")
    local weaponId = tostring(localPlayer:GetAttribute("WeaponId") or "")
    local best, bestScore = nil, -math.huge

    local function consider(object, bonus)
        if not object or not (object:IsA("Model") or object:IsA("Tool")) then return end
        if object == localPlayer.Character then return end
        if object:IsA("Model") and object:FindFirstChildOfClass("Humanoid") then return end

        local parts = countParts(object)
        if parts == 0 then return end

        local lowerName = string.lower(object.Name)
        local score = bonus + math.min(parts, 30)

        for _, id in ipairs({currentGun, weaponId}) do
            if id ~= "" then
                local lowerId = string.lower(id)
                if lowerName == lowerId then
                    score = score + 160
                elseif string.find(lowerName, lowerId, 1, true) then
                    score = score + 90
                end
                if tostring(object:GetAttribute("WeaponId") or "") == id then
                    score = score + 180
                end
            end
        end

        if score > bestScore then
            best = object
            bestScore = score
        end
    end

    local camera = workspace.CurrentCamera
    if camera then
        for _, object in ipairs(camera:GetChildren()) do
            consider(object, 120)
        end
        for _, object in ipairs(camera:GetDescendants()) do
            if object:IsA("Model") or object:IsA("Tool") then
                consider(object, 100)
            end
        end
    end

    local character = localPlayer.Character
    if character then
        for _, object in ipairs(character:GetChildren()) do
            consider(object, 80)
        end
    end

    if best then return best end

    if replicatedStorage then
        for _, object in ipairs(replicatedStorage:GetDescendants()) do
            if object:IsA("Model") then
                local lowerName = string.lower(object.Name)
                local exact = (currentGun ~= "" and lowerName == string.lower(currentGun))
                    or (weaponId ~= "" and lowerName == string.lower(weaponId))
                if exact then consider(object, 10) end
            end
        end
    end

    return best
end

function Helpers.CreateWeaponPreview(localPlayer, replicatedStorage)
    local source = Helpers.FindWeaponVisual(localPlayer, replicatedStorage)
    local model = wrapPreviewObject(source)

    if not model then
        model = Instance.new("Model")
        model.Name = "WeaponPreviewUnavailable"

        local body = Instance.new("Part")
        body.Size = Vector3.new(4.5, 0.7, 0.7)
        body.Anchored = true
        body.CanCollide = false
        body.Material = Enum.Material.Metal
        body.Color = Color3.fromRGB(80, 80, 90)
        body.Parent = model

        local barrel = Instance.new("Part")
        barrel.Size = Vector3.new(3.5, 0.25, 0.25)
        barrel.Position = Vector3.new(3.5, 0.1, 0)
        barrel.Anchored = true
        barrel.CanCollide = false
        barrel.Material = Enum.Material.Metal
        barrel.Color = Color3.fromRGB(110, 110, 120)
        barrel.Parent = model
    end

    local camera = Instance.new("Camera")
    camera.FieldOfView = 28
    return model, camera
end

function Helpers.AddRobloxProfileCard(section, localPlayer, players)
    local parent = section and section.Container
    if not parent then return nil end

    section._elementCount = (section._elementCount or 0) + 1

    local frame = Instance.new("Frame")
    frame.Name = "RobloxProfileCard"
    frame.Size = UDim2.new(1, 0, 0, 72)
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 29)
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    frame.LayoutOrder = section._elementCount
    frame.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(70, 70, 80)
    stroke.Transparency = 0.35
    stroke.Thickness = 1
    stroke.Parent = frame

    local avatar = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.Size = UDim2.fromOffset(50, 50)
    avatar.Position = UDim2.new(0, 11, 0.5, 0)
    avatar.AnchorPoint = Vector2.new(0, 0.5)
    avatar.BackgroundColor3 = Color3.fromRGB(38, 38, 44)
    avatar.BorderSizePixel = 0
    avatar.Image = "rbxthumb://type=AvatarHeadShot&id="
        .. tostring(localPlayer.UserId)
        .. "&w=150&h=150"
    avatar.Parent = frame

    local avatarCorner = Instance.new("UICorner")
    avatarCorner.CornerRadius = UDim.new(1, 0)
    avatarCorner.Parent = avatar

    local displayName = Instance.new("TextLabel")
    displayName.BackgroundTransparency = 1
    displayName.Position = UDim2.new(0, 73, 0, 14)
    displayName.Size = UDim2.new(1, -85, 0, 20)
    displayName.Font = Enum.Font.GothamSemibold
    displayName.TextSize = 14
    displayName.TextXAlignment = Enum.TextXAlignment.Left
    displayName.TextColor3 = Color3.fromRGB(245, 245, 247)
    displayName.Text = localPlayer.DisplayName
    displayName.Parent = frame

    local username = Instance.new("TextLabel")
    username.BackgroundTransparency = 1
    username.Position = UDim2.new(0, 73, 0, 37)
    username.Size = UDim2.new(1, -85, 0, 17)
    username.Font = Enum.Font.Gotham
    username.TextSize = 12
    username.TextXAlignment = Enum.TextXAlignment.Left
    username.TextColor3 = Color3.fromRGB(170, 170, 180)
    username.Text = "@" .. localPlayer.Name
    username.Parent = frame

    task.spawn(function()
        for _ = 1, 5 do
            local ok, content, ready = pcall(function()
                return players:GetUserThumbnailAsync(
                    localPlayer.UserId,
                    Enum.ThumbnailType.HeadShot,
                    Enum.ThumbnailSize.Size150x150
                )
            end)

            if ok and type(content) == "string" and content ~= "" then
                avatar.Image = content
                if ready then break end
            end
            task.wait(0.4)
        end
    end)

    return frame
end

return Helpers
