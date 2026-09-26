local BASE = "https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/ScopedV2/"
local source = game:HttpGet(BASE .. "Main.lua", true)

local function replaceOnce(old, new, label)
    local startPos, endPos = string.find(source, old, 1, true)
    if not startPos then
        error("[CAT_EMPIRE UI Patch] Missing anchor: " .. tostring(label))
    end

    source = string.sub(source, 1, startPos - 1)
        .. new
        .. string.sub(source, endPos + 1)
end

local helpersBootstrap = [[local UIHelpers = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/ScopedV2/UIHelpers.lua",
    true
))()
]]

replaceOnce(
    'local ReplicatedStorage = game:GetService("ReplicatedStorage")\n',
    'local ReplicatedStorage = game:GetService("ReplicatedStorage")\n\n' .. helpersBootstrap,
    "UIHelpers bootstrap"
)

replaceOnce(
[[    aimbotSection:AddToggle("SilentAimEnabled", {
        Title = "Silent Aim",
        Description = "Redirects shots to the closest valid target inside the FOV without moving the camera.",
        Default = false,]],
[[    aimbotSection:AddToggle("SilentAimEnabled", {
        Title = "Silent Aim",
        Default = false,]],
    "Silent Aim description"
)

local genericPreviewPattern =
    "local function CreateESPPreview%(%)"
    .. ".-\nend\n\nlocal function BuildSkinChoices"

local previewReplacement = [[local function CreateESPPreview()
    return UIHelpers.CreateESPPreview(LocalPlayer, ESP_COLORS)
end

local function CreateWeaponPreview(skinId)
    return UIHelpers.CreateWeaponPreview(
        LocalPlayer,
        ReplicatedStorage,
        skinId,
        0.001
    )
end

local function CreatePreviewPlaceholder(kind)
    local model = Instance.new("Model")
    model.Name = "CAT_EMPIRE_" .. tostring(kind or "Preview") .. "_Loading"

    local core = Instance.new("Part")
    core.Name = "Loading"
    core.Size = kind == "Skin"
        and Vector3.new(4.5, 0.7, 0.7)
        or Vector3.new(2, 4.5, 1)
    core.Anchored = true
    core.CanCollide = false
    core.CanTouch = false
    core.CanQuery = false
    core.Material = Enum.Material.SmoothPlastic
    core.Color = Color3.fromRGB(55, 55, 65)
    core.Parent = model

    local camera = Instance.new("Camera")
    camera.FieldOfView = 30

    if kind == "Skin" then
        camera.CFrame = CFrame.lookAt(
            Vector3.new(7, 2.2, 9),
            Vector3.new(0, 0, 0)
        )
    else
        camera.CFrame = CFrame.lookAt(
            Vector3.new(7, 3.5, 10),
            Vector3.new(0, 1.2, 0)
        )
    end

    return model, camera
end

local function AddRobloxProfileCard(section)
    return UIHelpers.AddRobloxProfileCard(section, LocalPlayer, Players)
end

local function BuildSkinChoices]]

local replacedPreview
source, replacedPreview = string.gsub(
    source,
    genericPreviewPattern,
    previewReplacement,
    1
)
if replacedPreview ~= 1 then
    error("[CAT_EMPIRE UI Patch] Could not replace preview helpers")
end

replaceOnce(
[[    local Tabs = {
        Combat = Window:AddTab({Title = "Combat", Icon = "solar/target-bold"}),
        Visuals = Window:AddTab({Title = "Visuals", Icon = "solar/eye-bold"}),
        Misc = Window:AddTab({Title = "Misc", Icon = "solar/widget-4-bold"}),
        Players = Window:AddTab({Title = "Players", Icon = "solar/users-group-rounded-bold"}),
        Settings = Window:AddTab({Title = "Settings", Icon = "solar/settings-bold"}),
    }]],
[[    local Tabs = {
        Combat = Window:AddTab({Title = "Combat", Icon = "solar/target-bold"}),
        Visuals = Window:AddTab({Title = "Visuals", Icon = "solar/eye-bold"}),
        Skins = Window:AddTab({Title = "Skins", Icon = "solar/palette-bold"}),
        Misc = Window:AddTab({Title = "Misc", Icon = "solar/widget-4-bold"}),
        Players = Window:AddTab({Title = "Players", Icon = "solar/users-group-rounded-bold"}),
        Settings = Window:AddTab({Title = "Settings", Icon = "solar/settings-bold"}),
    }]],
    "Skins tab"
)

replaceOnce(
[[    local colorPresets = {]],
[[    local RefreshESPPreview = nil
    local colorPresets = {]],
    "preview refresh declaration"
)

replaceOnce(
[[                ESP_COLORS[key] = colorPresets[value] or colorPresets.Purple
                UpdateESP()]],
[[                ESP_COLORS[key] = colorPresets[value] or colorPresets.Purple
                UpdateESP()
                if RefreshESPPreview then
                    RefreshESPPreview()
                end]],
    "preview color refresh"
)

replaceOnce(
[[    local previewSection = Tabs.Visuals:AddSection("ESP Preview 3D", "solar/cube-bold")
    local previewModel, previewCamera = CreateESPPreview()
    previewSection:AddViewport({
        Object = previewModel,
        Camera = previewCamera,
        Height = 260,
        AspectRatio = "16:9",
        Interactive = true,
        Focused = false,
    })]],
[[    local previewSection = Tabs.Visuals:AddSection("ESP Preview 3D", "solar/cube-bold")
    local previewModel, previewCamera = CreatePreviewPlaceholder("ESP")
    local espPreviewViewport = previewSection:AddViewport({
        Object = previewModel,
        Camera = previewCamera,
        Height = 300,
        AspectRatio = "16:9",
        Interactive = true,
        Focused = false,
    })

    local espPreviewGeneration = 0

    RefreshESPPreview = function()
        espPreviewGeneration = espPreviewGeneration + 1
        local generation = espPreviewGeneration

        task.spawn(function()
            for attempt = 1, 3 do
                if attempt > 1 then
                    task.wait(0.25)
                end

                if generation ~= espPreviewGeneration or UIClosed then
                    return
                end

                local ok, newModel, newCamera = pcall(CreateESPPreview)

                if generation ~= espPreviewGeneration or UIClosed then
                    if ok and newModel then
                        pcall(function() newModel:Destroy() end)
                    end
                    return
                end

                if ok and newModel and espPreviewViewport then
                    espPreviewViewport:SetObject(newModel)
                    if newCamera then
                        espPreviewViewport:SetCamera(newCamera)
                    end

                    if newModel.Name ~= "ESPPreviewFallback" then
                        return
                    end
                end
            end
        end)
    end

    task.defer(RefreshESPPreview)

    table.insert(Connections, LocalPlayer.CharacterAdded:Connect(function()
        task.delay(0.35, function()
            if RefreshESPPreview then
                RefreshESPPreview()
            end
        end)
    end))]],
    "lazy ESP preview"
)

local gameNamePattern =
    "    local function resolveGameName%(%)"
    .. ".-\n    end\n\n    local function resolveGameIcon%(%)"
    .. ".-\n    end"

local gameInfoReplacement = [[    local function resolveGameName()
        return "Scoped"
    end

    local function resolveGameIcon()
        return "rbxthumb://type=GameIcon&id="
            .. tostring(game.GameId)
            .. "&w=150&h=150"
    end]]

local gameInfoCount
source, gameInfoCount = string.gsub(
    source,
    gameNamePattern,
    gameInfoReplacement,
    1
)
if gameInfoCount ~= 1 then
    error("[CAT_EMPIRE UI Patch] Could not make game info nonblocking")
end

local avatarPattern =
    "    local function resolveAvatarThumbnail%(%)"
    .. ".-\n    end\n\n    local function shortJobId"

local avatarCount
source, avatarCount = string.gsub(
    source,
    avatarPattern,
    "    local function shortJobId",
    1
)
if avatarCount ~= 1 then
    error("[CAT_EMPIRE UI Patch] Could not remove old avatar resolver")
end

local accountStart = string.find(
    source,
    '    local accountSection = Tabs.Misc:AddSection("Sua Conta", "solar/user-bold")',
    1,
    true
)
local communityStart = string.find(
    source,
    '    local communitySection = Tabs.Misc:AddSection("Comunidade", "solar/chat-round-bold")',
    accountStart or 1,
    true
)

if not accountStart or not communityStart then
    error("[CAT_EMPIRE UI Patch] Could not locate Misc account/skin block")
end

local replacementBlock = [[    local accountSection = Tabs.Misc:AddSection("Sua Conta", "solar/user-bold")
    AddRobloxProfileCard(accountSection)
    accountSection:AddParagraph({
        Title = "Conta",
        Content = string.format(
            "User ID: %d  •  %d dias",
            LocalPlayer.UserId,
            LocalPlayer.AccountAge
        ),
    })

    local skinControlSection = Tabs.Skins:AddSection("Skin Changer", "solar/palette-bold")

    local selectedSkinId = tostring(LocalPlayer:GetAttribute("UseGunSkin") or "")
    if selectedSkinId == "" then
        selectedSkinId = nil
    end

    local skinIds = {}

    local weaponParagraph = skinControlSection:AddParagraph({
        Title = "Arma Atual",
        Content = tostring(LocalPlayer:GetAttribute("UseGun") or "N/A"),
    })

    local skinDropdown
    skinDropdown = skinControlSection:AddDropdown("ScopedGunSkin", {
        Title = "Gun Skin",
        Values = {"Carregando..."},
        Default = "Carregando...",
        DropdownOutsideWindow = true,
        Callback = function(value)
            if value == nil or value == "Carregando..." then
                return
            end

            if value == "Default" then
                selectedSkinId = nil
                RefreshLocalWeaponSkin(nil)
            else
                selectedSkinId = skinIds[value]
                if selectedSkinId then
                    RefreshLocalWeaponSkin(selectedSkinId)
                end
            end
        end,
    })

    local skinPreviewSection = Tabs.Skins:AddSection("Preview 3D", "solar/cube-bold")
    local weaponPreviewModel, weaponPreviewCamera = CreatePreviewPlaceholder("Skin")
    local skinViewport = skinPreviewSection:AddViewport({
        Object = weaponPreviewModel,
        Camera = weaponPreviewCamera,
        Height = 300,
        AspectRatio = "16:9",
        Interactive = true,
        Focused = false,
    })

    local skinPreviewGeneration = 0

    local function refreshSkinPreview()
        skinPreviewGeneration = skinPreviewGeneration + 1
        local generation = skinPreviewGeneration
        local skinAtRequest = selectedSkinId

        task.spawn(function()
            local delays = {0, 0.12, 0.35, 0.8}

            for _, delayTime in ipairs(delays) do
                if delayTime > 0 then
                    task.wait(delayTime)
                end

                if generation ~= skinPreviewGeneration or UIClosed then
                    return
                end

                local ok, newModel, newCamera = pcall(
                    CreateWeaponPreview,
                    skinAtRequest
                )

                if generation ~= skinPreviewGeneration or UIClosed then
                    if ok and newModel then
                        pcall(function() newModel:Destroy() end)
                    end
                    return
                end

                if ok and newModel and skinViewport then
                    skinViewport:SetObject(newModel)
                    if newCamera then
                        skinViewport:SetCamera(newCamera)
                    end

                    if newModel.Name ~= "WeaponPreviewUnavailable" then
                        return
                    end
                end
            end
        end)
    end

    -- Build the catalog only after every tab/section has already been created.
    task.defer(function()
        local ok, choices, ids = pcall(BuildSkinChoices)

        if UIClosed or not ok then
            return
        end

        skinIds = ids or {}
        choices = choices or {"Default"}

        if skinDropdown and skinDropdown.SetValues then
            skinDropdown:SetValues(choices)
        end

        refreshSkinPreview()
    end)

    table.insert(Connections, LocalPlayer:GetAttributeChangedSignal("UseGunSkin"):Connect(function()
        local value = tostring(LocalPlayer:GetAttribute("UseGunSkin") or "")
        selectedSkinId = value ~= "" and value or nil
        task.defer(refreshSkinPreview)
    end))

    table.insert(Connections, LocalPlayer:GetAttributeChangedSignal("WeaponId"):Connect(function()
        task.defer(refreshSkinPreview)
    end))

    table.insert(Connections, LocalPlayer:GetAttributeChangedSignal("UseGun"):Connect(function()
        if weaponParagraph and weaponParagraph.SetDesc then
            weaponParagraph:SetDesc(tostring(LocalPlayer:GetAttribute("UseGun") or "N/A"))
        end
        task.defer(refreshSkinPreview)
    end))

]]

source = string.sub(source, 1, accountStart - 1)
    .. replacementBlock
    .. string.sub(source, communityStart)

if string.find(source, 'Description = "Redirects shots', 1, true) then
    error("[CAT_EMPIRE UI Patch] Silent Aim description still present")
end

if not string.find(source, 'Skins = Window:AddTab({Title = "Skins"', 1, true) then
    error("[CAT_EMPIRE UI Patch] Skins tab missing")
end

if not string.find(source, 'Values = {"Carregando..."}', 1, true) then
    error("[CAT_EMPIRE UI Patch] Lazy skin catalog missing")
end

if not string.find(source, 'CreatePreviewPlaceholder("Skin")', 1, true) then
    error("[CAT_EMPIRE UI Patch] Lazy skin viewport missing")
end

if not string.find(source, "task.defer(RefreshESPPreview)", 1, true) then
    error("[CAT_EMPIRE UI Patch] Lazy ESP preview missing")
end

return loadstring(source)()
