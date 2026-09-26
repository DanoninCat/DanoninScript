local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local Core = {}
Core.VERSION = "1.0.0"

local Controller = {}
Controller.__index = Controller

local function clamp(v, a, b)
    return math.max(a, math.min(b, v))
end

local function getRoot(character)
    return character and (
        character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
    )
end

local function alive(character)
    if not character then return false end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0, humanoid
end

local function safeRemove(object)
    if not object then return end
    pcall(function()
        object.Visible = false
        object:Remove()
    end)
end

local function newDrawing(kind)
    if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
        return nil
    end
    local ok, object = pcall(Drawing.new, kind)
    return ok and object or nil
end

function Controller.new()
    local self = setmetatable({}, Controller)
    self.running = false
    self.connections = {}
    self.listeners = {}
    self.esp = {}
    self.currentTarget = nil
    self.fovCircle = nil
    self.drawingAvailable = type(Drawing) == "table" and type(Drawing.new) == "function"

    self.config = {
        aimEnabled = false,
        espEnabled = false,
        aimPart = "Head",
        aimMode = "Always",
        fov = 520,
        strength = 0.92,
        snap = false,
        stickyTarget = true,
        stickyFovMultiplier = 1.35,
        visibilityCheck = true,
        prediction = true,
        predictionSeconds = 0.035,
        maxDistance = 2500,
        teamCheck = false,
        autoScope = false,
        showFov = true,
        box = true,
        name = true,
        distance = true,
        healthBar = true,
        tracer = false,
        highlight = true,
        maxEspDistance = 3000,
    }

    return self
end

function Controller:On(eventName, callback)
    self.listeners[eventName] = self.listeners[eventName] or {}
    local bucket = self.listeners[eventName]
    table.insert(bucket, callback)
    local connected = true

    return function()
        if not connected then return end
        connected = false
        local index = table.find(bucket, callback)
        if index then table.remove(bucket, index) end
    end
end

function Controller:_emit(eventName, payload)
    for _, callback in ipairs(self.listeners[eventName] or {}) do
        task.spawn(function()
            pcall(callback, payload)
        end)
    end
end

function Controller:GetConfig()
    local copy = {}
    for key, value in pairs(self.config) do copy[key] = value end
    return copy
end

function Controller:SetConfig(patch)
    if type(patch) ~= "table" then return end

    for key, value in pairs(patch) do
        if self.config[key] ~= nil then
            self.config[key] = value
        end
    end

    if patch.aimEnabled == true and LocalPlayer then
        pcall(function()
            LocalPlayer:SetAttribute("AimAssistEnabled", false)
        end)
    end

    if patch.autoScope ~= nil and LocalPlayer then
        pcall(function()
            LocalPlayer:SetAttribute("AutoScopeEnabled", self.config.autoScope == true)
        end)
    end

    if patch.aimEnabled == false then
        self.currentTarget = nil
    end

    if patch.espEnabled == false then
        for _, visual in pairs(self.esp) do
            self:_hideESP(visual)
        end
    end

    self:_emit("configChanged", self:GetConfig())
end

function Controller:ApplyPreset(name)
    if name == "Rage" then
        self:SetConfig({
            fov = 2000,
            strength = 1,
            snap = true,
            stickyTarget = true,
            stickyFovMultiplier = 4,
            visibilityCheck = true,
            prediction = true,
            predictionSeconds = 0.04,
            aimMode = "Always",
            teamCheck = false,
        })
    elseif name == "Legit" then
        self:SetConfig({
            fov = 140,
            strength = 0.22,
            snap = false,
            stickyTarget = false,
            stickyFovMultiplier = 1.2,
            visibilityCheck = true,
            prediction = true,
            predictionSeconds = 0.02,
            aimMode = "RMB",
        })
    else
        self:SetConfig({
            fov = 520,
            strength = 0.92,
            snap = false,
            stickyTarget = true,
            stickyFovMultiplier = 1.35,
            visibilityCheck = true,
            prediction = true,
            predictionSeconds = 0.035,
            aimMode = "Always",
            teamCheck = false,
        })
    end
end

function Controller:_sameTeam(player)
    if not self.config.teamCheck then return false end
    return LocalPlayer
        and LocalPlayer.Team ~= nil
        and player.Team ~= nil
        and LocalPlayer.Team == player.Team
end

function Controller:_aimPart(character)
    if not character then return nil end
    local names = {
        self.config.aimPart,
        "Head",
        "UpperTorso",
        "Torso",
        "HumanoidRootPart",
    }

    for _, name in ipairs(names) do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            return part
        end
    end

    return getRoot(character)
end

function Controller:_validPlayer(player)
    if not player or player == LocalPlayer or self:_sameTeam(player) then
        return false
    end

    local character = player.Character
    local isAlive, humanoid = alive(character)
    if not isAlive then return false end

    local part = self:_aimPart(character)
    if not part then return false end

    local localRoot = getRoot(LocalPlayer and LocalPlayer.Character)
    if localRoot and (part.Position - localRoot.Position).Magnitude > self.config.maxDistance then
        return false
    end

    return true, character, humanoid, part
end

function Controller:_visible(character, part)
    if not self.config.visibilityCheck then return true end
    local camera = Workspace.CurrentCamera
    if not camera or not part then return false end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = LocalPlayer and LocalPlayer.Character and {LocalPlayer.Character} or {}
    params.IgnoreWater = true

    local result = Workspace:Raycast(camera.CFrame.Position, part.Position - camera.CFrame.Position, params)
    return result == nil or (result.Instance and result.Instance:IsDescendantOf(character))
end

function Controller:_predicted(part)
    if not self.config.prediction then return part.Position end
    return part.Position + part.AssemblyLinearVelocity * self.config.predictionSeconds
end

function Controller:_screen(worldPosition)
    local camera = Workspace.CurrentCamera
    if not camera then return nil, false end
    local vector, onScreen = camera:WorldToViewportPoint(worldPosition)
    return Vector2.new(vector.X, vector.Y), onScreen and vector.Z > 0
end

function Controller:_center()
    local camera = Workspace.CurrentCamera
    if not camera then return Vector2.zero end
    return Vector2.new(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y * 0.5)
end

function Controller:_targetStillValid(player)
    local ok, character, _, part = self:_validPlayer(player)
    if not ok or not self:_visible(character, part) then return false end

    local point, onScreen = self:_screen(self:_predicted(part))
    if not onScreen then return false end

    return (point - self:_center()).Magnitude <= self.config.fov * self.config.stickyFovMultiplier
end

function Controller:_acquireTarget()
    if self.config.stickyTarget and self:_targetStillValid(self.currentTarget) then
        return self.currentTarget
    end

    local center = self:_center()
    local localRoot = getRoot(LocalPlayer and LocalPlayer.Character)
    local bestPlayer, bestScore = nil, math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        local ok, character, _, part = self:_validPlayer(player)
        if ok and self:_visible(character, part) then
            local point, onScreen = self:_screen(self:_predicted(part))
            if onScreen then
                local screenDistance = (point - center).Magnitude
                if screenDistance <= self.config.fov then
                    local worldDistance = localRoot and (part.Position - localRoot.Position).Magnitude or 0
                    local score = screenDistance + worldDistance * 0.035
                    if score < bestScore then
                        bestScore = score
                        bestPlayer = player
                    end
                end
            end
        end
    end

    self.currentTarget = bestPlayer
    return bestPlayer
end

function Controller:_aimActive()
    if not self.config.aimEnabled then return false end
    if self.config.aimMode == "RMB" then
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    end
    return true
end

function Controller:_aim(player, dt)
    local ok, character, _, part = self:_validPlayer(player)
    if not ok or not self:_visible(character, part) then return end

    local camera = Workspace.CurrentCamera
    if not camera then return end

    local desired = CFrame.lookAt(camera.CFrame.Position, self:_predicted(part))
    if self.config.snap then
        camera.CFrame = desired
        return
    end

    local strength = clamp(self.config.strength, 0.01, 1)
    local alpha = 1 - math.pow(1 - strength, math.max(dt, 1 / 240) * 60)
    camera.CFrame = camera.CFrame:Lerp(desired, clamp(alpha, 0, 1))
end

function Controller:_hideESP(visual)
    if not visual then return end
    for _, key in ipairs({"box", "name", "distance", "healthBg", "health", "tracer"}) do
        if visual[key] then visual[key].Visible = false end
    end
    if visual.highlight then visual.highlight.Enabled = false end
end

function Controller:_makeESP(player)
    if self.esp[player] then return self.esp[player] end
    local visual = {player = player}

    if self.drawingAvailable then
        visual.box = newDrawing("Square")
        visual.name = newDrawing("Text")
        visual.distance = newDrawing("Text")
        visual.healthBg = newDrawing("Line")
        visual.health = newDrawing("Line")
        visual.tracer = newDrawing("Line")

        if visual.box then
            visual.box.Filled = false
            visual.box.Thickness = 1.5
            visual.box.Transparency = 1
        end

        for _, textObject in ipairs({visual.name, visual.distance}) do
            if textObject then
                textObject.Center = true
                textObject.Outline = true
                textObject.Size = 13
                textObject.Transparency = 1
            end
        end

        if visual.healthBg then
            visual.healthBg.Thickness = 4
            visual.healthBg.Transparency = 1
            visual.healthBg.Color = Color3.fromRGB(20, 20, 20)
        end

        if visual.health then
            visual.health.Thickness = 2
            visual.health.Transparency = 1
            visual.health.Color = Color3.fromRGB(80, 255, 120)
        end

        if visual.tracer then
            visual.tracer.Thickness = 1
            visual.tracer.Transparency = 1
        end
    end

    self.esp[player] = visual
    return visual
end

function Controller:_ensureHighlight(visual, character)
    if visual.highlight and visual.highlight.Parent ~= character then
        pcall(function() visual.highlight:Destroy() end)
        visual.highlight = nil
    end

    if not visual.highlight then
        local highlight = Instance.new("Highlight")
        highlight.Name = "CatEmpireScopedESP"
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillTransparency = 0.78
        highlight.OutlineTransparency = 0.05
        highlight.FillColor = Color3.fromRGB(255, 60, 60)
        highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        highlight.Parent = character
        visual.highlight = highlight
    end

    visual.highlight.Enabled = self.config.highlight
end

function Controller:_bounds(character)
    local camera = Workspace.CurrentCamera
    if not camera then return nil end

    local ok, cf, size = pcall(character.GetBoundingBox, character)
    if not ok then return nil end

    local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
    local offsets = {
        Vector3.new(-hx,-hy,-hz), Vector3.new(-hx,-hy,hz),
        Vector3.new(-hx, hy,-hz), Vector3.new(-hx, hy,hz),
        Vector3.new( hx,-hy,-hz), Vector3.new( hx,-hy,hz),
        Vector3.new( hx, hy,-hz), Vector3.new( hx, hy,hz),
    }

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local visible = false

    for _, offset in ipairs(offsets) do
        local point, onScreen = camera:WorldToViewportPoint(cf:PointToWorldSpace(offset))
        if point.Z > 0 then
            minX = math.min(minX, point.X)
            minY = math.min(minY, point.Y)
            maxX = math.max(maxX, point.X)
            maxY = math.max(maxY, point.Y)
            visible = visible or onScreen
        end
    end

    if minX == math.huge then return nil end
    return minX, minY, maxX, maxY, visible
end

function Controller:_updateESP(player)
    local visual = self:_makeESP(player)

    if not self.config.espEnabled then
        self:_hideESP(visual)
        return
    end

    local ok, character, humanoid, part = self:_validPlayer(player)
    if not ok then
        self:_hideESP(visual)
        return
    end

    local localRoot = getRoot(LocalPlayer and LocalPlayer.Character)
    local worldDistance = localRoot and (part.Position - localRoot.Position).Magnitude or 0
    if worldDistance > self.config.maxEspDistance then
        self:_hideESP(visual)
        return
    end

    self:_ensureHighlight(visual, character)
    if not self.drawingAvailable then return end

    local minX, minY, maxX, maxY, onScreen = self:_bounds(character)
    if not minX or not onScreen then
        self:_hideESP(visual)
        if visual.highlight then visual.highlight.Enabled = self.config.highlight end
        return
    end

    local width, height = maxX - minX, maxY - minY
    if width < 2 or height < 2 then
        self:_hideESP(visual)
        return
    end

    local target = self.currentTarget == player
    local targetColor = target and Color3.fromRGB(255, 220, 70) or Color3.fromRGB(255, 80, 80)

    if visual.box then
        visual.box.Visible = self.config.box
        visual.box.Position = Vector2.new(minX, minY)
        visual.box.Size = Vector2.new(width, height)
        visual.box.Color = targetColor
        visual.box.Thickness = target and 2.25 or 1.5
    end

    if visual.name then
        visual.name.Visible = self.config.name
        visual.name.Text = player.DisplayName ~= player.Name
            and (player.DisplayName .. " (@" .. player.Name .. ")")
            or player.Name
        visual.name.Position = Vector2.new((minX + maxX) / 2, minY - 16)
        visual.name.Color = target and Color3.fromRGB(255, 220, 70) or Color3.fromRGB(255, 255, 255)
    end

    if visual.distance then
        visual.distance.Visible = self.config.distance
        visual.distance.Text = string.format("%.0f studs", worldDistance)
        visual.distance.Position = Vector2.new((minX + maxX) / 2, maxY + 2)
        visual.distance.Color = Color3.fromRGB(255, 255, 255)
    end

    if visual.healthBg and visual.health then
        local ratio = clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
        local x = minX - 5
        visual.healthBg.Visible = self.config.healthBar
        visual.healthBg.From = Vector2.new(x, minY)
        visual.healthBg.To = Vector2.new(x, maxY)
        visual.health.Visible = self.config.healthBar
        visual.health.From = Vector2.new(x, maxY)
        visual.health.To = Vector2.new(x, maxY - height * ratio)
    end

    if visual.tracer then
        local camera = Workspace.CurrentCamera
        visual.tracer.Visible = self.config.tracer
        if camera then
            visual.tracer.From = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y - 2)
            visual.tracer.To = Vector2.new((minX + maxX) / 2, maxY)
            visual.tracer.Color = targetColor
        end
    end

    if visual.highlight then
        visual.highlight.Enabled = self.config.highlight
        visual.highlight.FillColor = target and Color3.fromRGB(255, 200, 40) or Color3.fromRGB(255, 60, 60)
    end
end

function Controller:_destroyESP(player)
    local visual = self.esp[player]
    if not visual then return end

    for _, key in ipairs({"box", "name", "distance", "healthBg", "health", "tracer"}) do
        safeRemove(visual[key])
    end

    if visual.highlight then
        pcall(function() visual.highlight:Destroy() end)
    end

    self.esp[player] = nil
end

function Controller:_updateFov()
    if not self.drawingAvailable then return end

    if not self.fovCircle then
        local circle = newDrawing("Circle")
        if circle then
            circle.Filled = false
            circle.NumSides = 96
            circle.Thickness = 1.5
            circle.Transparency = 0.65
            self.fovCircle = circle
        end
    end

    local circle = self.fovCircle
    if not circle then return end
    circle.Visible = self.config.aimEnabled and self.config.showFov
    if circle.Visible then
        circle.Position = self:_center()
        circle.Radius = self.config.fov
        circle.Color = self.currentTarget and Color3.fromRGB(255, 220, 70) or Color3.fromRGB(255, 255, 255)
    end
end

function Controller:_render(dt)
    if self:_aimActive() then
        local target = self:_acquireTarget()
        if target then self:_aim(target, dt) end
    else
        self.currentTarget = nil
    end

    self:_updateFov()

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            self:_updateESP(player)
        end
    end
end

function Controller:Start()
    if self.running then return true end
    self.running = true

    table.insert(self.connections, Players.PlayerRemoving:Connect(function(player)
        if self.currentTarget == player then self.currentTarget = nil end
        self:_destroyESP(player)
    end))

    table.insert(self.connections, RunService.RenderStepped:Connect(function(dt)
        if self.running then self:_render(dt) end
    end))

    return true
end

function Controller:Stop()
    if not self.running then return end
    self.running = false
    self.currentTarget = nil

    for _, connection in ipairs(self.connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(self.connections)

    for player in pairs(self.esp) do
        self:_destroyESP(player)
    end

    if self.fovCircle then
        safeRemove(self.fovCircle)
        self.fovCircle = nil
    end
end

function Controller:GetState()
    return {
        running = self.running,
        target = self.currentTarget and self.currentTarget.Name or nil,
        drawing = self.drawingAvailable,
        placeId = game.PlaceId,
        config = self:GetConfig(),
    }
end

Core.Controller = Controller

function Core.new()
    return Controller.new()
end

return Core
