local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local LocalPlayer = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G

local fluentSource = env["__CE_F_91A7"]
if type(fluentSource) ~= "string" or fluentSource == "" then
    error("[CAT_EMPIRE] Fluent source missing")
end

local Fluent = loadstring(fluentSource)()

local previous = env.__CAT_EMPIRE_SCOPED_UI
if previous and previous.Window then
    pcall(function()
        previous.Window:Destroy()
    end)
end

local function getSetting(name)
    local folder = LocalPlayer and LocalPlayer:FindFirstChild("Setting")
    return folder and folder:FindFirstChild(name)
end

local function readSetting(name, fallback)
    local object = getSetting(name)
    if object and object:IsA("ValueBase") then
        return object.Value
    end
    return fallback
end

local function writeSetting(name, value)
    local object = getSetting(name)
    if object and object:IsA("ValueBase") then
        pcall(function()
            object.Value = value
        end)
    end
end

local Window = Fluent:CreateWindow({
    Title = "CAT EMPIRE",
    SubTitle = "Scoped",
    TabWidth = 140,
    Size = UDim2.fromOffset(760, 460),
    Acrylic = true,
    Animated = true,
    Theme = "Crimson",
    MinimizeKey = Enum.KeyCode.LeftControl,
    ScreenGuiName = "CAT_EMPIRE_SCOPED",
})

local Tabs = {
    Combat = Window:AddTab({Title = "Combat", Icon = "solar/target-bold"}),
    Visuals = Window:AddTab({Title = "Visuals", Icon = "solar/eye-bold"}),
    Misc = Window:AddTab({Title = "Misc", Icon = "solar/widget-4-bold"}),
    Players = Window:AddTab({Title = "Players", Icon = "solar/users-group-rounded-bold"}),
    Settings = Window:AddTab({Title = "Settings", Icon = "solar/settings-bold"}),
}

local aimSection = Tabs.Combat:AddSection("Aim", "solar/target-bold")

aimSection:AddToggle("ScopedAimAssist", {
    Title = "Aim Assist",
    Default = LocalPlayer:GetAttribute("AimAssistEnabled") == true,
    Callback = function(value)
        pcall(function()
            LocalPlayer:SetAttribute("AimAssistEnabled", value == true)
        end)
    end,
})

aimSection:AddToggle("ScopedAutoScope", {
    Title = "Auto Scope",
    Default = LocalPlayer:GetAttribute("AutoScopeEnabled") == true,
    Callback = function(value)
        pcall(function()
            LocalPlayer:SetAttribute("AutoScopeEnabled", value == true)
        end)
    end,
})

local cameraSection = Tabs.Combat:AddSection("Camera", "solar/radar-2-bold")

cameraSection:AddSlider("ScopedDefaultFov", {
    Title = "Default FOV",
    Min = 40,
    Max = 120,
    Default = tonumber(readSetting("DefaultFov", 70)) or 70,
    Rounding = 0,
    Callback = function(value)
        writeSetting("DefaultFov", tonumber(value) or 70)
    end,
})

cameraSection:AddSlider("ScopedScopedFov", {
    Title = "Scoped FOV",
    Min = 10,
    Max = 90,
    Default = tonumber(readSetting("ScopedFov", 40)) or 40,
    Rounding = 0,
    Callback = function(value)
        writeSetting("ScopedFov", tonumber(value) or 40)
    end,
})

local performance = Tabs.Visuals:AddSection("Performance", "solar/bolt-bold")

performance:AddToggle("ScopedOptimizedShadow", {
    Title = "Optimized Shadow",
    Default = readSetting("Optimized Shadow", false) == true,
    Callback = function(value)
        writeSetting("Optimized Shadow", value == true)
    end,
})

performance:AddToggle("ScopedRemoveTextures", {
    Title = "Remove Textures",
    Default = readSetting("Remove Textures", false) == true,
    Callback = function(value)
        writeSetting("Remove Textures", value == true)
    end,
})

performance:AddToggle("ScopedOptimizedRagdoll", {
    Title = "Optimized Ragdoll",
    Default = readSetting("Optimized Ragdoll", false) == true,
    Callback = function(value)
        writeSetting("Optimized Ragdoll", value == true)
    end,
})

performance:AddToggle("ScopedOptimizedEffects", {
    Title = "Optimized Effects",
    Default = readSetting("Optimized Effects", false) == true,
    Callback = function(value)
        writeSetting("Optimized Effects", value == true)
    end,
})

local function shortJobId()
    local id = tostring(game.JobId or "")
    if id == "" then return "N/A" end
    return #id > 18 and (string.sub(id, 1, 18) .. "...") or id
end

local function resolveGameName()
    local name = "Scoped"
    pcall(function()
        local info = MarketplaceService:GetProductInfo(game.PlaceId)
        if info and type(info.Name) == "string" and info.Name ~= "" then
            name = info.Name
        end
    end)
    return name
end

local server = Tabs.Misc:AddSection("Servidor Atual", "solar/server-square-bold")
server:AddParagraph({
    Title = resolveGameName(),
    Content = string.format(
        "Jogadores: %d/%d\nPlace ID: %s\nServer ID: %s",
        #Players:GetPlayers(),
        tonumber(Players.MaxPlayers) or 0,
        tostring(game.PlaceId),
        shortJobId()
    ),
})

local account = Tabs.Misc:AddSection("Sua Conta", "solar/user-bold")
account:AddParagraph({
    Title = LocalPlayer.DisplayName,
    Content = string.format(
        "Nickname: @%s\nUser ID: %d\nConta: %d dias",
        LocalPlayer.Name,
        LocalPlayer.UserId,
        LocalPlayer.AccountAge
    ),
})

local community = Tabs.Misc:AddSection("Comunidade", "solar/chat-round-bold")
community:AddDiscord({InviteCode = "yykVnTjd2Y"})

local players = Tabs.Players:AddSection("Players List", "solar/users-group-rounded-bold")
for _, player in ipairs(Players:GetPlayers()) do
    players:AddParagraph({
        Title = player.DisplayName or player.Name,
        Content = "@" .. player.Name,
    })
end

if Fluent.InterfaceManager and Fluent.SaveManager then
    Fluent.InterfaceManager:SetLibrary(Fluent)
    Fluent.InterfaceManager:SetFolder("CAT_EMPIRE/Scoped")
    Fluent.SaveManager:SetLibrary(Fluent)
    Fluent.SaveManager:SetFolder("CAT_EMPIRE/Scoped")

    if Fluent.FloatingButtonManager then
        Fluent.FloatingButtonManager:SetLibrary(Fluent)
        Fluent.FloatingButtonManager:SetFolder("CAT_EMPIRE/Scoped/FloatingButtons")
    end

    Fluent.InterfaceManager.Settings.Theme = "Crimson"
    Fluent.InterfaceManager.Settings.Animated = true
    Fluent.InterfaceManager.Settings.Transparency = true
    Fluent.InterfaceManager.Settings.MenuKeybind = "LeftControl"
    Fluent.InterfaceManager.Settings.Font = "GothamSSm"

    Fluent.InterfaceManager:BuildInterfaceSection(Tabs.Settings)
    Fluent.SaveManager:BuildConfigSection(Tabs.Settings)

    if Fluent.FloatingButtonManager then
        Fluent.FloatingButtonManager:BuildConfigSection(Tabs.Settings)
    end
end

local unload = Tabs.Settings:AddSection("CAT EMPIRE", "solar/power-bold")
unload:AddButton({
    Title = "Unload CAT EMPIRE",
    Icon = "solar/power-bold",
    Callback = function()
        pcall(function()
            Window:Destroy()
        end)
        env.__CAT_EMPIRE_SCOPED_UI = nil
    end,
})

pcall(function()
    Window:SelectTab(1)
end)

env.__CAT_EMPIRE_SCOPED_UI = {
    Window = Window,
    Fluent = Fluent,
    Version = "2.0.0",
    PlaceId = game.PlaceId,
}

return env.__CAT_EMPIRE_SCOPED_UI
