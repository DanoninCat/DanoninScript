-- ============================================================
--  DANONIN HUB | Anime Capture v2.0
--  UI inspirada no Mai Hub — Tabs: Main, Hatch, GameModes, Misc, Settings, Info
-- ============================================================

if _G.DanoninAnimeCapture then
    pcall(function() _G.DanoninAnimeCapture:Destroy() end)
end

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local UIS     = game:GetService("UserInputService")
local PPS     = game:GetService("ProximityPromptService")
local player  = Players.LocalPlayer

repeat task.wait() until player:FindFirstChild("PlayerGui")

-- ============================================================
-- FLUENT
-- ============================================================
local ok1, Fluent = pcall(function()
    return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua", true))()
end)
if not ok1 then
    local ok1b
    ok1b, Fluent = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/dist/main.lua", true))()
    end)
    if not ok1b then warn("[AC] Fluent falhou") return end
end

local ok2, SaveManager = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua", true))()
end)
if not ok2 then warn("[AC] SaveManager falhou") return end

local ok3, InterfaceManager = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua", true))()
end)
if not ok3 then warn("[AC] InterfaceManager falhou") return end

-- ============================================================
-- REMOTES — ReplicatedStorage.RemotesFolder.*
-- ============================================================
local RF = RS:WaitForChild("RemotesFolder", 10)
if not RF then warn("[AC] RemotesFolder nao encontrado!") return end

local function fire(name, ...)
    local r = RF:FindFirstChild(name)
    if not r then warn("[AC] Remote nao encontrado: "..name) return end
    local args = {...}
    pcall(function() r:FireServer(table.unpack(args)) end)
end

local function invoke(name, ...)
    local r = RF:FindFirstChild(name)
    if not r then warn("[AC] Remote nao encontrado: "..name) return nil end
    local args = {...}
    local ok, res = pcall(function() return r:InvokeServer(table.unpack(args)) end)
    return ok and res or nil
end

-- ============================================================
-- SAFETY
-- ============================================================
local Safety = { _threads = {}, _active = {} }

function Safety:Kill(key)
    self._active[key] = false
    if self._threads[key] then
        pcall(function() task.cancel(self._threads[key]) end)
        self._threads[key] = nil
    end
end

function Safety:KillAll()
    for k in pairs(self._threads) do self:Kill(k) end
end

function Safety:Loop(key, interval, fn)
    self:Kill(key)
    self._active[key] = true
    local t = task.spawn(function()
        while self._active[key] do
            task.wait(interval)
            if self._active[key] then
                local ok, err = pcall(fn)
                if not ok then warn("[AC:"..key.."] "..tostring(err)) end
            end
        end
        self._threads[key] = nil
    end)
    self._threads[key] = t
end

function Safety:Toggle(key, enabled, interval, fn)
    if enabled then self:Loop(key, interval, fn) else self:Kill(key) end
end

-- ============================================================
-- FLUENT WINDOW — estilo Mai Hub
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Danonin Hub",
    SubTitle    = "Anime Capture v2.0",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(720, 480),
    Acrylic     = true,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

_G.DanoninAnimeCapture = Window

-- ============================================================
-- BOTÃO FLUTUANTE — v2.0
-- Fix definitivo mobile:
--   Active = true no Frame e Button
--   MouseButton1Down vazio consome o clique
--   PPS.Enabled = false quando UI fechada
-- ============================================================
local winVis = true
local pg     = player:WaitForChild("PlayerGui", 10)

local minSG = Instance.new("ScreenGui")
minSG.Name            = "ACMinGui"
minSG.ResetOnSpawn    = false
minSG.DisplayOrder    = 9999
minSG.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
minSG.IgnoreGuiInset  = true
minSG.Parent          = pg

local minFrame = Instance.new("Frame", minSG)
minFrame.Size                   = UDim2.fromOffset(54, 54)
minFrame.Position               = UDim2.new(0, 8, 0.5, -27)
minFrame.BackgroundColor3       = Color3.fromRGB(0, 90, 200)
minFrame.BackgroundTransparency = 0.1
minFrame.ZIndex                 = 100
minFrame.Active                 = true
Instance.new("UICorner", minFrame).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", minFrame)
stroke.Color     = Color3.fromRGB(60, 140, 255)
stroke.Thickness = 2

local minImg = Instance.new("ImageLabel", minFrame)
minImg.Size                   = UDim2.fromOffset(36, 36)
minImg.Position               = UDim2.new(0.5, -18, 0.5, -18)
minImg.Image                  = "rbxassetid://128797153413520"
minImg.BackgroundTransparency = 1
minImg.ZIndex                 = 101

-- TextButton com Active=true + MouseButton1Down vazio = bloqueia jogo atrás
local minHit = Instance.new("TextButton", minFrame)
minHit.Size                   = UDim2.fromScale(1, 1)
minHit.BackgroundTransparency = 1
minHit.Text                   = ""
minHit.AutoButtonColor        = false
minHit.Active                 = true
minHit.Selectable             = false
minHit.ZIndex                 = 102
minHit.MouseButton1Down:Connect(function() end)  -- consome press
minHit.InputBegan:Connect(function() end)         -- consome touch

-- Busca GUI do Fluent
local fluentSG = nil
task.spawn(function()
    for _ = 1, 40 do
        task.wait(0.5)
        -- Tenta pelo nome "Fluent"
        for _, sg in ipairs(pg:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Name == "Fluent" then
                fluentSG = sg break
            end
        end
        -- Fallback estrutural
        if not fluentSG then
            for _, sg in ipairs(pg:GetChildren()) do
                if sg:IsA("ScreenGui") and sg.Name ~= "ACMinGui" then
                    for _, ch in ipairs(sg:GetChildren()) do
                        if ch:IsA("Frame") and ch:FindFirstChildOfClass("UICorner") then
                            fluentSG = sg break
                        end
                    end
                end
                if fluentSG then break end
            end
        end
        if not fluentSG then
            pcall(function()
                for _, sg in ipairs(game:GetService("CoreGui"):GetChildren()) do
                    if sg:IsA("ScreenGui") and sg.Name ~= "RobloxGui" then
                        fluentSG = sg break
                    end
                end
            end)
        end
        if fluentSG then warn("[AC] Fluent GUI: "..fluentSG.Name) break end
    end
end)

local function setButtonState(open)
    winVis = open
    minFrame.BackgroundColor3 = open and Color3.fromRGB(0,90,200) or Color3.fromRGB(140,30,30)
    stroke.Color              = open and Color3.fromRGB(60,140,255) or Color3.fromRGB(220,80,80)
end

local function doMin()
    local newState = not winVis
    if fluentSG then pcall(function() fluentSG.Enabled = newState end) end
    -- Desativa ProximityPrompts quando UI fecha (evita NPC/shop ao clicar)
    pcall(function() PPS.Enabled = newState end)
    setButtonState(newState)
end

-- Drag
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

-- InputEnded faz o toggle (não MouseButton1Click) — mais confiável no mobile
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
-- TABS — estrutura igual ao Mai Hub
-- Main | Hatch | GameModes | Misc | Settings | Info
-- ============================================================
local Tabs = {
    Main      = Window:AddTab({ Title = "Main",      Icon = "swords"   }),
    Hatch     = Window:AddTab({ Title = "Hatch",     Icon = "package"  }),
    GameModes = Window:AddTab({ Title = "GameModes", Icon = "gamepad-2"}),
    Misc      = Window:AddTab({ Title = "Misc",      Icon = "wrench"   }),
    Settings  = Window:AddTab({ Title = "Settings",  Icon = "settings" }),
    Info      = Window:AddTab({ Title = "Info",      Icon = "info"     }),
}
local Options = Fluent.Options

-- ============================================================
-- TAB: MAIN — Auto Click, Catch, Sell, Stats, Rank, Progression
-- ============================================================
Tabs.Main:AddSection("Auto Farm")

Tabs.Main:AddToggle("AutoClick", { Title = "Auto Click", Default = false })
Options.AutoClick:OnChanged(function(v)
    Safety:Toggle("AutoClick", v, 0.05, function() fire("ClickEvent") end)
end)

Tabs.Main:AddToggle("AutoClicker", { Title = "Auto Clicker (server)", Default = false })
Options.AutoClicker:OnChanged(function(v)
    fire("AutoClicker", v)
end)

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
Options.AutoUpgradeStats:OnChanged(function(v)
    fire("AutoUpgradeStats", v)
end)

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

Tabs.Main:AddSection("Progression")

Tabs.Main:AddToggle("AutoProgression", { Title = "Auto Progression", Default = false })
Options.AutoProgression:OnChanged(function(v)
    fire("ProgressionAuto", v)
end)

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

Tabs.Main:AddSection("Potions & Rewards")

Tabs.Main:AddButton({
    Title    = "Use Potions",
    Callback = function()
        fire("UsePotions")
        Fluent:Notify({ Title="Potions", Content="Potions usadas", Duration=2 })
    end,
})

Tabs.Main:AddToggle("AutoPotion", { Title = "Auto Potion", Default = false })
Options.AutoPotion:OnChanged(function(v) fire("TogglePotion", v) end)

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
-- TAB: HATCH — Gacha, Pets, Swords, Accessories, Avatar
-- ============================================================
Tabs.Hatch:AddSection("Gachas")

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
-- TAB: GAMEMODES — Trial, Raid, World, Quests
-- ============================================================
Tabs.GameModes:AddSection("Trial")

Tabs.GameModes:AddToggle("AutoTrial", { Title = "Auto Trial", Default = false })
Options.AutoTrial:OnChanged(function(v) fire("AutoTrial", v) end)

local TRIAL_TYPES = { "Easy", "Normal", "Hard", "Extreme" }
Tabs.GameModes:AddDropdown("TrialType", {
    Title   = "Select Trial",
    Values  = TRIAL_TYPES,
    Default = "Easy",
})

Tabs.GameModes:AddButton({
    Title    = "Enter Trial",
    Callback = function()
        fire("EnterTrial", Options.TrialType.Value or "Easy")
        Fluent:Notify({ Title="Trial", Content="Enter "..Options.TrialType.Value, Duration=2 })
    end,
})

Tabs.GameModes:AddSection("Raid")

Tabs.GameModes:AddToggle("AutoRaid", { Title = "Auto Raid", Default = false })
Options.AutoRaid:OnChanged(function(v) fire("AutoRaid", v) end)

local RAID_TYPES = { "Blue Raid 0x", "Red Raid", "Gold Raid", "Black Raid" }
Tabs.GameModes:AddDropdown("RaidType", {
    Title   = "Select Raid",
    Values  = RAID_TYPES,
    Default = "Blue Raid 0x",
})

Tabs.GameModes:AddButton({
    Title    = "Enter Raid",
    Callback = function()
        fire("EnterRaid", Options.RaidType.Value or "Blue Raid 0x")
        Fluent:Notify({ Title="Raid", Content="Enter "..Options.RaidType.Value, Duration=2 })
    end,
})

Tabs.GameModes:AddSection("Leave Wave")

local function makeWaveInput(title, key, default)
    Tabs.GameModes:AddSlider(key, {
        Title    = title,
        Min      = 1,
        Max      = 100,
        Default  = default,
        Rounding = 0,
    })
end
makeWaveInput("Trial Easy — Leave at Wave", "WaveEasy", 50)
makeWaveInput("Raid — Leave at Wave",       "WaveRaid", 50)

Tabs.GameModes:AddButton({
    Title    = "Save Wave Settings",
    Callback = function()
        fire("SetWaveLeave", Options.WaveEasy.Value, Options.WaveRaid.Value)
        Fluent:Notify({ Title="Wave", Content="Salvo: Easy="..Options.WaveEasy.Value.." Raid="..Options.WaveRaid.Value, Duration=3 })
    end,
})

Tabs.GameModes:AddSection("World & Map")

Tabs.GameModes:AddToggle("AutoMobs", { Title = "Auto Mobs", Default = false })
Options.AutoMobs:OnChanged(function(v) fire("AutoMobs", v) end)

Tabs.GameModes:AddButton({
    Title    = "Save Position",
    Callback = function()
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            fire("SavePosition", hrp.Position)
            Fluent:Notify({ Title="Position", Content="Salvo: "..tostring(hrp.Position), Duration=3 })
        end
    end,
})

Tabs.GameModes:AddButton({
    Title    = "Exit Gamemode",
    Callback = function()
        fire("ExitGamemode")
        Fluent:Notify({ Title="Gamemode", Content="Exit enviado", Duration=2 })
    end,
})

Tabs.GameModes:AddButton({
    Title    = "Recall to Room",
    Callback = function()
        fire("RecallToRoom")
        Fluent:Notify({ Title="Room", Content="Recall enviado", Duration=2 })
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
        Fluent:Notify({ Title="Quests", Content="All quests completed", Duration=2 })
    end,
})

Tabs.GameModes:AddButton({
    Title    = "Complete Index Quests",
    Callback = function()
        fire("CompleteIndexQuests")
        Fluent:Notify({ Title="Quests", Content="Index quests completed", Duration=2 })
    end,
})

Tabs.GameModes:AddButton({
    Title    = "Track All Quests",
    Callback = function()
        fire("TrackAllQuests")
        Fluent:Notify({ Title="Quests", Content="All quests tracked", Duration=2 })
    end,
})

-- ============================================================
-- TAB: MISC — Codes, Verify, Time Chamber, Favorite
-- ============================================================
Tabs.Misc:AddSection("Codes")

Tabs.Misc:AddInput("ClaimCodeInput", {
    Title       = "Code",
    Placeholder = "Digite o código...",
})

Tabs.Misc:AddButton({
    Title    = "Claim Code",
    Callback = function()
        local code = Options.ClaimCodeInput.Value or ""
        if code == "" then
            Fluent:Notify({ Title="Code", Content="Digite um código!", Duration=2 })
            return
        end
        fire("ClaimCode", code)
        Fluent:Notify({ Title="Code", Content="Code: "..code.." enviado", Duration=2 })
    end,
})

Tabs.Misc:AddSection("Verify")

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

Tabs.Misc:AddSection("Remote List")

Tabs.Misc:AddParagraph({ Title="Remotes", Content="#RF:GetChildren() carregados" })

Tabs.Misc:AddButton({
    Title    = "Listar Remotes no Console",
    Callback = function()
        warn("=== ANIME CAPTURE — Remotes ===")
        local names = {}
        for _, r in ipairs(RF:GetChildren()) do
            table.insert(names, r.Name.." ["..r.ClassName.."]")
        end
        table.sort(names)
        for _, n in ipairs(names) do warn("  "..n) end
        Fluent:Notify({ Title="Remotes", Content=#names.." encontrados", Duration=3 })
    end,
})

-- ============================================================
-- TAB: SETTINGS
-- ============================================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("Danonin/AnimeCapture")
SaveManager:SetFolder("Danonin/AnimeCapture/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

-- ============================================================
-- TAB: INFO
-- ============================================================
Tabs.Info:AddSection("Danonin Hub")
Tabs.Info:AddParagraph({ Title="Dev",     Content="Danonin" })
Tabs.Info:AddParagraph({ Title="Discord", Content="discord.gg/qDeZ9sEdGY" })
Tabs.Info:AddButton({
    Title    = "Copiar Discord",
    Callback = function()
        setclipboard("https://discord.gg/qDeZ9sEdGY")
        Fluent:Notify({ Title="Copiado!", Content="discord.gg/qDeZ9sEdGY", Duration=2 })
    end,
})
Tabs.Info:AddParagraph({
    Title   = "Keybinds",
    Content = "RightControl — Abrir/Fechar GUI\nBotão — Toggle / Arrastar",
})
Tabs.Info:AddParagraph({
    Title   = "Status",
    Content = "Script: Online | Executor: Delta ✓",
})

-- ============================================================
-- INIT
-- ============================================================
SaveManager:LoadAutoloadConfig()
Window:SelectTab(Tabs.Main)

Fluent:Notify({
    Title    = "Anime Capture v2.0",
    Content  = "Carregado! "..#RF:GetChildren().." remotes.",
    Duration = 4,
})

warn("[AC] Anime Capture v2.0 carregado | "..#RF:GetChildren().." remotes em RemotesFolder")
