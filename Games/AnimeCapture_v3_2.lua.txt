-- ============================================================
--  DANONIN HUB | Anime Capture v3.2
--  UI: Estilo Mai Hub | Fluent custom (Darker + BG image)
--  Tabs: Main | Hatch | GameModes | Misc | Settings | Info
-- ============================================================

if _G.DanoninAnimeCapture then
    pcall(function() _G.DanoninAnimeCapture:Destroy() end)
end

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local UIS     = game:GetService("UserInputService")
local PPS     = game:GetService("ProximityPromptService")
local player  = Players.LocalPlayer

-- ============================================================
-- COMPAT SHIM — alguns executores não implementam task.* completo
-- Erro visto: "attempt to call a nil value" em task.wait
-- Preenche as funções faltantes com os globais equivalentes
-- ============================================================
if not task then task = {} end
task.wait   = task.wait   or wait
task.spawn  = task.spawn  or spawn
task.delay  = task.delay  or delay
task.defer  = task.defer  or spawn
task.cancel = task.cancel or function(thread)
    pcall(function() if coroutine.status(thread) ~= "dead" then coroutine.close(thread) end end)
end

local waited = 0
repeat
    task.wait(0.1)
    waited += 0.1
until player:FindFirstChild("PlayerGui") or waited > 10
local pg = player.PlayerGui or player:WaitForChild("PlayerGui", 5)

-- ============================================================
-- CONFIG (mesma estrutura do ConfigFluent.lua)
-- ============================================================
local Config = {
    Background              = "https://media.discordapp.net/attachments/1400396358976016438/1449007745259802677/da8050322d4e962ffa68dab9b0bfce50.png",
    Theme                   = "Darker",
    Title                   = "Danonin Hub",
    SubTitle                = "Anime Capture v3.2",
    Author                  = "Danonin",
    SetBackgroundImageTransparency = 0.7,
    Icon                    = "rbxassetid://116236573892978",
    Discord                 = "discord.gg/qDeZ9sEdGY",
}

-- ============================================================
-- FLUENT (versão custom com temas extras: Darker, AMOLED, etc.)
-- Tenta GitHub do usuário primeiro, depois fallback padrão
-- ============================================================
local Fluent, SaveManager, InterfaceManager

local function tryLoad(url)
    local ok, res = pcall(function()
        return loadstring(game:HttpGet(url, true))()
    end)
    return ok and res or nil
end

-- URL do Fluent customizado (sobe Fluent_lua.txt no GitHub como Fluent.lua)
Fluent = tryLoad("https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Libs/Fluent.lua")
     or tryLoad("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua")
     or tryLoad("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/dist/main.lua")

if not Fluent then warn("[AC] Fluent nao carregou") return end

SaveManager = tryLoad("https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Libs/SaveManager.lua")
          or tryLoad("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua")
if not SaveManager then warn("[AC] SaveManager nao carregou") return end

InterfaceManager = tryLoad("https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Libs/InterfaceManager.lua")
               or tryLoad("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua")
if not InterfaceManager then warn("[AC] InterfaceManager nao carregou") return end

-- ============================================================
-- REMOTES
-- ============================================================
local RF = RS:WaitForChild("RemotesFolder", 10)
if not RF then warn("[AC] RemotesFolder nao encontrado!") return end

local function fire(name, ...)
    local r = RF:FindFirstChild(name)
    if not r then warn("[AC] Remote: "..name.." nao encontrado") return end
    local args = {...}
    pcall(function() r:FireServer(table.unpack(args)) end)
end

-- ============================================================
-- SAFETY
-- ============================================================
local Safety = { _t = {}, _a = {} }

function Safety:Kill(key)
    self._a[key] = false
    if self._t[key] then
        pcall(function() task.cancel(self._t[key]) end)
        self._t[key] = nil
    end
end

function Safety:KillAll()
    for k in pairs(self._t) do self:Kill(k) end
end

function Safety:Loop(key, interval, fn)
    self:Kill(key)
    self._a[key] = true
    self._t[key] = task.spawn(function()
        while self._a[key] do
            task.wait(interval)
            if self._a[key] then
                local ok, err = pcall(fn)
                if not ok then warn("[AC:"..key.."] "..tostring(err)) end
            end
        end
        self._t[key] = nil
    end)
end

function Safety:Toggle(key, enabled, interval, fn)
    if enabled then self:Loop(key, interval, fn) else self:Kill(key) end
end

-- ============================================================
-- FLUENT WINDOW — estilo Mai Hub
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = Config.Title,
    SubTitle    = Config.SubTitle,
    TabWidth    = 160,
    Size        = UDim2.fromOffset(720, 480),
    Acrylic     = true,
    Theme       = Config.Theme,
    MinimizeKey = Enum.KeyCode.RightControl,
    BackgroundImage             = Config.Background,
    BackgroundImageTransparency = Config.SetBackgroundImageTransparency,
    Icon = Config.Icon,
})

_G.DanoninAnimeCapture = Window

-- ============================================================
-- DETECTAR fluentSG — logo após CreateWindow (síncrono)
-- O Fluent pode criar o ScreenGui em PlayerGui OU CoreGui
-- dependendo da versão. Capturamos todos os candidatos e
-- priorizamos o mais recente (último adicionado).
-- ============================================================
local winVis   = true
local fluentSG = nil

local function findFluentSG()
    -- 1. Busca em PlayerGui — qualquer ScreenGui que não seja o nosso
    for _, sg in ipairs(pg:GetChildren()) do
        if sg:IsA("ScreenGui") and sg.Name ~= "ACMinGui" then
            fluentSG = sg  -- pega o último = mais recente
        end
    end
    -- 2. Busca em CoreGui como fallback
    if not fluentSG then
        pcall(function()
            local cg = game:GetService("CoreGui")
            for _, sg in ipairs(cg:GetChildren()) do
                if sg:IsA("ScreenGui")
                and sg.Name ~= "RobloxGui"
                and not sg.Name:find("^Roblox") then
                    -- Confirma estrutura Fluent: Frame filho com UICorner
                    for _, ch in ipairs(sg:GetChildren()) do
                        if ch:IsA("Frame") and ch:FindFirstChildOfClass("UICorner") then
                            fluentSG = sg
                            break
                        end
                    end
                end
                if fluentSG then break end
            end
        end)
    end
    if fluentSG then
        warn("[AC] fluentSG encontrado: "..fluentSG.Name.." | Parent: "..fluentSG.Parent.Name)
    else
        warn("[AC] fluentSG NAO encontrado — minimize pode nao funcionar")
    end
end

-- Captura síncrona imediata
findFluentSG()

-- Se não achou ainda (Fluent carrega assíncrono em alguns forks),
-- tenta novamente após 1 segundo
if not fluentSG then
    task.delay(1, findFluentSG)
end

local minSG = Instance.new("ScreenGui")
minSG.Name            = "ACMinGui"
minSG.ResetOnSpawn    = false
minSG.DisplayOrder    = 9999
minSG.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
minSG.IgnoreGuiInset  = true
minSG.Parent          = pg

local minFrame = Instance.new("Frame", minSG)
minFrame.Size                   = UDim2.fromOffset(56, 56)
minFrame.Position               = UDim2.new(0, 8, 0.5, -28)
minFrame.BackgroundColor3       = Color3.fromRGB(30, 30, 40)
minFrame.BackgroundTransparency = 0.05
minFrame.ZIndex                 = 100
minFrame.Active                 = true   -- ← sinka input na layer
Instance.new("UICorner", minFrame).CornerRadius = UDim.new(0, 14)

local stroke = Instance.new("UIStroke", minFrame)
stroke.Color     = Color3.fromRGB(80, 80, 120)
stroke.Thickness = 1.5

-- Ícone do Hub
local minImg = Instance.new("ImageLabel", minFrame)
minImg.Size                   = UDim2.fromOffset(38, 38)
minImg.Position               = UDim2.new(0.5, -19, 0.5, -19)
minImg.Image                  = Config.Icon
minImg.BackgroundTransparency = 1
minImg.ZIndex                 = 101
minImg.ScaleType              = Enum.ScaleType.Fit

-- Botão invisível por cima — consome TODOS os inputs
local minHit = Instance.new("TextButton", minFrame)
minHit.Size                   = UDim2.fromScale(1, 1)
minHit.BackgroundTransparency = 1
minHit.Text                   = ""
minHit.AutoButtonColor        = false
minHit.Active                 = true    -- ← bloqueia jogo atrás
minHit.Selectable             = false
minHit.ZIndex                 = 102

-- Consome press/touch ANTES de chegar no jogo/NPC
minHit.MouseButton1Down:Connect(function() end)
minHit.InputBegan:Connect(function() end)

-- [busca de fluentSG movida para antes do botão — acima]

local function setButtonOpen(open)
    winVis = open
    if open then
        minFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        stroke.Color              = Color3.fromRGB(80, 80, 120)
        minImg.ImageTransparency  = 0
    else
        minFrame.BackgroundColor3 = Color3.fromRGB(100, 20, 20)
        stroke.Color              = Color3.fromRGB(200, 60, 60)
        minImg.ImageTransparency  = 0.3
    end
end

local function doMin()
    local newState = not winVis
    -- Desativa ProximityPrompts ANTES de esconder
    pcall(function() PPS.Enabled = newState end)
    task.wait()  -- 1 frame

    -- Tenta esconder via ScreenGui.Enabled
    if fluentSG then
        pcall(function() fluentSG.Enabled = newState end)
    end

    -- Fallback: tenta métodos do Window object (alguns forks expõem isso)
    if not fluentSG or not pcall(function()
        -- Verifica se realmente escondeu
        if fluentSG and fluentSG.Enabled ~= newState then error("not applied") end
    end) then
        pcall(function()
            if newState then
                Window.Open and Window:Open()
                Window.Show and Window:Show()
            else
                Window.Close and Window:Close()
                Window.Hide and Window:Hide()
            end
        end)
    end

    setButtonOpen(newState)
end

-- Drag sem SetModalEnabled
local drag, moved, dStart, sPos = false, false, nil, nil

minHit.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        drag   = true
        moved  = false
        dStart = Vector2.new(i.Position.X, i.Position.Y)
        sPos   = minFrame.Position
    end
end)

UIS.InputChanged:Connect(function(i)
    if not drag then return end
    if i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch then
        local dx = i.Position.X - dStart.X
        local dy = i.Position.Y - dStart.Y
        if math.abs(dx) > 6 or math.abs(dy) > 6 then
            moved = true
            minFrame.Position = UDim2.new(
                sPos.X.Scale, sPos.X.Offset + dx,
                sPos.Y.Scale, sPos.Y.Offset + dy)
        end
    end
end)

-- InputEnded faz o toggle — mais confiável no mobile que MouseButton1Click
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        if not drag then return end
        local wasMoved = moved
        drag  = false
        moved = false
        if not wasMoved then doMin() end
    end
end)

-- ============================================================
-- TABS — estrutura Mai Hub
-- ============================================================
local Tabs = {
    Main      = Window:AddTab({ Title = "Main",      Icon = "swords"    }),
    Hatch     = Window:AddTab({ Title = "Hatch",     Icon = "package"   }),
    GameModes = Window:AddTab({ Title = "GameModes", Icon = "gamepad-2" }),
    Misc      = Window:AddTab({ Title = "Misc",      Icon = "wrench"    }),
    Settings  = Window:AddTab({ Title = "Settings",  Icon = "settings"  }),
    Info      = Window:AddTab({ Title = "Info",      Icon = "info"      }),
}
local Options = Fluent.Options

-- ============================================================
-- TAB: MAIN
-- ============================================================
Tabs.Main:AddSection("Auto Farm")

Tabs.Main:AddToggle("AutoClick", { Title = "Auto Click", Default = false })
Options.AutoClick:OnChanged(function(v)
    Safety:Toggle("AutoClick", v, 0.05, function() fire("ClickEvent") end)
end)

Tabs.Main:AddToggle("AutoClicker", { Title = "Auto Clicker (server)", Default = false })
Options.AutoClicker:OnChanged(function(v) fire("AutoClicker", v) end)

Tabs.Main:AddToggle("AutoCatch", { Title = "Auto Catch", Default = false })
Options.AutoCatch:OnChanged(function(v)
    Safety:Toggle("AutoCatch", v, 0.2, function() fire("Catch") end)
end)

Tabs.Main:AddToggle("AutoRun", { Title = "Auto Run", Default = false })
Options.AutoRun:OnChanged(function(v)
    Safety:Toggle("AutoRun", v, 0.1, function() fire("Run") end)
end)

Tabs.Main:AddSection("Stats & Rank")

Tabs.Main:AddToggle("AutoUpgradeStats", { Title = "Auto Upgrade Stats", Default = false })
Options.AutoUpgradeStats:OnChanged(function(v) fire("AutoUpgradeStats", v) end)

Tabs.Main:AddButton({
    Title    = "Upgrade Stats (1x)",
    Callback = function()
        fire("UpgradeStat")
        Fluent:Notify({ Title="Stats", Content="Upgrade enviado", Duration=2 })
    end,
})

Tabs.Main:AddToggle("AutoRankUp", { Title = "Auto Rank Up", Default = false })
Options.AutoRankUp:OnChanged(function(v)
    Safety:Toggle("AutoRankUp", v, 3, function() fire("RankUp") end)
end)

Tabs.Main:AddButton({
    Title    = "Rank Up (1x)",
    Callback = function()
        fire("RankUp")
        Fluent:Notify({ Title="Rank", Content="Rank Up enviado", Duration=2 })
    end,
})

Tabs.Main:AddSection("Progression & Potions")

Tabs.Main:AddToggle("AutoProgression", { Title = "Auto Progression", Default = false })
Options.AutoProgression:OnChanged(function(v) fire("ProgressionAuto", v) end)

Tabs.Main:AddToggle("AutoUpgradeLevels", { Title = "Auto Upgrade Levels", Default = false })
Options.AutoUpgradeLevels:OnChanged(function(v)
    Safety:Toggle("AutoUpgradeLevels", v, 1, function() fire("UpgradeLevels") end)
end)

Tabs.Main:AddButton({
    Title    = "Upgrade Progression (1x)",
    Callback = function()
        fire("UpgradeProgression")
        Fluent:Notify({ Title="Progression", Content="Upgrade enviado", Duration=2 })
    end,
})

Tabs.Main:AddButton({
    Title    = "Use Potions",
    Callback = function()
        fire("UsePotions")
        Fluent:Notify({ Title="Potions", Content="Potions usadas", Duration=2 })
    end,
})

Tabs.Main:AddToggle("AutoPotion", { Title = "Auto Potion", Default = false })
Options.AutoPotion:OnChanged(function(v) fire("TogglePotion", v) end)

Tabs.Main:AddSection("Rewards & Achievements")

Tabs.Main:AddButton({
    Title    = "Claim Daily Reward",
    Callback = function()
        fire("ClaimDailyReward")
        Fluent:Notify({ Title="Rewards", Content="Daily claimed", Duration=2 })
    end,
})

Tabs.Main:AddButton({
    Title    = "Claim All Rewards",
    Callback = function()
        fire("ClaimAllRewards")
        Fluent:Notify({ Title="Rewards", Content="All claimed", Duration=2 })
    end,
})

Tabs.Main:AddToggle("AutoClaimRewards", { Title = "Auto Claim Rewards", Default = false })
Options.AutoClaimRewards:OnChanged(function(v) fire("AutoClaimRewards", v) end)

Tabs.Main:AddButton({
    Title    = "Claim All Achievements",
    Callback = function()
        fire("ClaimAllAchievements")
        Fluent:Notify({ Title="Achievements", Content="All claimed", Duration=2 })
    end,
})

Tabs.Main:AddToggle("AutoAchievement", { Title = "Auto Achievement", Default = false })
Options.AutoAchievement:OnChanged(function(v) fire("AutoAchievement", v) end)

-- ============================================================
-- TAB: HATCH
-- ============================================================
Tabs.Hatch:AddSection("Gacha")

Tabs.Hatch:AddToggle("AutoRollGacha", { Title = "Auto Gacha", Default = false })
Options.AutoRollGacha:OnChanged(function(v) fire("AutoRollGacha", v) end)

Tabs.Hatch:AddButton({
    Title    = "Equip Best Gacha",
    Callback = function()
        fire("EquipeBestGachas")
        Fluent:Notify({ Title="Gacha", Content="Best equipado", Duration=2 })
    end,
})

Tabs.Hatch:AddButton({
    Title    = "Activate Obelisk",
    Callback = function()
        fire("Active0belisk")
        Fluent:Notify({ Title="Obelisk", Content="Ativado", Duration=2 })
    end,
})

Tabs.Hatch:AddSection("Pets")

Tabs.Hatch:AddButton({
    Title    = "Equip Best Pets",
    Callback = function()
        fire("EquipPets")
        Fluent:Notify({ Title="Pets", Content="Best equipado", Duration=2 })
    end,
})

Tabs.Hatch:AddButton({
    Title    = "Lock All Pets",
    Callback = function()
        fire("LockPets")
        Fluent:Notify({ Title="Pets", Content="Lock enviado", Duration=2 })
    end,
})

Tabs.Hatch:AddButton({
    Title    = "Delete Unlocked Pets",
    Callback = function()
        fire("DeletePets")
        Fluent:Notify({ Title="Pets", Content="Delete enviado", Duration=2 })
    end,
})

Tabs.Hatch:AddSection("Swords")

Tabs.Hatch:AddButton({
    Title    = "Equip Best Sword",
    Callback = function()
        fire("EquipSwords")
        Fluent:Notify({ Title="Swords", Content="Best equipado", Duration=2 })
    end,
})

Tabs.Hatch:AddButton({
    Title    = "Lock All Swords",
    Callback = function()
        fire("LockSwords")
        Fluent:Notify({ Title="Swords", Content="Lock enviado", Duration=2 })
    end,
})

Tabs.Hatch:AddToggle("AutoDeleteSword", { Title = "Auto Delete Swords", Default = false })
Options.AutoDeleteSword:OnChanged(function(v) fire("ToggleAutoSwordDelete", v) end)

Tabs.Hatch:AddButton({
    Title    = "Fuse Swords",
    Callback = function()
        fire("FuseSwords")
        Fluent:Notify({ Title="Swords", Content="Fuse enviado", Duration=2 })
    end,
})

Tabs.Hatch:AddSection("Accessories & Aura")

Tabs.Hatch:AddButton({
    Title    = "Equip Best Accessories",
    Callback = function()
        fire("EquipAccessories")
        Fluent:Notify({ Title="Accessories", Content="Best equipado", Duration=2 })
    end,
})

Tabs.Hatch:AddButton({
    Title    = "Lock All Accessories",
    Callback = function()
        fire("LockAccessories")
        Fluent:Notify({ Title="Accessories", Content="Lock enviado", Duration=2 })
    end,
})

Tabs.Hatch:AddToggle("AutoDeleteAcc", { Title = "Auto Delete Accessories", Default = false })
Options.AutoDeleteAcc:OnChanged(function(v) fire("ToggleAutoAccessoryDelete", v) end)

Tabs.Hatch:AddButton({
    Title    = "Equip Best Aura",
    Callback = function()
        fire("EquipBestAura")
        Fluent:Notify({ Title="Aura", Content="Best equipada", Duration=2 })
    end,
})

Tabs.Hatch:AddButton({
    Title    = "Equip Best All",
    Callback = function()
        fire("EquipBestAll")
        Fluent:Notify({ Title="Equipment", Content="Best All equipado", Duration=2 })
    end,
})

Tabs.Hatch:AddButton({
    Title    = "Unequip All",
    Callback = function()
        fire("UnequipAll")
        Fluent:Notify({ Title="Equipment", Content="Unequip All enviado", Duration=2 })
    end,
})

Tabs.Hatch:AddSection("Avatar")

Tabs.Hatch:AddButton({
    Title    = "Max Avatar Level",
    Callback = function()
        fire("MaxAvatarLevel")
        Fluent:Notify({ Title="Avatar", Content="Max Level enviado", Duration=2 })
    end,
})

Tabs.Hatch:AddToggle("AutoAvatarLevel", { Title = "Auto Avatar Level", Default = false })
Options.AutoAvatarLevel:OnChanged(function(v) fire("AutoAvatarLevel", v) end)

Tabs.Hatch:AddButton({
    Title    = "Upgrade Avatar Level",
    Callback = function()
        fire("UpgradeAvatarLevel")
        Fluent:Notify({ Title="Avatar", Content="Upgrade enviado", Duration=2 })
    end,
})

Tabs.Hatch:AddButton({
    Title    = "Craft Avatar",
    Callback = function()
        fire("CraftAvatar")
        Fluent:Notify({ Title="Avatar", Content="Craft enviado", Duration=2 })
    end,
})

-- ============================================================
-- TAB: GAMEMODES
-- ============================================================
Tabs.GameModes:AddSection("Trial")

local TRIAL_TYPES = { "Easy", "Normal", "Hard", "Extreme" }
Tabs.GameModes:AddDropdown("TrialType", {
    Title   = "Select Trial",
    Values  = TRIAL_TYPES,
    Default = "Easy",
})

Tabs.GameModes:AddToggle("AutoTrial", { Title = "Auto Trial", Default = false })
Options.AutoTrial:OnChanged(function(v) fire("AutoTrial", v) end)

Tabs.GameModes:AddButton({
    Title    = "Enter Trial",
    Callback = function()
        fire("EnterTrial", Options.TrialType.Value or "Easy")
        Fluent:Notify({ Title="Trial", Content="Enter "..tostring(Options.TrialType.Value), Duration=2 })
    end,
})

Tabs.GameModes:AddSection("Raid")

local RAID_TYPES = { "Blue Raid 0x", "Red Raid", "Gold Raid", "Black Raid" }
Tabs.GameModes:AddDropdown("RaidType", {
    Title   = "Select Raid",
    Values  = RAID_TYPES,
    Default = "Blue Raid 0x",
})

Tabs.GameModes:AddToggle("AutoRaid", { Title = "Auto Raid", Default = false })
Options.AutoRaid:OnChanged(function(v) fire("AutoRaid", v) end)

Tabs.GameModes:AddButton({
    Title    = "Enter Raid",
    Callback = function()
        fire("EnterRaid", Options.RaidType.Value or "Blue Raid 0x")
        Fluent:Notify({ Title="Raid", Content="Enter "..tostring(Options.RaidType.Value), Duration=2 })
    end,
})

Tabs.GameModes:AddSection("Wave Settings")

Tabs.GameModes:AddSlider("WaveEasy", {
    Title    = "Trial Easy — Leave Wave",
    Min      = 1, Max = 100, Default = 50, Rounding = 0,
})

Tabs.GameModes:AddSlider("WaveRaid", {
    Title    = "Raid — Leave Wave",
    Min      = 1, Max = 100, Default = 50, Rounding = 0,
})

Tabs.GameModes:AddButton({
    Title    = "Salvar Wave Settings",
    Callback = function()
        fire("SetWaveLeave", Options.WaveEasy.Value, Options.WaveRaid.Value)
        Fluent:Notify({
            Title   = "Wave",
            Content = "Easy="..Options.WaveEasy.Value.." Raid="..Options.WaveRaid.Value,
            Duration = 3,
        })
    end,
})

Tabs.GameModes:AddSection("Map & World")

Tabs.GameModes:AddToggle("AutoMobs", { Title = "Auto Mobs", Default = false })
Options.AutoMobs:OnChanged(function(v) fire("AutoMobs", v) end)

Tabs.GameModes:AddButton({
    Title    = "Save Position",
    Callback = function()
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            fire("SavePosition", hrp.Position)
            local p = hrp.Position
            Fluent:Notify({
                Title   = "Position",
                Content = string.format("(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z),
                Duration = 3,
            })
        end
    end,
})

Tabs.GameModes:AddButton({
    Title    = "Map Return",
    Callback = function()
        fire("RecallToRoom")
        Fluent:Notify({ Title="Map", Content="Voltando ao mapa...", Duration=2 })
    end,
})

Tabs.GameModes:AddButton({
    Title    = "Exit Gamemode",
    Callback = function()
        fire("ExitGamemode")
        Fluent:Notify({ Title="Gamemode", Content="Exit enviado", Duration=2 })
    end,
})

Tabs.GameModes:AddSection("Teleport")

Tabs.GameModes:AddInput("TeleportDest", {
    Title       = "Destino",
    Placeholder = "Nome do mundo...",
})

Tabs.GameModes:AddButton({
    Title    = "Teleportar",
    Callback = function()
        local dest = Options.TeleportDest.Value or ""
        if dest == "" then
            Fluent:Notify({ Title="Teleport", Content="Digite um destino!", Duration=2 })
            return
        end
        fire("Teleport", dest)
        Fluent:Notify({ Title="Teleport", Content="Indo para "..dest, Duration=2 })
    end,
})

Tabs.GameModes:AddSection("Quests")

Tabs.GameModes:AddButton({
    Title    = "Claim All Quest Objectives",
    Callback = function()
        fire("ClaimAllQuestObjectives")
        Fluent:Notify({ Title="Quests", Content="All objectives claimed", Duration=2 })
    end,
})

Tabs.GameModes:AddButton({
    Title    = "Complete All Quests",
    Callback = function()
        fire("CompleteAllQuests")
        Fluent:Notify({ Title="Quests", Content="All completed", Duration=2 })
    end,
})

Tabs.GameModes:AddButton({
    Title    = "Complete Index Quests",
    Callback = function()
        fire("CompleteIndexQuests")
        Fluent:Notify({ Title="Quests", Content="Index completed", Duration=2 })
    end,
})

Tabs.GameModes:AddButton({
    Title    = "Track All Quests",
    Callback = function()
        fire("TrackAllQuests")
        Fluent:Notify({ Title="Quests", Content="All tracked", Duration=2 })
    end,
})

-- ============================================================
-- TAB: MISC
-- ============================================================
Tabs.Misc:AddSection("Codes")

Tabs.Misc:AddInput("ClaimCodeInput", {
    Title       = "Código",
    Placeholder = "Digite o código...",
})

Tabs.Misc:AddButton({
    Title    = "Resgatar Código",
    Callback = function()
        local code = Options.ClaimCodeInput.Value or ""
        if code == "" then
            Fluent:Notify({ Title="Code", Content="Digite um código!", Duration=2 })
            return
        end
        fire("ClaimCode", code)
        Fluent:Notify({ Title="Code", Content=code.." enviado", Duration=2 })
    end,
})

Tabs.Misc:AddSection("Verificações")

Tabs.Misc:AddButton({
    Title    = "Verify Group",
    Callback = function()
        fire("VerifyPlayerInGroup")
        Fluent:Notify({ Title="Verify", Content="Group verify enviado", Duration=2 })
    end,
})

Tabs.Misc:AddButton({
    Title    = "Favorite Game",
    Callback = function()
        fire("VerifyPlayerFavorityGame")
        Fluent:Notify({ Title="Verify", Content="Favorite enviado", Duration=2 })
    end,
})

Tabs.Misc:AddButton({
    Title    = "Like Game",
    Callback = function()
        fire("VerifyPlayerLikedGame")
        Fluent:Notify({ Title="Verify", Content="Like enviado", Duration=2 })
    end,
})

Tabs.Misc:AddButton({
    Title    = "Favorite World",
    Callback = function()
        fire("FavorityWorld")
        Fluent:Notify({ Title="World", Content="World favoritado", Duration=2 })
    end,
})

Tabs.Misc:AddSection("Time Chamber")

Tabs.Misc:AddButton({
    Title    = "Quit Time Chamber",
    Callback = function()
        fire("QuitTimeChamber")
        Fluent:Notify({ Title="Time Chamber", Content="Quit enviado", Duration=2 })
    end,
})

Tabs.Misc:AddButton({
    Title    = "Return Time Chamber",
    Callback = function()
        fire("ReturnTimeChamber")
        Fluent:Notify({ Title="Time Chamber", Content="Return enviado", Duration=2 })
    end,
})

Tabs.Misc:AddSection("Debug")

Tabs.Misc:AddButton({
    Title    = "Listar Remotes",
    Callback = function()
        warn("=== ANIME CAPTURE — RemotesFolder ===")
        local names = {}
        for _, r in ipairs(RF:GetChildren()) do
            table.insert(names, "  "..r.Name.." ["..r.ClassName.."]")
        end
        table.sort(names)
        for _, n in ipairs(names) do warn(n) end
        Fluent:Notify({ Title="Remotes", Content=#names.." encontrados no console", Duration=3 })
    end,
})

-- ============================================================
-- TAB: SETTINGS
-- ============================================================
local settingsOk = true

local ok1, err1 = pcall(function()
    SaveManager:SetLibrary(Fluent)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({})
    SaveManager:SetFolder("Danonin/AnimeCapture/configs")
end)
if not ok1 then
    warn("[AC] SaveManager setup falhou: "..tostring(err1))
    settingsOk = false
end

local ok2, err2 = pcall(function()
    InterfaceManager:SetLibrary(Fluent)
    InterfaceManager:SetFolder("Danonin/AnimeCapture")
    InterfaceManager:BuildInterfaceSection(Tabs.Settings)
end)
if not ok2 then
    warn("[AC] InterfaceManager build falhou: "..tostring(err2))
    settingsOk = false
end

local ok3, err3 = pcall(function()
    SaveManager:BuildConfigSection(Tabs.Settings)
end)
if not ok3 then
    warn("[AC] SaveManager build falhou: "..tostring(err3))
    settingsOk = false
end

-- Se tudo falhou, mostra aviso na aba em vez de ficar vazia
if not settingsOk then
    Tabs.Settings:AddParagraph({
        Title   = "Settings indisponível",
        Content = "SaveManager/InterfaceManager incompatível com este Fluent.\nVerifique se Libs/SaveManager.lua e Libs/InterfaceManager.lua estão no seu GitHub.",
    })
end

-- ============================================================
-- TAB: INFO — estilo Mai Hub About
-- ============================================================
Tabs.Info:AddSection("Danonin Hub")

Tabs.Info:AddParagraph({ Title="Script",  Content="Anime Capture v3.2" })
Tabs.Info:AddParagraph({ Title="Dev",     Content=Config.Author })
Tabs.Info:AddParagraph({ Title="Discord", Content=Config.Discord })
Tabs.Info:AddParagraph({ Title="Status",  Content="Script: Online | Delta: Supported" })

Tabs.Info:AddButton({
    Title    = "Copiar Discord",
    Callback = function()
        setclipboard("https://"..Config.Discord)
        Fluent:Notify({ Title="Copiado!", Content=Config.Discord, Duration=3 })
    end,
})

Tabs.Info:AddSection("Keybinds")
Tabs.Info:AddParagraph({
    Title   = "Atalhos",
    Content = "RightControl — Abrir/Fechar GUI\nBotão Ícone — Toggle / Arrastar",
})

-- ============================================================
-- INIT
-- ============================================================
pcall(function() SaveManager:LoadAutoloadConfig() end)
Window:SelectTab(Tabs.Main)

Fluent:Notify({
    Title    = "Danonin Hub",
    Content  = "Anime Capture v3.2 carregado!",
    Duration = 5,
})

warn("[AC] v3.2 carregado | Theme: "..Config.Theme.." | "..#RF:GetChildren().." remotes | fluentSG: "..(fluentSG and fluentSG.Name or "nil"))
