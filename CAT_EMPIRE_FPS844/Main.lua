-- CAT EMPIRE | FPS 84448037861644 | Loader/Loader.lua | UI proprietaria
if game.PlaceId ~= 84448037861644 then return end

local Env = (getgenv and getgenv()) or _G
if type(Env.__CE_FPS844_CLEANUP) == "function" then pcall(Env.__CE_FPS844_CLEANUP) end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Weapons = ReplicatedStorage:WaitForChild("Weapons", 15)
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
if not (Weapons and Remotes) then return end

local function module(name)
    local obj = Weapons:FindFirstChild(name)
    if not obj then return nil end
    local ok, result = pcall(require, obj)
    if ok then return result end
end
local ClientState = module("ClientState") or {}
local ClientHitboxes = module("ClientHitboxes") or { parts = {}, folders = {} }
local WeaponData = module("WeaponData") or {}
local ModCatalog = module("ModCatalog")
local NetLag = nil
pcall(function() NetLag = require(ReplicatedStorage:WaitForChild("NetLag", 6)) end)
local CrewShared = nil
pcall(function() CrewShared = require(ReplicatedStorage:WaitForChild("CrewShared", 6)) end)

local Settings = {
    Aim = false, AimKey = "RightShift", AimHeld = false, AimSmooth = 0.28,
    AimPart = "Head", AimFOV = 200, AimWall = true,
    Silent = false, SilentPart = "Head", SilentWall = true,
    Trigger = false, TriggerKey = "T", TriggerHeld = false,
    TriggerTarget = "Any", TriggerDelay = 0.08, TriggerCooldown = 0.14,
    TriggerWall = true, TriggerOnlyADS = false,
    ESP = false, ESPBox = true, ESPName = true, ESPDistance = true,
    ESPLine = false, ESPColor = "#FF0000", ESPRange = 1500,
    Chams = false, ChamsColor = "#FF0000", ChamsTransparency = 0.45,
    FOVCircle = false, FOVColor = "#FF0000", FOVThickness = 1.6,
    NoSpread = false, AutoReload = false,
    SkinChanger = false, Skin = "DarkMatter", AutoRejoin = false,
    AntiAFK = false, BoostFPS = false, AutoCloseUI = false,
    AutoLoadAfterRejoin = false, AutoLoadProfile = false, Theme = "Dark",
    ProfileName = "Default",
}
local Connections, Visuals, Highlights = {}, {}, {}
local Alive = true
local SpreadBackup = {}
local BoostBackup = setmetatable({}, {__mode = "k"})
local LastSkinTool, LastSkinId, LastReload, LastTrigger = nil, nil, 0, 0
local TriggerStart, TriggerTarget, TriggerDown = nil, nil, false
local PreviewGUI, PreviewView, PreviewCamera = nil, nil, nil
local FOVDrawing = nil
local PROFILE_DIR = "CAT_EMPIRE/FPS844/84448037861644"

local function connect(signal, fn)
    local conn = signal:Connect(fn)
    table.insert(Connections, conn)
    return conn
end
local function rgb(hex)
    local valid = type(hex) == "string" and hex:match("^#%x%x%x%x%x%x$")
    if not valid then return Color3.fromRGB(255, 0, 0) end
    return Color3.fromRGB(tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16))
end
local function hex(c)
    return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end
local function currentTool()
    local ch = LocalPlayer.Character
    if not ch then return nil end
    for _, child in ipairs(ch:GetChildren()) do
        if child:IsA("Tool") and child:GetAttribute("Weapon") then return child end
    end
end
local function getHumanoid(model)
    return model and model:FindFirstChildOfClass("Humanoid")
end
local function validCharacter(char)
    if not char or char == LocalPlayer.Character or not char.Parent then return false end
    local humanoid = getHumanoid(char)
    local root = char:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then return false end
    if char:GetAttribute("InSafeZone") then return false end
    if char:GetAttribute("InFarmZone") and char:GetAttribute("PvPSafe") then return false end
    if CrewShared and type(CrewShared.Same) == "function" then
        local ok, same = pcall(CrewShared.Same, LocalPlayer, char)
        if ok and same then return false end
    end
    local player = Players:GetPlayerFromCharacter(char)
    if player and LocalPlayer.Team and player.Team == LocalPlayer.Team and not LocalPlayer.Neutral then
        return false
    end
    return true
end
local function candidates()
    local chars, seen = {}, {}
    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        if char and not seen[char] and validCharacter(char) then
            seen[char] = true
            table.insert(chars, char)
        end
    end
    local dummies = workspace:FindFirstChild("Dummies", true)
    if dummies then
        for _, obj in ipairs(dummies:GetChildren()) do
            if obj:IsA("Model") and validCharacter(obj) and not seen[obj] then
                seen[obj] = true
                table.insert(chars, obj)
            end
        end
    end
    return chars
end
local function aimPart(char, selection)
    if selection == "Torso" then
        return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
    elseif selection == "Any" then
        return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
    end
    return char:FindFirstChild("Head") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart")
end
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true
local function visible(char, point, origin)
    origin = origin or Camera.CFrame.Position
    local blacklist = { LocalPlayer.Character }
    for _, n in ipairs({"FX", "ClientHitboxes"}) do
        local obj = workspace:FindFirstChild(n)
        if obj then table.insert(blacklist, obj) end
    end
    losParams.FilterDescendantsInstances = blacklist
    local delta = point - origin
    local hit = workspace:Raycast(origin, delta, losParams)
    return not hit or hit.Instance:IsDescendantOf(char)
end
local function bestTarget(radius, selection, requireLOS)
    Camera = workspace.CurrentCamera or Camera
    local midpoint = Camera.ViewportSize * 0.5
    local best, bestDist = nil, radius
    for _, char in ipairs(candidates()) do
        local part = aimPart(char, selection)
        if part then
            local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
            if onScreen and pos.Z > 0 then
                local distance = (Vector2.new(pos.X, pos.Y) - midpoint).Magnitude
                if distance < bestDist and (not requireLOS or visible(char, part.Position)) then
                    bestDist = distance
                    best = {char = char, part = part, pos = part.Position}
                end
            end
        end
    end
    return best
end

local function newDraw(kind)
    if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then return nil end
    local ok, obj = pcall(Drawing.new, kind)
    if ok then return obj end
end
local function makeESP()
    return {
        box = newDraw("Square"), name = newDraw("Text"),
        distance = newDraw("Text"), line = newDraw("Line"),
    }
end
local function eraseESP(record)
    for _, obj in pairs(record) do if obj then pcall(function() obj:Remove() end) end end
end
local function hideESP(record)
    for _, obj in pairs(record) do if obj then obj.Visible = false end end
end
local function screenBounds(char)
    local ok, cf, size = pcall(char.GetBoundingBox, char)
    if not ok then return end
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local front = false
    for x = -1, 1, 2 do
        for y = -1, 1, 2 do
            for z = -1, 1, 2 do
                local p = cf:PointToWorldSpace(Vector3.new(size.X * x / 2, size.Y * y / 2, size.Z * z / 2))
                local projected = Camera:WorldToViewportPoint(p)
                if projected.Z > 0 then
                    front = true
                    minX, minY = math.min(minX, projected.X), math.min(minY, projected.Y)
                    maxX, maxY = math.max(maxX, projected.X), math.max(maxY, projected.Y)
                end
            end
        end
    end
    if not front then return end
    return minX, minY, maxX, maxY
end
local function updateESP()
    local active = {}
    local origin = Camera.CFrame.Position
    if Settings.ESP then
        for _, char in ipairs(candidates()) do
            local root = char:FindFirstChild("HumanoidRootPart")
            if root and (root.Position - origin).Magnitude <= Settings.ESPRange then
                active[char] = true
                if not Visuals[char] then Visuals[char] = makeESP() end
                local record = Visuals[char]
                local x1, y1, x2, y2 = screenBounds(char)
                if x1 and (x2 > 0 and x1 < Camera.ViewportSize.X and y2 > 0 and y1 < Camera.ViewportSize.Y) then
                    local c = rgb(Settings.ESPColor)
                    if record.box then
                        record.box.Visible = Settings.ESPBox
                        record.box.Filled = false
                        record.box.Thickness = 1.5
                        record.box.Color = c
                        record.box.Position = Vector2.new(x1, y1)
                        record.box.Size = Vector2.new(x2-x1, y2-y1)
                    end
                    if record.name then
                        local player = Players:GetPlayerFromCharacter(char)
                        record.name.Visible = Settings.ESPName
                        record.name.Size = 14
                        record.name.Center = true
                        record.name.Outline = true
                        record.name.Color = c
                        record.name.Text = player and player.DisplayName or char.Name
                        record.name.Position = Vector2.new((x1+x2)*0.5, y1-19)
                    end
                    if record.distance then
                        record.distance.Visible = Settings.ESPDistance
                        record.distance.Size = 13
                        record.distance.Center = true
                        record.distance.Outline = true
                        record.distance.Color = c
                        record.distance.Text = string.format("%d", (root.Position-origin).Magnitude)
                        record.distance.Position = Vector2.new((x1+x2)*0.5, y2+3)
                    end
                    if record.line then
                        record.line.Visible = Settings.ESPLine
                        record.line.Color = c
                        record.line.Thickness = 1
                        record.line.From = Vector2.new(Camera.ViewportSize.X * 0.5, Camera.ViewportSize.Y)
                        record.line.To = Vector2.new((x1+x2)*0.5,y2)
                    end
                else hideESP(record) end
            end
        end
    end
    for char, record in pairs(Visuals) do
        if not active[char] then
            eraseESP(record)
            Visuals[char] = nil
        end
    end
end
local function updateChams()
    local active = {}
    if Settings.Chams then
        for _, char in ipairs(candidates()) do
            active[char] = true
            if not Highlights[char] or not Highlights[char].Parent then
                local glow = Instance.new("Highlight")
                glow.Name = "CAT_EMPIRE_FPS844_Chams"
                glow.Adornee = char
                glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                glow.Parent = char
                Highlights[char] = glow
            end
            local glow = Highlights[char]
            glow.Enabled = true
            glow.FillColor = rgb(Settings.ChamsColor)
            glow.OutlineColor = rgb(Settings.ChamsColor)
            glow.FillTransparency = Settings.ChamsTransparency
            glow.OutlineTransparency = 0
        end
    end
    for char, glow in pairs(Highlights) do
        if not active[char] then
            pcall(function() glow:Destroy() end)
            Highlights[char] = nil
        end
    end
end
local function updateCircle()
    if not FOVDrawing then FOVDrawing = newDraw("Circle") end
    if not FOVDrawing then return end
    FOVDrawing.Visible = Settings.FOVCircle
    FOVDrawing.Filled = false
    FOVDrawing.NumSides = 80
    FOVDrawing.Transparency = 1
    FOVDrawing.Thickness = Settings.FOVThickness
    FOVDrawing.Color = rgb(Settings.FOVColor)
    FOVDrawing.Radius = Settings.AimFOV
    FOVDrawing.Position = Camera.ViewportSize * 0.5
end
local function updateAim(dt)
    if not Settings.Aim or not Settings.AimHeld or UIS:GetFocusedTextBox() then return end
    local t = bestTarget(Settings.AimFOV, Settings.AimPart, Settings.AimWall)
    if t then
        local cf = Camera.CFrame
        local wanted = CFrame.lookAt(cf.Position, t.pos)
        local alpha = math.clamp(1 - (1 - Settings.AimSmooth)^(math.max(dt, 0.001)*60), 0, 1)
        Camera.CFrame = cf:Lerp(wanted, alpha)
    end
end
local function releaseTrigger()
    if TriggerDown then
        TriggerDown = false
        if type(mouse1release) == "function" then pcall(mouse1release) else
            pcall(function() VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0) end)
        end
    end
end
local function pulseTrigger()
    if TriggerDown then return end
    TriggerDown = true
    if type(mouse1press) == "function" then pcall(mouse1press) else
        pcall(function() VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0) end)
    end
    task.delay(0.035, releaseTrigger)
end
local function underCrosshair()
    local ch = LocalPlayer.Character
    if not ch then return nil end
    local exclude = {ch}
    local fx = workspace:FindFirstChild("FX")
    if fx then table.insert(exclude, fx) end
    losParams.FilterDescendantsInstances = exclude
    local start = Camera.CFrame.Position
    local direction = Camera.CFrame.LookVector * 2000
    local hit = workspace:Raycast(start, direction, losParams)
    if not hit then return nil end
    local meta = ClientHitboxes.parts and ClientHitboxes.parts[hit.Instance]
    local char = meta and meta.char or hit.Instance:FindFirstAncestorOfClass("Model")
    if not validCharacter(char) then return nil end
    local partName = meta and meta.name or hit.Instance.Name
    if Settings.TriggerTarget == "Head" and partName ~= "Head" then return nil end
    if Settings.TriggerTarget == "Torso" and not (partName == "UpperTorso" or partName == "Torso" or partName == "LowerTorso") then return nil end
    return char, partName
end
local function updateTrigger()
    if not (Settings.Trigger and Settings.TriggerHeld) or UIS:GetFocusedTextBox() then
        TriggerStart, TriggerTarget = nil, nil
        return
    end
    if Settings.TriggerOnlyADS and not ClientState.Aiming then
        TriggerStart, TriggerTarget = nil, nil
        return
    end
    local target
    if Settings.TriggerWall then
        target = underCrosshair()
    else
        local choice = bestTarget(4, Settings.TriggerTarget, false)
        target = choice and choice.char or nil
    end
    if not target then TriggerStart, TriggerTarget = nil, nil; return end
    if target ~= TriggerTarget then TriggerTarget, TriggerStart = target, os.clock() end
    local now = os.clock()
    if now - TriggerStart >= Settings.TriggerDelay and now - LastTrigger >= Settings.TriggerCooldown then
        LastTrigger = now
        pulseTrigger()
    end
end
local function setNoSpread(enabled)
    for _, data in pairs(WeaponData) do
        if type(data) == "table" and type(data.Bloom) == "table" then
            local bloom = data.Bloom
            if enabled then
                if not SpreadBackup[bloom] then
                    local backup = {}
                    for k, v in pairs(bloom) do backup[k] = v end
                    SpreadBackup[bloom] = backup
                end
                for _, key in ipairs({"Base","Min","Max","PerShot","Hip","Aim","Move","Air","Jump","Spread","Standing","Crouch"}) do
                    if type(bloom[key]) == "number" then bloom[key] = 0 end
                end
            elseif SpreadBackup[bloom] then
                for k, v in pairs(SpreadBackup[bloom]) do bloom[k] = v end
                SpreadBackup[bloom] = nil
            end
        end
    end
end
local function sendReload()
    local ok = false
    if type(keypress) == "function" and type(keyrelease) == "function" then
        ok = pcall(function() keypress(0x52); task.wait(0.06); keyrelease(0x52) end)
    end
    if not ok then
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.R, false, game)
            task.wait(0.06)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.R, false, game)
        end)
    end
end
local function updateReload()
    if not Settings.AutoReload or os.clock() - LastReload < 1.4 then return end
    local tool = currentTool()
    if not tool or ClientState.Reloading or UIS:GetFocusedTextBox() then return end
    local ammo = tool:GetAttribute("Ammo")
    if type(ammo) == "number" and ammo <= 0 then
        LastReload = os.clock()
        task.spawn(sendReload)
    end
end

local function installShotHook()
    if not NetLag or type(NetLag.Out) ~= "function" or type(hookfunction) ~= "function" then return end
    local original
    local ok = pcall(function()
        original = hookfunction(NetLag.Out, function(fn, remote, ...)
            if Alive and remote == Remotes:FindFirstChild("Fire") and not UIS:GetFocusedTextBox() then
                local args = table.pack(...)
                if typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" then
                    local t = nil
                    if Settings.Silent then
                        t = bestTarget(Settings.AimFOV, Settings.SilentPart, Settings.SilentWall)
                    end
                    if t and args[1] and (t.pos - args[1]).Magnitude > 0.1 then
                        local isRocket = type(args[3]) == "string"
                        if not isRocket then
                            args[2] = (t.pos - args[1]).Unit
                            args[3] = t.char
                            args[4] = t.part.Name
                            args[5] = t.pos
                            args[6] = t.part
                        end
                    end
                    if Settings.NoSpread and type(args[9]) == "number" then
                        args[9] = 0
                    end
                    return original(fn, remote, table.unpack(args, 1, args.n))
                end
            end
            return original(fn, remote, ...)
        end)
    end)
    if not ok then warn("[CAT EMPIRE FPS844] NetLag.Out hook unavailable") end
end
installShotHook()

local function applySkinToTool()
    if not Settings.SkinChanger or not ModCatalog or type(ModCatalog.SkinTool) ~= "function" then return end
    local tool = currentTool()
    if not tool then return end
    if LastSkinTool == tool and LastSkinId == Settings.Skin then return end
    local ok = pcall(ModCatalog.SkinTool, tool, {Skin = Settings.Skin})
    if ok then LastSkinTool, LastSkinId = tool, Settings.Skin end
end
local function restoreSkinTool()
    if LastSkinTool and LastSkinTool.Parent and ModCatalog then
        pcall(ModCatalog.SkinTool, LastSkinTool, {})
    end
    LastSkinTool, LastSkinId = nil, nil
end
local function installSkinHook()
    if not ModCatalog or type(ModCatalog.Apply) ~= "function" or type(hookfunction) ~= "function" then return end
    local old
    pcall(function()
        old = hookfunction(ModCatalog.Apply, function(model, weapon, mods)
            if Alive and Settings.SkinChanger then
                mods = type(mods) == "table" and table.clone(mods) or {}
                mods.Skin = Settings.Skin
            end
            return old(model, weapon, mods)
        end)
    end)
end
installSkinHook()

local function destroyPreview()
    if PreviewGUI then PreviewGUI:Destroy() end
    PreviewGUI, PreviewView, PreviewCamera = nil, nil, nil
end
local function previewSkin()
    destroyPreview()
    local tool = currentTool()
    if not tool or not ModCatalog then return end
    local weapon = tool:GetAttribute("Weapon")
    local store = ReplicatedStorage:FindFirstChild("WeaponVisuals")
    local original = store and store:FindFirstChild(weapon or "")
    if not original then return end
    local ok, model = pcall(function() return original:Clone() end)
    if not ok or not model then return end
    local gui = Instance.new("ScreenGui")
    gui.Name = "CAT_EMPIRE_FPS844_SkinPreview"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(320, 260)
    panel.AnchorPoint = Vector2.new(1, 0.5)
    panel.Position = UDim2.new(1, -22, 0.5, 0)
    panel.BackgroundColor3 = Color3.fromRGB(16, 13, 24)
    panel.BorderSizePixel = 0
    panel.Parent = gui
    Instance.new("UICorner",panel).CornerRadius = UDim.new(0, 12)
    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(28, 28)
    close.Position = UDim2.new(1, -34, 0, 6)
    close.BackgroundTransparency = 1
    close.Text = "X"
    close.TextSize = 18
    close.TextColor3 = Color3.new(1, 1, 1)
    close.Parent = panel
    close.MouseButton1Click:Connect(destroyPreview)
    local view = Instance.new("ViewportFrame")
    view.Size = UDim2.new(1, -12, 1, -45)
    view.Position = UDim2.fromOffset(6, 36)
    view.BackgroundTransparency = 1
    view.Active = true
    view.Ambient = Color3.fromRGB(190, 190, 190)
    view.LightColor = Color3.new(1, 1, 1)
    view.Parent = panel
    local world = Instance.new("WorldModel")
    world.Parent = view
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("Script") or desc:IsA("LocalScript") then desc:Destroy()
        elseif desc:IsA("BasePart") then desc.Anchored = true; desc.CanCollide = false end
    end
    model.Parent = world
    pcall(ModCatalog.SkinTool, model, {Skin = Settings.Skin})
    local cf, size = model:GetBoundingBox()
    local cam = Instance.new("Camera")
    cam.FieldOfView = 36
    local distance = math.max(size.Magnitude * 1.3, 5)
    cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(distance * 0.6, distance * 0.25, distance), cf.Position)
    cam.Parent = view
    view.CurrentCamera = cam
    local yaw = 0
    local dragging, startX = false, 0
    view.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, startX = true, input.Position.X
        end
    end)
    view.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    view.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            yaw = yaw + (input.Position.X - startX) * 0.012
            startX = input.Position.X
            local offset = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(Vector3.new(distance*.6, distance*.25, distance))
            cam.CFrame = CFrame.lookAt(cf.Position + offset, cf.Position)
        end
    end)
    PreviewGUI, PreviewView, PreviewCamera = gui, view, cam
end

local function applyBoost(enable)
    pcall(function()
        if enable then
            BoostBackup.LightingShadows = game:GetService("Lighting").GlobalShadows
            game:GetService("Lighting").GlobalShadows = false
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj:IsA("BasePart") then
                    if not BoostBackup[obj] then BoostBackup[obj] = {material=obj.Material, shadow=obj.CastShadow} end
                    obj.Material = Enum.Material.SmoothPlastic
                    obj.CastShadow = false
                elseif obj:IsA("Decal") or obj:IsA("Texture") then
                    if BoostBackup[obj] == nil then BoostBackup[obj] = obj.Transparency end
                    obj.Transparency = 1
                end
            end
        else
            for obj, original in pairs(BoostBackup) do
                if typeof(obj) == "Instance" and obj.Parent then
                    if type(original) == "table" then
                        obj.Material, obj.CastShadow = original.material, original.shadow
                    elseif type(original) == "number" then obj.Transparency = original end
                end
            end
            local shadows = BoostBackup.LightingShadows
            if shadows ~= nil then game:GetService("Lighting").GlobalShadows = shadows end
        end
    end)
end

local function profileFile(name)
    name = (name or "Default"):gsub("[^%w_%-]", "_")
    if name == "" then name = "Default" end
    return PROFILE_DIR .. "/" .. name .. ".json"
end
local function ensureProfileDir()
    if type(makefolder) == "function" and type(isfolder) == "function" then
        if not isfolder("CAT_EMPIRE") then pcall(makefolder,"CAT_EMPIRE") end
        if not isfolder(PROFILE_DIR) then pcall(makefolder,PROFILE_DIR) end
    end
end
local function loadProfile(name)
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return end
    local path = profileFile(name)
    if not isfile(path) then return end
    local ok, obj = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if ok and type(obj) == "table" then
        for k, v in pairs(obj) do
            if Settings[k] ~= nil and typeof(v) == typeof(Settings[k]) then Settings[k] = v end
        end
    end
end
local function saveProfile(name)
    if type(writefile) ~= "function" then return end
    ensureProfileDir()
    pcall(writefile, profileFile(name), HttpService:JSONEncode(Settings))
end
if type(isfile) == "function" and type(readfile) == "function" then
    local path = PROFILE_DIR .. "/autoload.json"
    if isfile(path) then
        local ok, metadata = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
        if ok and type(metadata) == "table" and metadata.enabled then
            Settings.AutoLoadProfile = true
            Settings.ProfileName = metadata.profile or "Default"
            loadProfile(Settings.ProfileName)
        end
    end
end
local function queueAfterRejoin()
    if not Settings.AutoLoadAfterRejoin then return end
    local queue = queue_on_teleport or (syn and syn.queue_on_teleport)
    if type(queue) == "function" then
        pcall(queue, [[loadstring(game:HttpGet("https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Loader/Loader.lua"))()]])
    end
end
local function saveAutoload()
    if type(writefile) ~= "function" then return end
    ensureProfileDir()
    pcall(writefile, PROFILE_DIR .. "/autoload.json", HttpService:JSONEncode({enabled=Settings.AutoLoadProfile,profile=Settings.ProfileName}))
end

-- Biblioteca exclusiva da interface CAT EMPIRE, preparada pelo Loader principal.
local FluentSource = Env.__CE_F_91A7
assert(type(FluentSource) == "string" and #FluentSource > 0,
    "[CAT EMPIRE] Execute pelo Loader/Loader.lua principal")
local okUI, Fluent = pcall(function()
    local factory = assert(loadstring(FluentSource))
    return factory()
end)
assert(okUI and Fluent, "[CAT EMPIRE] Falha ao carregar a interface CAT EMPIRE")

local Window = Fluent:CreateWindow({
    Title = "CAT EMPIRE", SubTitle = "FPS | 84448037861644",
    TabWidth = 155, Size = UDim2.fromOffset(590, 505),
    Acrylic = false, Theme = Settings.Theme,
    MinimizeKey = Enum.KeyCode.RightControl,
})
local Tabs = {
    Combat = Window:AddTab({Title = "COMBAT", Icon = "crosshair"}),
    Visuals = Window:AddTab({Title = "VISUALS", Icon = "eye"}),
    Skins = Window:AddTab({Title = "SKINS", Icon = "palette"}),
    Settings = Window:AddTab({Title = "SETTINGS", Icon = "settings"}),
    Misc = Window:AddTab({Title = "MISC", Icon = "user"}),
}
local function toggle(tab, key, title)
    return tab:AddToggle(key, {Title=title, Default=Settings[key], Callback=function(value)
        Settings[key] = value
        if key == "NoSpread" then setNoSpread(value)
        elseif key == "Chams" and not value then updateChams()
        elseif key == "SkinChanger" and not value then restoreSkinTool()
        elseif key == "BoostFPS" then applyBoost(value)
        elseif key == "AutoLoadProfile" then saveAutoload()
        elseif key == "AutoLoadAfterRejoin" and value then queueAfterRejoin()
        elseif key == "AutoCloseUI" and value then
            task.delay(0.6, function() pcall(function() Window:Minimize() end) end)
        end
    end})
end
local function slider(tab, key, title, min, max, decimals)
    return tab:AddSlider(key, {Title=title, Default=Settings[key], Min=min, Max=max,
        Rounding=decimals or 0, Callback=function(value) Settings[key]=value end})
end
local function dropdown(tab, key, title, values)
    return tab:AddDropdown(key, {Title=title, Values=values, Default=Settings[key], Multi=false,
        Callback=function(value)
            Settings[key]=value
            if key=="Skin" then LastSkinTool=nil
            elseif key=="Theme" then pcall(function() Fluent:SetTheme(value) end) end
        end})
end
local function colorPicker(tab, key, title)
    local ok, instance = pcall(function()
        return tab:AddColorpicker(key, {Title=title, Default=rgb(Settings[key]), Callback=function(value)
            Settings[key]=hex(value)
        end})
    end)
    return ok and instance or nil
end
local function bind(tab, label, key, heldKey)
    local ok = pcall(function()
        tab:AddKeybind(label, {Title="Keybind", Mode="Hold", Default=Settings[key],
            Callback=function(isDown) Settings[heldKey]=isDown == true end,
            ChangedCallback=function(value)
                local raw = tostring(value)
                Settings[key] = raw:match("([^%.]+)$") or raw
            end})
    end)
    if not ok then warn("[CAT EMPIRE FPS844] keybind widget unavailable") end
end

toggle(Tabs.Combat,"Aim","Aimbot")
bind(Tabs.Combat,"AimKeybind","AimKey","AimHeld")
slider(Tabs.Combat,"AimSmooth","Smooth",0.03,1,2)
dropdown(Tabs.Combat,"AimPart","Target",{"Head","Torso"})
toggle(Tabs.Combat,"AimWall","Wall Check")
toggle(Tabs.Combat,"Silent","Silent Aim")
dropdown(Tabs.Combat,"SilentPart","Silent Target",{"Head","Torso"})
toggle(Tabs.Combat,"SilentWall","Silent Wall Check")
toggle(Tabs.Combat,"Trigger","Triggerbot")
bind(Tabs.Combat,"TriggerKeybind","TriggerKey","TriggerHeld")
dropdown(Tabs.Combat,"TriggerTarget","Trigger Target",{"Any","Head","Torso"})
slider(Tabs.Combat,"TriggerDelay","Trigger Delay",0,0.8,2)
slider(Tabs.Combat,"TriggerCooldown","Trigger Cooldown",0.06,0.8,2)
toggle(Tabs.Combat,"TriggerWall","Trigger Wall Check")
toggle(Tabs.Combat,"TriggerOnlyADS","Trigger ADS")
toggle(Tabs.Combat,"NoSpread","No Spread")
toggle(Tabs.Combat,"AutoReload","Auto Reload")

toggle(Tabs.Visuals,"ESP","ESP")
toggle(Tabs.Visuals,"ESPBox","Boxes")
toggle(Tabs.Visuals,"ESPName","Names")
toggle(Tabs.Visuals,"ESPDistance","Distance")
toggle(Tabs.Visuals,"ESPLine","Lines")
slider(Tabs.Visuals,"ESPRange","ESP Range",100,3000)
colorPicker(Tabs.Visuals,"ESPColor","ESP Color")
toggle(Tabs.Visuals,"Chams","Chams")
slider(Tabs.Visuals,"ChamsTransparency","Chams Transparency",0,1,2)
colorPicker(Tabs.Visuals,"ChamsColor","Chams Color")
toggle(Tabs.Visuals,"FOVCircle","FOV Circle")
slider(Tabs.Visuals,"AimFOV","FOV",30,600)
slider(Tabs.Visuals,"FOVThickness","FOV Thickness",1,4,1)
colorPicker(Tabs.Visuals,"FOVColor","FOV Color")

toggle(Tabs.Skins,"SkinChanger","SkinChanger")
local skins = {}
if ModCatalog and type(ModCatalog.Skins) == "table" then
    for name in pairs(ModCatalog.Skins) do table.insert(skins,name) end
    table.sort(skins)
end
if #skins == 0 then skins={"DarkMatter"} end
dropdown(Tabs.Skins,"Skin","Skin",skins)
Tabs.Skins:AddButton({Title="Preview 3D", Callback=previewSkin})

local function refreshProfileName(value)
    Settings.ProfileName = value or "Default"
end
Tabs.Settings:AddInput("Profile", {Title="Profile",Default=Settings.ProfileName,Numeric=false,
    Finished=false,Callback=refreshProfileName})
Tabs.Settings:AddButton({Title="Create Profile",Callback=function() saveProfile(Settings.ProfileName) end})
Tabs.Settings:AddButton({Title="Save Profile",Callback=function() saveProfile(Settings.ProfileName) end})
Tabs.Settings:AddButton({Title="Load Profile",Callback=function()
    loadProfile(Settings.ProfileName)
    if Fluent.Options then
        for key, value in pairs(Settings) do
            local option = Fluent.Options[key]
            if option and type(option.SetValue) == "function" then
                pcall(function()
                    if key:find("Color") and type(value) == "string" then
                        option:SetValue(rgb(value))
                    else
                        option:SetValue(value)
                    end
                end)
            end
        end
    end
    setNoSpread(Settings.NoSpread)
    if not Settings.SkinChanger then restoreSkinTool() end
    saveAutoload()
end})
toggle(Tabs.Settings,"AutoLoadProfile","Auto Load Profiles")
toggle(Tabs.Settings,"AutoRejoin","Auto Rejoin")
toggle(Tabs.Settings,"AntiAFK","Anti AFK")
toggle(Tabs.Settings,"AutoCloseUI","Auto Close UI")
toggle(Tabs.Settings,"AutoLoadAfterRejoin","Auto Load After Rejoin")
toggle(Tabs.Settings,"BoostFPS","Boost FPS")
dropdown(Tabs.Settings,"Theme","Themes",{"Dark","Darker","Light","Rose","Aqua","Amethyst"})

local display = LocalPlayer.DisplayName .. " (@" .. LocalPlayer.Name .. ")"
local avatar = ""
pcall(function()
    avatar = Players:GetUserThumbnailAsync(LocalPlayer.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size420x420)
end)
local gamename = "84448037861644"
local gameIcon = ""
pcall(function()
    local info = MarketplaceService:GetProductInfo(game.PlaceId)
    gamename = info and info.Name or gamename
    gameIcon = "rbxassetid://" .. tostring(info.IconImageAssetId or "")
end)
Tabs.Misc:AddParagraph({Title=display,Content="ID: " .. tostring(LocalPlayer.UserId)})
Tabs.Misc:AddParagraph({Title=gamename,Content="Place ID: " .. tostring(game.PlaceId)})
local miscPanel
local function showMiscPanel()
    if miscPanel then miscPanel:Destroy(); miscPanel=nil; return end
    local gui = Instance.new("ScreenGui")
    gui.Name = "CAT_EMPIRE_FPS844_Misc"
    gui.ResetOnSpawn = false
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(385,245)
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.BackgroundColor3 = Color3.fromRGB(16,13,24)
    panel.BorderSizePixel = 0
    panel.Parent = gui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0,12)
    local function card(x, src, main, sub)
        local image = Instance.new("ImageLabel")
        image.Size = UDim2.fromOffset(142,142)
        image.Position = UDim2.fromOffset(x, 14)
        image.BackgroundTransparency = 1
        image.Image = src
        image.Parent = panel
        local caption = Instance.new("TextLabel")
        caption.Size = UDim2.fromOffset(170,40)
        caption.Position = UDim2.fromOffset(x-14,166)
        caption.BackgroundTransparency = 1
        caption.Text = main .. "\n" .. sub
        caption.TextColor3 = Color3.fromRGB(247,241,255)
        caption.TextScaled = true
        caption.Font = Enum.Font.Gotham
        caption.Parent = panel
    end
    card(29,avatar,LocalPlayer.DisplayName,LocalPlayer.Name)
    card(216,gameIcon,gamename,tostring(game.PlaceId))
    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(26,26)
    close.Position = UDim2.new(1,-32,0,4)
    close.BackgroundTransparency = 1
    close.Text = "X"
    close.TextColor3 = Color3.new(1,1,1)
    close.TextSize = 18
    close.Parent = panel
    close.MouseButton1Click:Connect(function() gui:Destroy(); miscPanel=nil end)
    miscPanel=gui
end
Tabs.Misc:AddButton({Title="Profile", Callback=showMiscPanel})

local function cleanup()
    if not Alive then return end
    Alive = false
    releaseTrigger()
    restoreSkinTool()
    setNoSpread(false)
    applyBoost(false)
    Settings.Chams = false
    updateChams()
    Settings.ESP = false
    updateESP()
    if FOVDrawing then pcall(function() FOVDrawing:Remove() end) end
    destroyPreview()
    if miscPanel then miscPanel:Destroy(); miscPanel = nil end
    for _, connection in ipairs(Connections) do pcall(function() connection:Disconnect() end) end
    pcall(function() RunService:UnbindFromRenderStep("CAT_EMPIRE_FPS844_Aim") end)
    pcall(function()
        if Window and type(Window.Destroy) == "function" then Window:Destroy() end
    end)
    if Env.__CE_FPS844_CLEANUP == cleanup then Env.__CE_FPS844_CLEANUP = nil end
end
Env.__CE_FPS844_CLEANUP = cleanup

connect(LocalPlayer.Idled,function()
    if Settings.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0,0))
    end
end)
connect(game:GetService("GuiService").ErrorMessageChanged,function(message)
    if Settings.AutoRejoin and message and message ~= "" then
        task.delay(3,function()
            if Alive and Settings.AutoRejoin then pcall(TeleportService.Teleport,TeleportService,game.PlaceId,LocalPlayer) end
        end)
    end
end)
connect(LocalPlayer.CharacterAdded,function()
    LastSkinTool,LastSkinId = nil,nil
    TriggerStart,TriggerTarget = nil,nil
end)
connect(RunService.Heartbeat,function()
    if not Alive then return end
    updateTrigger()
    updateReload()
    applySkinToTool()
end)
local lastChams = 0
RunService:BindToRenderStep("CAT_EMPIRE_FPS844_Aim",Enum.RenderPriority.Camera.Value+3,function(dt)
    if not Alive then return end
    Camera = workspace.CurrentCamera or Camera
    updateAim(dt)
    updateCircle()
    updateESP()
    if os.clock()-lastChams>0.18 then
        lastChams=os.clock()
        updateChams()
    end
end)

connect(UIS.InputBegan,function(input,processed)
    if processed or UIS:GetFocusedTextBox() then return end
    if input.KeyCode.Name == Settings.AimKey then Settings.AimHeld = true end
    if input.KeyCode.Name == Settings.TriggerKey then Settings.TriggerHeld = true end
end)
connect(UIS.InputEnded,function(input)
    if input.KeyCode.Name == Settings.AimKey then Settings.AimHeld = false end
    if input.KeyCode.Name == Settings.TriggerKey then Settings.TriggerHeld = false end
end)
if Settings.NoSpread then setNoSpread(true) end
if Settings.BoostFPS then applyBoost(true) end
queueAfterRejoin()
if Settings.AutoCloseUI then pcall(function() Window:Minimize() end) end
pcall(function() Window:SelectTab(1) end)