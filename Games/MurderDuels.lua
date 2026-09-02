local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

local ESP_Objects = {}
local aimbotEnabled = false
local aimbotTarget = nil
local fovCircle = nil
local fovRadius = 200
local TeamCheckEnabled = true
local ESPLines = {}
local WindowRef = nil
local UIClosed = false
local CloseButton = nil

local function CloseUI()
    UIClosed = true
    if WindowRef then
        pcall(function()
            WindowRef:Destroy()
        end)
        WindowRef = nil
    end
    for char, esp in pairs(ESP_Objects) do
        pcall(function()
            esp.highlight:Destroy()
            esp.billboard:Destroy()
        end)
    end
    ESP_Objects = {}
    for char, line in pairs(ESPLines) do
        pcall(function() line:Destroy() end)
    end
    ESPLines = {}
    if fovCircle then
        pcall(function() fovCircle:Destroy() end)
        fovCircle = nil
    end
    pcall(function()
        local screenGui = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("ESP_Lines")
        if screenGui then screenGui:Destroy() end
        local fovGui = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("FOVCircle")
        if fovGui then fovGui:Destroy() end
    end)
end

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

WindowRef = Fluent:CreateWindow({
    Title = "MurderDuels",
    SubTitle = "FPS Exploit",
    TabWidth = 160,
    Size = UDim2.fromOffset(620, 480),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

local function ToggleUI()
    if WindowRef and WindowRef.Visible then
        CloseUI()
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        ToggleUI()
    end
end)

local Tabs = {
    ESP = WindowRef:AddTab({ Title = "ESP", Icon = "eye" }),
    Aimbot = WindowRef:AddTab({ Title = "Aimbot", Icon = "crosshair" }),
    FOV = WindowRef:AddTab({ Title = "FOV", Icon = "circle" }),
    Combat = WindowRef:AddTab({ Title = "Combat", Icon = "swords" }),
}
local Options = Fluent.Options

local function getCharacters()
    local chars = {}
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            table.insert(chars, player.Character)
        end
    end
    return chars
end

local function isEnemy(char)
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    if humanoid.Health <= 0 then return false end
    if TeamCheckEnabled then
        local myChar = LocalPlayer.Character
        if myChar then
            local myTeam = myChar:GetAttribute("MatchSide") or myChar:GetAttribute("Team") or myChar:GetAttribute("Side")
            local theirTeam = char:GetAttribute("MatchSide") or char:GetAttribute("Team") or char:GetAttribute("Side")
            if myTeam and theirTeam and myTeam == theirTeam then
                return false
            end
        end
    end
    return true
end

local function getHeadPosition(char)
    local head = char:FindFirstChild("Head")
    if head then return head.Position end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then return humanoid.TargetPoint end
    return char:GetPivot().Position
end

local function getDistance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

local function getClosestEnemyToCrosshair(maxDistance)
    local closest = nil
    local closestDist = maxDistance or 300
    for _, char in pairs(getCharacters()) do
        if isEnemy(char) then
            local head = char:FindFirstChild("Head")
            if head then
                local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
                if onScreen then
                    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closest = char
                    end
                end
            end
        end
    end
    return closest
end

local function aimAtPosition(position)
    local cameraPos = Camera.CFrame.Position
    local lookDir = (position - cameraPos).Unit
    Camera.CFrame = CFrame.new(cameraPos, cameraPos + lookDir)
end

local function smoothAim(position, strength)
    strength = strength or 0.5
    local cameraPos = Camera.CFrame.Position
    local targetDir = (position - cameraPos).Unit
    local currentDir = Camera.CFrame.LookVector
    local newDir = currentDir:Lerp(targetDir, strength)
    Camera.CFrame = CFrame.new(cameraPos, cameraPos + newDir)
end

local function createESP(char)
    if UIClosed then return end
    local esp = {}
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESP_Highlight"
    highlight.FillColor = Color3.fromRGB(255, 0, 0)
    highlight.FillTransparency = 0.5
    highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
    highlight.OutlineTransparency = 0
    highlight.Parent = char
    esp.highlight = highlight
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
    esp.label = label
    esp.billboard = billboard
    ESP_Objects[char] = esp
end

local function updateESP()
    if UIClosed then return end
    for char, esp in pairs(ESP_Objects) do
        if not char.Parent or not char:FindFirstChildOfClass("Humanoid") then
            pcall(function()
                esp.highlight:Destroy()
                esp.billboard:Destroy()
            end)
            ESP_Objects[char] = nil
            continue
        end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid.Health <= 0 then
            pcall(function()
                esp.highlight:Destroy()
                esp.billboard:Destroy()
            end)
            ESP_Objects[char] = nil
            continue
        end
        local myChar = LocalPlayer.Character
        if myChar then
            local myTeam = myChar:GetAttribute("MatchSide")
            local theirTeam = char:GetAttribute("MatchSide")
            if myTeam and theirTeam and myTeam ~= theirTeam then
                esp.highlight.FillColor = Color3.fromRGB(255, 0, 0)
                esp.highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
                esp.label.TextColor3 = Color3.fromRGB(255, 0, 0)
            else
                esp.highlight.FillColor = Color3.fromRGB(255, 200, 0)
                esp.highlight.OutlineColor = Color3.fromRGB(255, 200, 0)
                esp.label.TextColor3 = Color3.fromRGB(255, 200, 0)
            end
        end
        local dist = getDistance(char:GetPivot().Position, LocalPlayer.Character:GetPivot().Position)
        esp.label.Text = string.format("%.0f studs", dist)
    end
end

local function ESPLoop()
    while Options.ESPEnabled and Options.ESPEnabled.Value and not UIClosed do
        task.wait(0.1)
        updateESP()
    end
end

local function createESPLine(char)
    if UIClosed then return end
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
    ESPLines[char] = line
end

local function updateESPLines()
    if UIClosed then return end
    for char, line in pairs(ESPLines) do
        if not char.Parent or not char:FindFirstChildOfClass("Humanoid") then
            pcall(function() line:Destroy() end)
            ESPLines[char] = nil
            continue
        end
        local headPos = getHeadPosition(char)
        local screenPos, onScreen = Camera:WorldToViewportPoint(headPos)
        if onScreen then
            local centerX = Camera.ViewportSize.X / 2
            local centerY = Camera.ViewportSize.Y / 2
            local x1 = centerX
            local y1 = centerY
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
            line.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        else
            line.Visible = false
        end
    end
end

local function ESPLinesLoop()
    while Options.ESPLines and Options.ESPLines.Value and not UIClosed do
        task.wait()
        updateESPLines()
    end
end

local function createFOVCircle(radius)
    if fovCircle then 
        pcall(function() fovCircle:Destroy() end)
        fovCircle = nil
    end
    if UIClosed then return end
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
    local circle = Instance.new("ImageLabel")
    circle.Size = UDim2.new(1, 0, 1, 0)
    circle.Position = UDim2.new(0, 0, 0, 0)
    circle.BackgroundTransparency = 1
    circle.Image = "rbxassetid://3570695787"
    circle.ImageColor3 = Color3.fromRGB(0, 255, 255)
    circle.ImageTransparency = 0.3
    circle.Parent = frame
    fovCircle = gui
end

local function aimbotLoop()
    while not UIClosed do
        task.wait()
        if aimbotEnabled and LocalPlayer.Character then
            local target = getClosestEnemyToCrosshair(fovRadius)
            if target then
                aimbotTarget = target
                local headPos = getHeadPosition(target)
                if Options.SilentAim and Options.SilentAim.Value then
                    pcall(function() aimAtPosition(headPos) end)
                elseif Options.AimAssist and Options.AimAssist.Value then
                    local strength = Options.AimStrength and Options.AimStrength.Value or 0.5
                    pcall(function() smoothAim(headPos, strength) end)
                else
                    pcall(function() aimAtPosition(headPos) end)
                end
            end
        end
    end
end

local function autoShootLoop()
    while not UIClosed do
        task.wait(0.1)
        if Options.AutoShoot and Options.AutoShoot.Value then
            local target = aimbotTarget
            if target then
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
end

Tabs.ESP:AddSection("ESP Geral")

Tabs.ESP:AddToggle("ESPEnabled", {
    Title = "ESP Ativado",
    Default = false,
})

Options.ESPEnabled:OnChanged(function(v)
    if v and not UIClosed then
        for _, char in pairs(getCharacters()) do
            if isEnemy(char) then
                createESP(char)
            end
        end
        task.spawn(ESPLoop)
    else
        for char, esp in pairs(ESP_Objects) do
            pcall(function()
                esp.highlight:Destroy()
                esp.billboard:Destroy()
            end)
        end
        ESP_Objects = {}
    end
end)

Tabs.ESP:AddToggle("ESPBox", {
    Title = "ESP Highlight",
    Default = true,
})

Tabs.ESP:AddToggle("ESPDistance", {
    Title = "ESP Distância",
    Default = true,
})

Tabs.ESP:AddSection("ESP Lines")

Tabs.ESP:AddToggle("ESPLines", {
    Title = "Linhas (Tracers)",
    Default = false,
})

Options.ESPLines:OnChanged(function(v)
    if v and not UIClosed then
        for _, char in pairs(getCharacters()) do
            if isEnemy(char) then
                createESPLine(char)
            end
        end
        task.spawn(ESPLinesLoop)
    else
        for char, line in pairs(ESPLines) do
            pcall(function() line:Destroy() end)
        end
        ESPLines = {}
        local screenGui = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("ESP_Lines")
        if screenGui then screenGui:Destroy() end
    end
end)

Tabs.ESP:AddSection("Time / Equipe")

Tabs.ESP:AddToggle("TeamCheck", {
    Title = "Team Check",
    Default = true,
})

Options.TeamCheck:OnChanged(function(v)
    TeamCheckEnabled = v
end)

Tabs.Aimbot:AddSection("Configurações do Aimbot")

Tabs.Aimbot:AddToggle("AimbotEnabled", {
    Title = "Aimbot Ativado",
    Default = false,
})

Options.AimbotEnabled:OnChanged(function(v)
    aimbotEnabled = v
end)

Tabs.Aimbot:AddToggle("SilentAim", {
    Title = "Silent Aim",
    Default = false,
})

Tabs.Aimbot:AddToggle("AimAssist", {
    Title = "Aim Assist",
    Default = true,
})

Tabs.Aimbot:AddSlider("AimStrength", {
    Title = "Força da Mira",
    Min = 0.1,
    Max = 1,
    Default = 0.5,
    Rounding = 2,
})

Tabs.Aimbot:AddSlider("AimFOV", {
    Title = "FOV do Aimbot",
    Min = 50,
    Max = 500,
    Default = 200,
    Rounding = 0,
})

Options.AimFOV:OnChanged(function(v)
    fovRadius = v
end)

Tabs.FOV:AddSection("Círculo de FOV")

Tabs.FOV:AddToggle("FOVCircleEnabled", {
    Title = "Círculo de FOV",
    Default = false,
})

Options.FOVCircleEnabled:OnChanged(function(v)
    if v and not UIClosed then
        createFOVCircle(fovRadius)
    else
        if fovCircle then
            pcall(function() fovCircle:Destroy() end)
            fovCircle = nil
        end
    end
end)

Tabs.FOV:AddSlider("FOVRadius", {
    Title = "Raio do FOV",
    Min = 30,
    Max = 500,
    Default = 200,
    Rounding = 0,
})

Options.FOVRadius:OnChanged(function(v)
    fovRadius = v
    if Options.FOVCircleEnabled and Options.FOVCircleEnabled.Value and not UIClosed then
        createFOVCircle(fovRadius)
    end
end)

Tabs.FOV:AddSection("FOV da Câmera")

Tabs.FOV:AddSlider("GameFOV", {
    Title = "FOV da Câmera",
    Min = 40,
    Max = 120,
    Default = 70,
    Rounding = 0,
})

Options.GameFOV:OnChanged(function(v)
    Camera.FieldOfView = v
end)

Tabs.Combat:AddSection("Combate Automático")

Tabs.Combat:AddToggle("AutoShoot", {
    Title = "Auto Shoot",
    Default = false,
})

local function addCloseButton()
    if not WindowRef then return end
    local success, gui = pcall(function()
        return WindowRef.Gui
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
            CloseUI()
        end)
        closeBtn.MouseEnter:Connect(function()
            closeBtn.BackgroundTransparency = 0
        end)
        closeBtn.MouseLeave:Connect(function()
            closeBtn.BackgroundTransparency = 0.3
        end)
    end
end

task.spawn(function()
    task.wait(0.5)
    addCloseButton()
end)

task.spawn(aimbotLoop)
task.spawn(autoShootLoop)

Fluent:Notify({
    Title = "MurderDuels",
    Content = "FPS Exploit carregado!",
    Duration = 4,
})
