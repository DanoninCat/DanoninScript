-- ============================================================
--  DANONIN HUB | Anime Capture
--  Remotes: ReplicatedStorage.RemotesFolder.*
-- ============================================================

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local UIS     = game:GetService("UserInputService")
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
    if not ok1b then warn("[AC] Fluent falhou: "..tostring(Fluent)) return end
end

local ok2, SaveManager = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua", true))()
end)
if not ok2 then warn("[AC] SaveManager: "..tostring(SaveManager)) return end

local ok3, InterfaceManager = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua", true))()
end)
if not ok3 then warn("[AC] InterfaceManager: "..tostring(InterfaceManager)) return end

-- ============================================================
-- REMOTES — ReplicatedStorage.RemotesFolder.*
-- ============================================================
local RF = RS:WaitForChild("RemotesFolder", 10)
if not RF then warn("[AC] RemotesFolder nao encontrado!") return end

local function fire(name, ...)
    local args = {...}
    local r    = RF:FindFirstChild(name)
    if not r then warn("[AC] Remote nao encontrado: "..name) return end
    pcall(function() r:FireServer(table.unpack(args)) end)
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
            if self._active[key] then pcall(fn) end
        end
        self._threads[key] = nil
    end)
    self._threads[key] = t
end

function Safety:Toggle(key, enabled, interval, fn)
    if enabled then self:Loop(key, interval, fn) else self:Kill(key) end
end

-- ============================================================
-- FLUENT WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Anime Capture",
    SubTitle    = "v1.1 | by Danonin",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(720, 480),
    Acrylic     = true,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

-- ============================================================
-- BOTÃO FLUTUANTE
-- ============================================================
local winVis = true
local pg     = player:WaitForChild("PlayerGui", 10)

local minSG = Instance.new("ScreenGui")
minSG.Name           = "ACMinGui"
minSG.ResetOnSpawn   = false
minSG.DisplayOrder   = 9999
minSG.IgnoreGuiInset = true
minSG.Parent         = pg

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

local minHit = Instance.new("TextButton", minFrame)
minHit.Size                   = UDim2.fromScale(1, 1)
minHit.BackgroundTransparency = 1
minHit.Text                   = ""
minHit.AutoButtonColor        = false
minHit.Active                 = true
minHit.ZIndex                 = 102
minHit.MouseButton1Down:Connect(function() end)
minHit.InputBegan:Connect(function() end)

local fluentSG = nil
task.spawn(function()
    for _ = 1, 40 do
        task.wait(0.5)
        -- Busca pelo nome "Fluent" primeiro
        for _, sg in ipairs(pg:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Name == "Fluent" then
                fluentSG = sg
                break
            end
        end
        -- Fallback: qualquer ScreenGui com Frame+UICorner (estrutura do Fluent)
        if not fluentSG then
            for _, sg in ipairs(pg:GetChildren()) do
                if sg:IsA("ScreenGui") and sg.Name ~= "ACMinGui" then
                    for _, ch in ipairs(sg:GetChildren()) do
                        if ch:IsA("Frame") and ch:FindFirstChildOfClass("UICorner") then
                            fluentSG = sg
                            break
                        end
                    end
                end
                if fluentSG then break end
            end
        end
        if fluentSG then
            warn("[AC] Fluent GUI: " .. fluentSG.Name)
            break
        end
    end
end)

local function doMin()
    winVis = not winVis
    if fluentSG then pcall(function() fluentSG.Enabled = winVis end) end
    minFrame.BackgroundColor3 = winVis
        and Color3.fromRGB(0, 90, 200) or Color3.fromRGB(140, 30, 30)
    stroke.Color = winVis
        and Color3.fromRGB(60, 140, 255) or Color3.fromRGB(220, 80, 80)
end

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

-- MouseButton1Click consome o evento impedindo de passar pro jogo
minHit.MouseButton1Click:Connect(function()
    if moved then return end
    doMin()
end)

UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        drag  = false
        moved = false
    end
end)

-- ============================================================
-- TABS
-- ============================================================
local Tabs = {
    Farm      = Window:AddTab({ Title = "Farm",       Icon = "swords"        }),
    Rewards   = Window:AddTab({ Title = "Rewards",    Icon = "gift"          }),
    Quests    = Window:AddTab({ Title = "Quests",     Icon = "scroll"        }),
    Equipment = Window:AddTab({ Title = "Equipment",  Icon = "shield"        }),
    Gacha     = Window:AddTab({ Title = "Gacha",      Icon = "star"          }),
    Avatar    = Window:AddTab({ Title = "Avatar",     Icon = "user"          }),
    World     = Window:AddTab({ Title = "World",      Icon = "map-pin"       }),
    Settings  = Window:AddTab({ Title = "Settings",   Icon = "settings"      }),
    Info      = Window:AddTab({ Title = "Info",       Icon = "info"          }),
}
local Options = Fluent.Options

-- ============================================================
-- TAB: FARM
-- ============================================================
Tabs.Farm:AddSection("Auto Click & Catch")

Tabs.Farm:AddToggle("AutoClick", { Title = "Auto Click", Default = false })
Options.AutoClick:OnChanged(function(v)
    Safety:Toggle("AutoClick", v, 0.05, function()
        fire("ClickEvent")
    end)
end)

Tabs.Farm:AddToggle("AutoClicker", { Title = "Auto Clicker (server)", Default = false })
Options.AutoClicker:OnChanged(function(v)
    if v then
        fire("AutoClicker", true)
    else
        fire("AutoClicker", false)
    end
end)

Tabs.Farm:AddToggle("AutoRun", { Title = "Auto Run", Default = false })
Options.AutoRun:OnChanged(function(v)
    Safety:Toggle("AutoRun", v, 0.1, function()
        fire("Run")
    end)
end)

Tabs.Farm:AddToggle("AutoCatch", { Title = "Auto Catch", Default = false })
Options.AutoCatch:OnChanged(function(v)
    Safety:Toggle("AutoCatch", v, 0.2, function()
        fire("Catch")
    end)
end)

Tabs.Farm:AddSection("Stats & Rank")

Tabs.Farm:AddToggle("AutoUpgradeStats", { Title = "Auto Upgrade Stats", Default = false })
Options.AutoUpgradeStats:OnChanged(function(v)
    if v then
        fire("AutoUpgradeStats", true)
    else
        fire("AutoUpgradeStats", false)
    end
end)

Tabs.Farm:AddButton({
    Title    = "Upgrade Stats (1x)",
    Callback = function()
        fire("UpgradeStat")
        Fluent:Notify({ Title="Stats", Content="Upgrade enviado", Duration=2 })
    end,
})

Tabs.Farm:AddToggle("AutoRankUp", { Title = "Auto Rank Up", Default = false })
Options.AutoRankUp:OnChanged(function(v)
    Safety:Toggle("AutoRankUp", v, 3, function()
        fire("RankUp")
    end)
end)

Tabs.Farm:AddButton({
    Title    = "Rank Up (1x)",
    Callback = function()
        fire("RankUp")
        Fluent:Notify({ Title="Rank", Content="Rank Up enviado", Duration=2 })
    end,
})

Tabs.Farm:AddSection("Levels & Progression")

Tabs.Farm:AddToggle("AutoProgression", { Title = "Auto Progression", Default = false })
Options.AutoProgression:OnChanged(function(v)
    if v then
        fire("ProgressionAuto", true)
    else
        fire("ProgressionAuto", false)
    end
end)

Tabs.Farm:AddToggle("AutoUpgradeLevels", { Title = "Auto Upgrade Levels", Default = false })
Options.AutoUpgradeLevels:OnChanged(function(v)
    Safety:Toggle("AutoUpgradeLevels", v, 1, function()
        fire("UpgradeLevels")
    end)
end)

Tabs.Farm:AddButton({
    Title    = "Upgrade Progression (1x)",
    Callback = function()
        fire("UpgradeProgression")
        Fluent:Notify({ Title="Progression", Content="Upgrade enviado", Duration=2 })
    end,
})

Tabs.Farm:AddSection("Potions")

Tabs.Farm:AddButton({
    Title    = "Use Potions",
    Callback = function()
        fire("UsePotions")
        Fluent:Notify({ Title="Potions", Content="Potions usadas", Duration=2 })
    end,
})

Tabs.Farm:AddToggle("AutoPotion", { Title = "Auto Potion Toggle", Default = false })
Options.AutoPotion:OnChanged(function(v)
    fire("TogglePotion", v)
end)

-- ============================================================
-- TAB: REWARDS
-- ============================================================
Tabs.Rewards:AddSection("Daily & Time")

Tabs.Rewards:AddButton({
    Title    = "Claim Daily Reward",
    Callback = function()
        fire("ClaimDailyReward")
        Fluent:Notify({ Title="Rewards", Content="Daily Reward claimed", Duration=2 })
    end,
})

Tabs.Rewards:AddButton({
    Title    = "Claim Time Reward",
    Callback = function()
        fire("ClaimTimeReward")
        Fluent:Notify({ Title="Rewards", Content="Time Reward claimed", Duration=2 })
    end,
})

Tabs.Rewards:AddButton({
    Title    = "Claim All Rewards",
    Callback = function()
        fire("ClaimAllRewards")
        Fluent:Notify({ Title="Rewards", Content="All Rewards claimed", Duration=2 })
    end,
})

Tabs.Rewards:AddToggle("AutoClaimRewards", { Title = "Auto Claim Rewards", Default = false })
Options.AutoClaimRewards:OnChanged(function(v)
    if v then
        fire("AutoClaimRewards", true)
    else
        fire("AutoClaimRewards", false)
    end
end)

Tabs.Rewards:AddSection("Achievements")

Tabs.Rewards:AddButton({
    Title    = "Claim All Achievements",
    Callback = function()
        fire("ClaimAllAchievements")
        Fluent:Notify({ Title="Achievements", Content="All claimed", Duration=2 })
    end,
})

Tabs.Rewards:AddToggle("AutoAchievement", { Title = "Auto Achievement", Default = false })
Options.AutoAchievement:OnChanged(function(v)
    if v then
        fire("AutoAchievement", true)
    else
        fire("AutoAchievement", false)
    end
end)

-- ============================================================
-- TAB: QUESTS
-- ============================================================
Tabs.Quests:AddSection("Quest Automation")

Tabs.Quests:AddButton({
    Title    = "Claim All Quest Objectives",
    Callback = function()
        fire("ClaimAllQuestObjectives")
        Fluent:Notify({ Title="Quests", Content="All objectives claimed", Duration=2 })
    end,
})

Tabs.Quests:AddButton({
    Title    = "Complete All Quests",
    Callback = function()
        fire("CompleteAllQuests")
        Fluent:Notify({ Title="Quests", Content="All quests completed", Duration=2 })
    end,
})

Tabs.Quests:AddButton({
    Title    = "Complete Index Quests",
    Callback = function()
        fire("CompleteIndexQuests")
        Fluent:Notify({ Title="Quests", Content="Index quests completed", Duration=2 })
    end,
})

Tabs.Quests:AddButton({
    Title    = "Track All Quests",
    Callback = function()
        fire("TrackAllQuests")
        Fluent:Notify({ Title="Quests", Content="All quests tracked", Duration=2 })
    end,
})

Tabs.Quests:AddButton({
    Title    = "Untrack All Quests",
    Callback = function()
        fire("UntrackAllQuests")
        Fluent:Notify({ Title="Quests", Content="All quests untracked", Duration=2 })
    end,
})

-- ============================================================
-- TAB: EQUIPMENT
-- ============================================================
Tabs.Equipment:AddSection("Pets")

Tabs.Equipment:AddButton({
    Title    = "Equip Best Pets",
    Callback = function()
        fire("EquipPets")
        Fluent:Notify({ Title="Pets", Content="Equip enviado", Duration=2 })
    end,
})

Tabs.Equipment:AddButton({
    Title    = "Lock All Pets",
    Callback = function()
        fire("LockPets")
        Fluent:Notify({ Title="Pets", Content="Lock enviado", Duration=2 })
    end,
})

Tabs.Equipment:AddButton({
    Title    = "Delete Unlocked Pets",
    Callback = function()
        fire("DeletePets")
        Fluent:Notify({ Title="Pets", Content="Delete enviado", Duration=2 })
    end,
})

Tabs.Equipment:AddSection("Swords")

Tabs.Equipment:AddButton({
    Title    = "Equip Best Sword",
    Callback = function()
        fire("EquipSwords")
        Fluent:Notify({ Title="Swords", Content="Equip enviado", Duration=2 })
    end,
})

Tabs.Equipment:AddButton({
    Title    = "Lock All Swords",
    Callback = function()
        fire("LockSwords")
        Fluent:Notify({ Title="Swords", Content="Lock enviado", Duration=2 })
    end,
})

Tabs.Equipment:AddToggle("AutoDeleteSword", { Title = "Auto Delete Swords", Default = false })
Options.AutoDeleteSword:OnChanged(function(v)
    fire("ToggleAutoSwordDelete", v)
end)

Tabs.Equipment:AddButton({
    Title    = "Fuse Swords",
    Callback = function()
        fire("FuseSwords")
        Fluent:Notify({ Title="Swords", Content="Fuse enviado", Duration=2 })
    end,
})

Tabs.Equipment:AddSection("Accessories")

Tabs.Equipment:AddButton({
    Title    = "Equip Best Accessories",
    Callback = function()
        fire("EquipAccessories")
        Fluent:Notify({ Title="Accessories", Content="Equip enviado", Duration=2 })
    end,
})

Tabs.Equipment:AddButton({
    Title    = "Lock All Accessories",
    Callback = function()
        fire("LockAccessories")
        Fluent:Notify({ Title="Accessories", Content="Lock enviado", Duration=2 })
    end,
})

Tabs.Equipment:AddToggle("AutoDeleteAcc", { Title = "Auto Delete Accessories", Default = false })
Options.AutoDeleteAcc:OnChanged(function(v)
    fire("ToggleAutoAccessoryDelete", v)
end)

Tabs.Equipment:AddSection("Aura")

Tabs.Equipment:AddButton({
    Title    = "Equip Best Aura",
    Callback = function()
        fire("EquipBestAura")
        Fluent:Notify({ Title="Aura", Content="Best Aura equipada", Duration=2 })
    end,
})

Tabs.Equipment:AddButton({
    Title    = "Equip Best All",
    Callback = function()
        fire("EquipBestAll")
        Fluent:Notify({ Title="Equipment", Content="Best All equipado", Duration=2 })
    end,
})

Tabs.Equipment:AddButton({
    Title    = "Unequip All",
    Callback = function()
        fire("UnequipAll")
        Fluent:Notify({ Title="Equipment", Content="Unequip All enviado", Duration=2 })
    end,
})

-- ============================================================
-- TAB: GACHA
-- ============================================================
Tabs.Gacha:AddSection("Auto Roll")

Tabs.Gacha:AddToggle("AutoRollGacha", { Title = "Auto Roll Gacha", Default = false })
Options.AutoRollGacha:OnChanged(function(v)
    if v then
        fire("AutoRollGacha", true)
    else
        fire("AutoRollGacha", false)
    end
end)

Tabs.Gacha:AddButton({
    Title    = "Equip Best Gacha",
    Callback = function()
        fire("EquipeBestGachas")
        Fluent:Notify({ Title="Gacha", Content="Best Gacha equipado", Duration=2 })
    end,
})

Tabs.Gacha:AddSection("Obelisk")

Tabs.Gacha:AddButton({
    Title    = "Activate Obelisk",
    Callback = function()
        fire("Active0belisk")
        Fluent:Notify({ Title="Obelisk", Content="Ativado", Duration=2 })
    end,
})

-- ============================================================
-- TAB: AVATAR
-- ============================================================
Tabs.Avatar:AddSection("Avatar Level")

Tabs.Avatar:AddButton({
    Title    = "Max Avatar Level",
    Callback = function()
        fire("MaxAvatarLevel")
        Fluent:Notify({ Title="Avatar", Content="Max Level enviado", Duration=2 })
    end,
})

Tabs.Avatar:AddToggle("AutoAvatarLevel", { Title = "Auto Avatar Level", Default = false })
Options.AutoAvatarLevel:OnChanged(function(v)
    if v then
        fire("AutoAvatarLevel", true)
    else
        fire("AutoAvatarLevel", false)
    end
end)

Tabs.Avatar:AddButton({
    Title    = "Upgrade Avatar Level",
    Callback = function()
        fire("UpgradeAvatarLevel")
        Fluent:Notify({ Title="Avatar", Content="Upgrade enviado", Duration=2 })
    end,
})

Tabs.Avatar:AddButton({
    Title    = "Craft Avatar",
    Callback = function()
        fire("CraftAvatar")
        Fluent:Notify({ Title="Avatar", Content="Craft enviado", Duration=2 })
    end,
})

-- ============================================================
-- TAB: WORLD — Teleport, Raids, Trials
-- ============================================================
Tabs.World:AddSection("Teleport")

Tabs.World:AddInput("TeleportDest", {
    Title       = "Destino",
    Placeholder = "Nome do mundo...",
})

Tabs.World:AddButton({
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

Tabs.World:AddButton({
    Title    = "Favorite Current World",
    Callback = function()
        fire("FavorityWorld")
        Fluent:Notify({ Title="World", Content="World favoritado", Duration=2 })
    end,
})

Tabs.World:AddSection("Raids & Trials")

Tabs.World:AddButton({
    Title    = "Enter Raid",
    Callback = function()
        fire("EnterRaid")
        Fluent:Notify({ Title="Raid", Content="Enter Raid enviado", Duration=2 })
    end,
})

Tabs.World:AddButton({
    Title    = "Enter Trial",
    Callback = function()
        fire("EnterTrial")
        Fluent:Notify({ Title="Trial", Content="Enter Trial enviado", Duration=2 })
    end,
})

Tabs.World:AddButton({
    Title    = "Exit Gamemode",
    Callback = function()
        fire("ExitGamemode")
        Fluent:Notify({ Title="Gamemode", Content="Exit enviado", Duration=2 })
    end,
})

Tabs.World:AddButton({
    Title    = "Recall to Room",
    Callback = function()
        fire("RecallToRoom")
        Fluent:Notify({ Title="Room", Content="Recall enviado", Duration=2 })
    end,
})

Tabs.World:AddSection("Time Chamber")

Tabs.World:AddButton({
    Title    = "Quit Time Chamber",
    Callback = function()
        fire("QuitTimeChamber")
        Fluent:Notify({ Title="Time Chamber", Content="Quit enviado", Duration=2 })
    end,
})

Tabs.World:AddButton({
    Title    = "Return Time Chamber",
    Callback = function()
        fire("ReturnTimeChamber")
        Fluent:Notify({ Title="Time Chamber", Content="Return enviado", Duration=2 })
    end,
})

Tabs.World:AddSection("Verify & Codes")

Tabs.World:AddButton({
    Title    = "Verify Group",
    Callback = function()
        fire("VerifyPlayerInGroup")
        Fluent:Notify({ Title="Verify", Content="Group verify enviado", Duration=2 })
    end,
})

Tabs.World:AddButton({
    Title    = "Favorite Game",
    Callback = function()
        fire("VerifyPlayerFavorityGame")
        Fluent:Notify({ Title="Verify", Content="Favorite enviado", Duration=2 })
    end,
})

Tabs.World:AddButton({
    Title    = "Like Game",
    Callback = function()
        fire("VerifyPlayerLikedGame")
        Fluent:Notify({ Title="Verify", Content="Like enviado", Duration=2 })
    end,
})

Tabs.World:AddInput("ClaimCodeInput", {
    Title       = "Code",
    Placeholder = "Digite o código...",
})

Tabs.World:AddButton({
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
Tabs.Info:AddSection("Anime Capture v1.1")
Tabs.Info:AddParagraph({ Title="Dev",     Content="Danonin"                })
Tabs.Info:AddParagraph({ Title="Discord", Content="discord.gg/qDeZ9sEdGY" })
Tabs.Info:AddButton({
    Title    = "Copiar Discord",
    Callback = function()
        setclipboard("https://discord.gg/qDeZ9sEdGY")
        Fluent:Notify({ Title="Copiado!", Content="discord.gg/qDeZ9sEdGY", Duration=2 })
    end,
})
Tabs.Info:AddParagraph({
    Title   = "Keybind",
    Content = "RightControl — Toggle GUI\nBotao — Toggle/Arrastar",
})

-- ============================================================
-- INIT
-- ============================================================
SaveManager:LoadAutoloadConfig()
Window:SelectTab(Tabs.Farm)
Fluent:Notify({ Title="Anime Capture v1.1", Content="Carregado!", Duration=4 })
warn("[AC] Anime Capture v1.1 | RemotesFolder: "..#RF:GetChildren().." remotes")
