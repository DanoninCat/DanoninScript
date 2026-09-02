-- ============================================================
-- CAT EMPIRE | FPS EXPLOIT HUB v2.0
-- ============================================================
-- GitHub: @DanoninCat
-- Jogo: Cat Empire (ID: 120851538706364)
-- ============================================================

-- ============================================================
-- [SERVIÇOS]
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

-- ============================================================
-- [VARIÁVEIS GLOBAIS]
-- ============================================================
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

-- ============================================================
-- [UI - FLUENT]
-- ============================================================
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local Window = Fluent:CreateWindow({
    Title = "Cat Empire",
    SubTitle = "FPS Exploit v2.0",
    TabWidth = 160,
    Size = UDim2.fromOffset(620, 480),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

-- ============================================================
-- [TABS]
-- ============================================================
local Tabs = {
    ESP = Window:AddTab({ Title = "ESP", Icon = "eye" }),
    Aimbot = Window:AddTab({ Title = "Aimbot", Icon = "crosshair" }),
    FOV = Window:AddTab({ Title = "FOV", Icon = "circle" }),
    Combat = Window:AddTab({ Title = "Combat", Icon = "swords" }),
}
local Options = Fluent.Options

-- ============================================================
-- [FUNÇÕES DE UTILIDADE]
-- ============================================================

-- Obtém todos os personagens dos jogadores
local function getCharacters()
    local chars = {}
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            table.insert(chars, player.Character)
        end
    end
    return chars
end

-- Verifica se o personagem é inimigo (Team Check)
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

-- Obtém a posição da cabeça do personagem
local function getHeadPosition(char)
    local head = char:FindFirstChild("Head")
    if head then return head.Position end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then return humanoid.TargetPoint end
    return char:GetPivot().Position
end

-- Obtém a posição do torso do personagem
local function getTorsoPosition(char)
    local torso = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    if torso then return torso.Position end
    return char:GetPivot().Position
end

-- Distância entre dois pontos
local function getDistance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

-- ============================================================
-- [FUNÇÕES DE AIMBOT]
-- ============================================================

-- Obtém o inimigo mais próximo da mira
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

-- Mira diretamente para uma posição
local function aimAtPosition(position)
    local cameraPos = Camera.CFrame.Position
    local lookDir = (position - cameraPos).Unit
    Camera.CFrame = CFrame.new(cameraPos, cameraPos + lookDir)
end

-- Mira suavemente para uma posição
local function smoothAim(position, strength)
    strength = strength or 0.5
    local cameraPos = Camera.CFrame.Position
    local targetDir = (position - cameraPos).Unit
    local currentDir = Camera.CFrame.LookVector
    local newDir = currentDir:Lerp(targetDir, strength)
    Camera.CFrame = CFrame.new(cameraPos, cameraPos + newDir)
end

-- ============================================================
-- [ESP - HIGHLIGHT + DISTÂNCIA]
-- ============================================================

-- Cria ESP para um personagem
local function createESP(char)
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

-- Atualiza ESP de todos os personagens
local function updateESP()
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
        
        -- Cor do ESP baseada no time
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

-- Loop do ESP
local function ESPLoop()
    while Options.ESPEnabled and Options.ESPEnabled.Value do
        task.wait(0.1)
        updateESP()
    end
end

-- ============================================================
-- [ESP - TRACERS / LINES]
-- ============================================================

-- Cria uma linha de ESP
local function createESPLine(char)
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

-- Atualiza as linhas de ESP
local function updateESPLines()
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

-- Loop das linhas
local function ESPLinesLoop()
    while Options.ESPLines and Options.ESPLines.Value do
        task.wait()
        updateESPLines()
    end
end

-- ============================================================
-- [FOV CIRCLE]
-- ============================================================

-- Cria o círculo de FOV
local function createFOVCircle(radius)
    if fovCircle then fovCircle:Destroy() end
    
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
    outline.ImageTransparency = 0.5
    outline.Parent = frame
    
    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 4, 0, 4)
    dot.Position = UDim2.new(0.5, -2, 0.5, -2)
    dot.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    dot.BorderSizePixel = 0
    dot.Parent = frame
    
    fovCircle = gui
end

-- ============================================================
-- [AIMBOT LOOP PRINCIPAL]
-- ============================================================

local function aimbotLoop()
    while true do
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

-- ============================================================
-- [AUTO SHOOT]
-- ============================================================

local function autoShootLoop()
    while true do
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

-- ============================================================
-- [UI: ESP TAB]
-- ============================================================

Tabs.ESP:AddSection("ESP Geral")

Tabs.ESP:AddToggle("ESPEnabled", {
    Title = "ESP Ativado",
    Default = false,
})

Options.ESPEnabled:OnChanged(function(v)
    if v then
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
    if v then
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
    Title = "Team Check (Verificar Times)",
    Default = true,
})

Options.TeamCheck:OnChanged(function(v)
    TeamCheckEnabled = v
end)

-- ============================================================
-- [UI: AIMBOT TAB]
-- ============================================================

Tabs.Aimbot:AddSection("Configurações do Aimbot")

Tabs.Aimbot:AddToggle("AimbotEnabled", {
    Title = "Aimbot Ativado",
    Default = false,
})

Options.AimbotEnabled:OnChanged(function(v)
    aimbotEnabled = v
end)

Tabs.Aimbot:AddToggle("SilentAim", {
    Title = "Silent Aim (Mira Invisível)",
    Default = false,
})

Tabs.Aimbot:AddToggle("AimAssist", {
    Title = "Aim Assist (Mira Suave)",
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

-- ============================================================
-- [UI: FOV TAB]
-- ============================================================

Tabs.FOV:AddSection("Círculo de FOV")

Tabs.FOV:AddToggle("FOVCircleEnabled", {
    Title = "Círculo de FOV",
    Default = false,
})

Options.FOVCircleEnabled:OnChanged(function(v)
    if v then
        createFOVCircle(fovRadius)
    else
        if fovCircle then
            fovCircle:Destroy()
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
    if Options.FOVCircleEnabled and Options.FOVCircleEnabled.Value then
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

-- ============================================================
-- [UI: COMBAT TAB]
-- ============================================================

Tabs.Combat:AddSection("Combate Automático")

Tabs.Combat:AddToggle("AutoShoot", {
    Title = "Auto Shoot (Atirar Automático)",
    Default = false,
})

-- ============================================================
-- [INICIAR LOOPS]
-- ============================================================

task.spawn(aimbotLoop)
task.spawn(autoShootLoop)

-- ============================================================
-- [NOTIFICAÇÃO DE CARREGAMENTO]
-- ============================================================

Fluent:Notify({
    Title = "Cat Empire",
    Content = "FPS Exploit v2.0 carregado!",
    Duration = 4,
})

print("============================================================")
print("CAT EMPIRE | FPS EXPLOIT HUB v2.0")
print("GitHub: @DanoninCat")
print("============================================================")
print("[✓] ESP com Highlight + Distância")
print("[✓] ESP Lines (Tracers)")
print("[✓] Team Check")
print("[✓] Aimbot + Silent Aim + Aim Assist")
print("[✓] FOV Circle")
print("[✓] Auto Shoot")
print("============================================================")
