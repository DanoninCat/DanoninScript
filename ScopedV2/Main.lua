local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local LocalPlayer = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G

if not game:IsLoaded() then
    game.Loaded:Wait()
end

if LocalPlayer then
    LocalPlayer:WaitForChild("PlayerGui", 20)
end

local fluentSource = env["__CE_F_91A7"]
if type(fluentSource) ~= "string" or fluentSource == "" then
    error("[CAT_EMPIRE][Scoped] Fluent source missing")
end

local Fluent = loadstring(fluentSource)()

local previous = env.__CAT_EMPIRE_SCOPED_UI
if previous and previous.Window then
    pcall(function()
        previous.Window:Destroy()
    end)
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

local combat = Tabs.Combat:AddSection("Scoped Runtime", "solar/target-bold")
combat:AddParagraph({
    Title = "Loader OK",
    Content = "CAT EMPIRE carregado no Scoped. Place ID: " .. tostring(game.PlaceId),
})
combat:AddParagraph({
    Title = "Second Dump",
    Content = "Runtime preparado para a arquitetura do segundo dump (Scripts_114689356953798).",
})

local visuals = Tabs.Visuals:AddSection("Visuals", "solar/eye-bold")
visuals:AddParagraph({
    Title = "Interface",
    Content = "Layout no mesmo padrão do Murder Duels: Crimson, tabs separadas e Settings FluentPro.",
})

local function shortJobId()
    local id = tostring(game.JobId or "")
    if id == "" then return "N/A" end
    return #id > 18 and (string.sub(id,1,18) .. "...") or id
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

local misc = Tabs.Misc:AddSection("Servidor Atual", "solar/server-square-bold")
misc:AddParagraph({
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
    Title = LocalPlayer and LocalPlayer.DisplayName or "Player",
    Content = LocalPlayer and string.format(
        "Nickname: @%s\nUser ID: %d\nConta: %d dias",
        LocalPlayer.Name,
        LocalPlayer.UserId,
        LocalPlayer.AccountAge
    ) or "LocalPlayer indisponível",
})

local community = Tabs.Misc:AddSection("Comunidade", "solar/chat-round-bold")
community:AddDiscord({InviteCode = "yykVnTjd2Y"})

local listSection = Tabs.Players:AddSection("Players List", "solar/users-group-rounded-bold")
for _, player in ipairs(Players:GetPlayers()) do
    listSection:AddParagraph({
        Title = player.DisplayName or player.Name,
        Content = "@" .. player.Name,
    })
end

local developer = Tabs.Settings:AddSection("Developer", "solar/code-bold")
developer:AddParagraph({Title = "Dev", Content = "Danonin"})
developer:AddParagraph({
    Title = "Scoped Loader",
    Content = "Build UI diagnostic\nPlace: " .. tostring(game.PlaceId),
})

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
    Version = "UI-DIAG-1",
    PlaceId = game.PlaceId,
}

return env.__CAT_EMPIRE_SCOPED_UI
