from pathlib import Path
import base64, gzip, subprocess, hashlib

parts = sorted(Path('.github/reference').glob('fluent_reference.part*.b64'))
assert len(parts) == 8, f'expected 8 reference parts, got {len(parts)}'
encoded = ''.join(p.read_text(encoding='utf-8').strip() for p in parts)
reference = gzip.decompress(base64.b64decode(encoded)).decode('utf-8')
Path('Libs/Fluent.lua').write_text(reference, encoding='utf-8')
blob = subprocess.check_output(['git','hash-object','Libs/Fluent.lua'], text=True).strip()
assert blob == 'baf6fb51b076e48e34e3c0bb2309ee7fdce509ab', f'exact reference blob mismatch: {blob}'

path = Path('Games/MurderDuel.lua')
game = path.read_text(encoding='utf-8')
start = game.index('local function CreateUI()')
end = game.index('local function SetupConnections()', start)
pre = game[:start]
post = game[end:]
pre_hash = hashlib.sha256(pre.encode()).hexdigest()
post_hash = hashlib.sha256(post.encode()).hexdigest()

create_ui = r'''local function CreateUI()
    local Window = Fluent:CreateWindow({
        Title = "CAT EMPIRE",
        SubTitle = "Murder Duel",
        TabWidth = 140,
        Size = UDim2.fromOffset(760, 460),
        Acrylic = true,
        Animated = true,
        Theme = "Crimson",
        MinimizeKey = Enum.KeyCode.LeftControl,
        ScreenGuiName = "CAT_EMPIRE",
    })

    WindowRef = Window

    local Tabs = {
        Combat = Window:AddTab({Title = "Combat", Icon = "solar/target-bold"}),
        Visuals = Window:AddTab({Title = "Visuals", Icon = "solar/eye-bold"}),
        Misc = Window:AddTab({Title = "Misc", Icon = "solar/widget-4-bold"}),
        Players = Window:AddTab({Title = "Players", Icon = "solar/users-group-rounded-bold"}),
        Settings = Window:AddTab({Title = "Settings", Icon = "solar/settings-bold"}),
    }

    local aimbotSection = Tabs.Combat:AddSection("Aimbot", "solar/target-bold")
    aimbotSection:AddToggle("AimbotEnabled", {
        Title = "Aimbot",
        Default = false,
        Callback = function(value)
            State.Aim.Enabled = value
            RefreshCombatTracking()
        end,
    })

    local combatFilterSection = Tabs.Combat:AddSection("Target Filters", "solar/filter-bold")
    combatFilterSection:AddToggle("CombatTeamCheck", {
        Title = "Team Check",
        Default = false,
        Callback = function(value)
            State.Filters.TeamCheck = value
            local other = Fluent.Options.TeamCheck
            if other and other.Value ~= value then
                other:SetValue(value)
            end
        end,
    })

    local espSection = Tabs.Visuals:AddSection("Players ESP", "solar/users-group-rounded-bold")
    espSection:AddSlider("ESPRenderDistance", {
        Title = "Rendering Distance",
        Min = 25,
        Max = 1000,
        Default = 500,
        Rounding = 0,
        Callback = function(value)
            State.ESP.RenderingDistance = value
            UpdateESP()
        end,
    })

    local function bindESPToggle(id, title, stateKey)
        espSection:AddToggle(id, {
            Title = title,
            Default = false,
            Callback = function(value)
                State.ESP[stateKey] = value
                RefreshESPEnabled()
                UpdateESP()
            end,
        })
    end

    bindESPToggle("ESPBox", "Box", "Box")
    bindESPToggle("ESPSkeleton", "Skeleton", "Skeleton")
    bindESPToggle("ESPName", "Name", "Name")
    bindESPToggle("ESPDistance", "Distance", "Distance")
    bindESPToggle("ESPLines", "Lines", "Lines")

    espSection:AddToggle("TeamCheck", {
        Title = "Team Check",
        Default = false,
        Callback = function(value)
            State.Filters.TeamCheck = value
            local other = Fluent.Options.CombatTeamCheck
            if other and other.Value ~= value then
                other:SetValue(value)
            end
            UpdateESP()
        end,
    })

    local colorPresets = {
        White = Color3.fromRGB(245, 245, 247),
        Red = Color3.fromRGB(235, 65, 75),
        Blue = Color3.fromRGB(35, 125, 255),
        Purple = Color3.fromRGB(118, 78, 255),
        Pink = Color3.fromRGB(255, 65, 150),
    }
    local colorNames = {"White", "Red", "Blue", "Purple", "Pink"}
    local colorsSection = Tabs.Visuals:AddSection("ESP Colors", "solar/palette-bold")

    local function bindESPColor(id, title, key, default)
        colorsSection:AddDropdown(id, {
            Title = title,
            Values = colorNames,
            Default = default,
            DropdownOutsideWindow = true,
            Callback = function(value)
                ESP_COLORS[key] = colorPresets[value] or colorPresets.Purple
                UpdateESP()
            end,
        })
    end

    bindESPColor("BoxColor", "Box", "Box", "Purple")
    bindESPColor("SkeletonColor", "Skeleton", "Skeleton", "Purple")
    bindESPColor("LineColor", "Lines", "Lines", "Purple")
    bindESPColor("NameColor", "Name", "Name", "White")
    bindESPColor("DistanceColor", "Distance", "Distance", "White")

    local fovSection = Tabs.Visuals:AddSection("FOV", "solar/radar-2-bold")
    fovSection:AddToggle("FOVCircle", {
        Title = "Draw FOV",
        Default = false,
        Callback = function(value)
            State.Visual.FOVCircle = value
            UpdateFOVCircle()
        end,
    })
    fovSection:AddSlider("FOVRadius", {
        Title = "FOV Radius",
        Min = 30,
        Max = 500,
        Default = 200,
        Rounding = 0,
        Callback = function(value)
            SetSharedFOV(value)
        end,
    })

    local function resolveGameName()
        local gameName = "Murder Duel"
        pcall(function()
            local info = MarketplaceService:GetProductInfo(game.PlaceId)
            if info and type(info.Name) == "string" and info.Name ~= "" then
                gameName = info.Name
            end
        end)
        return gameName
    end

    local function shortJobId()
        local id = tostring(game.JobId or "")
        if id == "" then
            return "N/A"
        end
        return #id > 18 and (string.sub(id, 1, 18) .. "...") or id
    end

    local serverSection = Tabs.Misc:AddSection("Servidor Atual", "solar/server-square-bold")
    serverSection:AddImage({
        Image = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150",
        AspectRatio = "4:1",
        Radius = 10,
    })
    local serverInfo = serverSection:AddParagraph({
        Title = resolveGameName(),
        Content = string.format(
            "Jogadores: %d/%d\nPlace ID: %s\nServer ID: %s",
            #Players:GetPlayers(),
            tonumber(Players.MaxPlayers) or 0,
            tostring(game.PlaceId),
            shortJobId()
        ),
    })

    local accountSection = Tabs.Misc:AddSection("Sua Conta", "solar/user-bold")
    accountSection:AddImage({
        Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150",
        AspectRatio = "4:1",
        Radius = 10,
    })
    accountSection:AddParagraph({
        Title = LocalPlayer.DisplayName,
        Content = string.format(
            "Display Name: %s\nNickname: @%s\nUser ID: %d\nConta: %d dias",
            LocalPlayer.DisplayName,
            LocalPlayer.Name,
            LocalPlayer.UserId,
            LocalPlayer.AccountAge
        ),
    })

    local communitySection = Tabs.Misc:AddSection("Comunidade", "solar/chat-round-bold")
    communitySection:AddDiscord({InviteCode = "yykVnTjd2Y"})
    communitySection:AddParagraph({
        Title = "Discord",
        Content = "https://discord.gg/yykVnTjd2Y",
    })
    communitySection:AddButton({
        Title = "Copiar Discord",
        Icon = "solar/copy-bold",
        Callback = function()
            local env = (getgenv and getgenv()) or _G
            local clipboard = (env and env.setclipboard) or rawget(_G, "setclipboard")
            if type(clipboard) == "function" then
                pcall(clipboard, "https://discord.gg/yykVnTjd2Y")
                Fluent:Notify({Title = "CAT EMPIRE", Content = "Link do Discord copiado.", Duration = 2})
            else
                Fluent:Notify({Title = "CAT EMPIRE", Content = "Clipboard indisponível.", Duration = 3})
            end
        end,
    })

    local listSection = Tabs.Players:AddSection("Players List", "solar/users-group-rounded-bold")
    local playerRows = {}
    for index = 1, 8 do
        playerRows[index] = listSection:AddParagraph({Title = "-", Content = ""})
    end

    local informationSection = Tabs.Players:AddSection("Information", "solar/info-circle-bold")
    local nearestName = informationSection:AddParagraph({Title = "Name: --", Content = ""})
    local nearestDistance = informationSection:AddParagraph({Title = "Distance: --", Content = ""})

    local developerSection = Tabs.Settings:AddSection("Developer", "solar/code-bold")
    developerSection:AddParagraph({Title = "Dev", Content = "Danonin"})

    Fluent.InterfaceManager:SetLibrary(Fluent)
    Fluent.InterfaceManager:SetFolder("CAT_EMPIRE")
    Fluent.SaveManager:SetLibrary(Fluent)
    Fluent.SaveManager:SetFolder("CAT_EMPIRE")
    Fluent.FloatingButtonManager:SetLibrary(Fluent)
    Fluent.FloatingButtonManager:SetFolder("CAT_EMPIRE/FloatingButtons")

    Fluent.InterfaceManager.Settings.Theme = "Crimson"
    Fluent.InterfaceManager.Settings.Animated = true
    Fluent.InterfaceManager.Settings.Transparency = true
    Fluent.InterfaceManager.Settings.MenuKeybind = "LeftControl"
    Fluent.InterfaceManager.Settings.Font = "GothamSSm"

    Fluent.InterfaceManager:BuildInterfaceSection(Tabs.Settings)
    Fluent.SaveManager:BuildConfigSection(Tabs.Settings)
    Fluent.FloatingButtonManager:BuildConfigSection(Tabs.Settings)

    local unloadSection = Tabs.Settings:AddSection("CAT EMPIRE", "solar/power-bold")
    unloadSection:AddButton({
        Title = "Unload CAT EMPIRE",
        Icon = "solar/power-bold",
        Callback = function()
            Cleanup()
        end,
    })

    task.spawn(function()
        while not UIClosed do
            task.wait(0.5)

            if serverInfo and serverInfo.SetDesc then
                serverInfo:SetDesc(string.format(
                    "Jogadores: %d/%d\nPlace ID: %s\nServer ID: %s",
                    #Players:GetPlayers(),
                    tonumber(Players.MaxPlayers) or 0,
                    tostring(game.PlaceId),
                    shortJobId()
                ))
            end

            local localRoot = GetTargetPart(LocalPlayer.Character)
            local rows = {}
            if localRoot then
                for _, player in ipairs(Players:GetPlayers()) do
                    if player ~= LocalPlayer and player.Character then
                        local root = GetTargetPart(player.Character)
                        local humanoid = GetHumanoid(player.Character)
                        if root and humanoid and humanoid.Health > 0 then
                            table.insert(rows, {
                                Player = player,
                                Distance = GetDistance(localRoot.Position, root.Position),
                            })
                        end
                    end
                end
            end

            table.sort(rows, function(a, b)
                return a.Distance < b.Distance
            end)

            for index = 1, #playerRows do
                local row = rows[index]
                local value = row
                    and string.format("%s  [%d]", row.Player.DisplayName or row.Player.Name, math.floor(row.Distance + 0.5))
                    or "-"
                if playerRows[index] and playerRows[index].SetTitle then
                    playerRows[index]:SetTitle(value)
                end
            end

            local nearest = rows[1]
            if nearest then
                nearestName:SetTitle("Name: " .. (nearest.Player.DisplayName or nearest.Player.Name))
                nearestDistance:SetTitle("Distance: " .. tostring(math.floor(nearest.Distance + 0.5)))
            else
                nearestName:SetTitle("Name: --")
                nearestDistance:SetTitle("Distance: --")
            end
        end
    end)
end

'''

new_game = pre + create_ui + post
assert hashlib.sha256(new_game[:new_game.index('local function CreateUI()')].encode()).hexdigest() == pre_hash
assert hashlib.sha256(new_game[new_game.index('local function SetupConnections()'):].encode()).hexdigest() == post_hash
path.write_text(new_game, encoding='utf-8')

checks = [
    'Title = "CAT EMPIRE"', 'SubTitle = "Murder Duel"', 'Theme = "Crimson"',
    'MinimizeKey = Enum.KeyCode.LeftControl', 'Combat = Window:AddTab',
    'Visuals = Window:AddTab', 'Misc = Window:AddTab', 'Players = Window:AddTab',
    'Settings = Window:AddTab', 'Fluent.InterfaceManager:BuildInterfaceSection',
    'Fluent.SaveManager:BuildConfigSection', 'Fluent.FloatingButtonManager:BuildConfigSection',
    'InviteCode = "yykVnTjd2Y"', 'Default = false', 'FOV Radius',
]
for token in checks:
    assert token in new_game, token
assert 'Silent Aim' not in new_game
assert 'Aim Assist' not in new_game
assert 'Diagnóstico' not in new_game
assert 'Aim FOV' not in new_game
assert 'Camera FOV' not in new_game
assert 'AddGroup(' not in create_ui
assert 'AddSelect(' not in create_ui
assert 'Enum.KeyCode.Unknown' not in create_ui
assert 'WindowRef:Destroy()' in new_game
assert 'State.Aim.Enabled = value' in create_ui
assert 'RefreshCombatTracking()' in create_ui
assert 'SetSharedFOV(value)' in create_ui
assert 'State.Visual.FOVCircle = value' in create_ui

subprocess.run(['git','diff','--check'], check=True)
print('exact fluent blob:', blob)
print('murder duel blob:', subprocess.check_output(['git','hash-object','Games/MurderDuel.lua'], text=True).strip())
