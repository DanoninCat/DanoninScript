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

local helpersBootstrap = [[local UIHelpers = nil
task.spawn(function()
    local ok, library = pcall(function()
        return loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/ScopedV2/UIHelpers.lua",
            true
        ))()
    end)
    if ok and type(library) == "table" then
        UIHelpers = library
    end
end)
]]

replaceOnce(
    'local ReplicatedStorage = game:GetService("ReplicatedStorage")\n',
    'local ReplicatedStorage = game:GetService("ReplicatedStorage")\n\n' .. helpersBootstrap,
    "UIHelpers bootstrap"
)

replaceOnce(
[[pcall(function()
    local utils = ReplicatedStorage:FindFirstChild("Utils")
    local module = utils and utils:FindFirstChild("CameraController")
    if module and module:IsA("ModuleScript") then
        CameraController = require(module)
    end
end)]],
[[task.spawn(function()
    pcall(function()
        local utils = ReplicatedStorage:FindFirstChild("Utils")
        local module = utils and utils:FindFirstChild("CameraController")
        if module and module:IsA("ModuleScript") then
            CameraController = require(module)
        end
    end)
end)]],
    "async CameraController"
)

replaceOnce(
[[pcall(function()
    local guiUtils = ReplicatedStorage:FindFirstChild("GuiUtils")
    local module = guiUtils and guiUtils:FindFirstChild("FireRay")
    if module and module:IsA("ModuleScript") then
        FireRay = require(module)
    end
end)]],
[[task.spawn(function()
    pcall(function()
        local guiUtils = ReplicatedStorage:FindFirstChild("GuiUtils")
        local module = guiUtils and guiUtils:FindFirstChild("FireRay")
        if module and module:IsA("ModuleScript") then
            FireRay = require(module)
        end
    end)
end)]],
    "async FireRay"
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
    if not UIHelpers or type(UIHelpers.CreateESPPreview) ~= "function" then
        return nil
    end
    return UIHelpers.CreateESPPreview(LocalPlayer, ESP_COLORS)
end

local function CreateWeaponPreview(skinId, kind)
    if not UIHelpers or type(UIHelpers.CreateWeaponPreview) ~= "function" then
        return nil
    end
    return UIHelpers.CreateWeaponPreview(
        LocalPlayer,
        ReplicatedStorage,
        skinId,
        0.001,
        kind
    )
end

local function CreatePreviewPlaceholder(kind)
    local model = Instance.new("Model")
    model.Name = "CAT_EMPIRE_" .. tostring(kind or "Preview") .. "_Loading"

    local core = Instance.new("Part")
    core.Name = "Loading"
    core.Size = (kind == "Gun" or kind == "Knife")
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

    if kind == "Gun" or kind == "Knife" then
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
    local parent = section and section.Container
    if not parent then return nil end

    section._elementCount = (section._elementCount or 0) + 1

    local frame = Instance.new("Frame")
    frame.Name = "RobloxProfileCard"
    frame.Size = UDim2.new(1, 0, 0, 64)
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 29)
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    frame.LayoutOrder = section._elementCount
    frame.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local avatar = Instance.new("ImageLabel")
    avatar.Size = UDim2.fromOffset(44, 44)
    avatar.Position = UDim2.new(0, 10, 0.5, 0)
    avatar.AnchorPoint = Vector2.new(0, 0.5)
    avatar.BackgroundTransparency = 1
    avatar.Image = "rbxthumb://type=AvatarHeadShot&id="
        .. tostring(LocalPlayer.UserId)
        .. "&w=150&h=150"
    avatar.Parent = frame

    local avatarCorner = Instance.new("UICorner")
    avatarCorner.CornerRadius = UDim.new(1, 0)
    avatarCorner.Parent = avatar

    local displayName = Instance.new("TextLabel")
    displayName.BackgroundTransparency = 1
    displayName.Position = UDim2.new(0, 64, 0, 12)
    displayName.Size = UDim2.new(1, -74, 0, 18)
    displayName.Font = Enum.Font.GothamSemibold
    displayName.TextSize = 13
    displayName.TextXAlignment = Enum.TextXAlignment.Left
    displayName.TextColor3 = Color3.fromRGB(245, 245, 247)
    displayName.Text = LocalPlayer.DisplayName
    displayName.Parent = frame

    local username = Instance.new("TextLabel")
    username.BackgroundTransparency = 1
    username.Position = UDim2.new(0, 64, 0, 33)
    username.Size = UDim2.new(1, -74, 0, 16)
    username.Font = Enum.Font.Gotham
    username.TextSize = 11
    username.TextXAlignment = Enum.TextXAlignment.Left
    username.TextColor3 = Color3.fromRGB(170, 170, 180)
    username.Text = "@" .. LocalPlayer.Name
    username.Parent = frame

    return frame
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
        Height = 200,
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

replaceOnce(
[[local function BuildSkinChoices()
    local currentGun = tostring(LocalPlayer:GetAttribute("UseGun") or "")
    local choices = {"Default"}
    local ids = {}

    local function collect(config)
        for skinId, info in pairs(config or {}) do
            if type(info) == "table" and tostring(info.WeaponId or "") == currentGun then
                local label = string.format(
                    "%s | %s | %s",
                    tostring(skinId),
                    tostring(info.Name or skinId),
                    tostring(info.Rarity or "")
                )
                ids[label] = skinId
                table.insert(choices, label)
            end
        end
    end

    collect(SkinConfig)
    collect(SkinMutation)

    table.sort(choices, function(a, b)
        if a == "Default" then return true end
        if b == "Default" then return false end
        return a < b
    end)

    return choices, ids
end]],
[[local function BuildSkinChoices(weaponId)
    weaponId = tostring(weaponId or "")
    local choices = {"Default"}
    local ids = {}

    if next(SkinConfig) == nil and next(SkinMutation) == nil then
        pcall(function()
            local helper = ReplicatedStorage:FindFirstChild("Config")
            helper = helper and helper:FindFirstChild("SkinHelper")
            local config = helper and helper:FindFirstChild("SkinConfig")
            local mutation = helper and helper:FindFirstChild("SkinMutation")
            if config and config:IsA("ModuleScript") then
                SkinConfig = require(config)
            end
            if mutation and mutation:IsA("ModuleScript") then
                SkinMutation = require(mutation)
            end
        end)
    end

    local function collect(config)
        for skinId, info in pairs(config or {}) do
            if type(info) == "table" and tostring(info.WeaponId or "") == weaponId then
                local label = string.format(
                    "%s | %s | %s",
                    tostring(skinId),
                    tostring(info.Name or skinId),
                    tostring(info.Rarity or "")
                )
                ids[label] = skinId
                table.insert(choices, label)
            end
        end
    end

    collect(SkinConfig)
    collect(SkinMutation)

    table.sort(choices, function(a, b)
        if a == "Default" then return true end
        if b == "Default" then return false end
        return a < b
    end)

    return choices, ids
end]],
    "parameterized skin catalog"
)

replaceOnce(
[[local function RefreshLocalWeaponSkin(skinId)
    if skinId then
        LocalPlayer:SetAttribute("UseGunSkin", skinId)
        LocalPlayer:SetAttribute("UseGunSkinWear", 0.001)
    else
        LocalPlayer:SetAttribute("UseGunSkin", "")
    end

    local currentWeapon = LocalPlayer:GetAttribute("WeaponId")
    if not currentWeapon or currentWeapon == "" then
        return
    end

    -- Hand.lua rebuilds the first-person weapon whenever WeaponId changes.
    LocalPlayer:SetAttribute("WeaponId", "")
    task.delay(0.06, function()
        if LocalPlayer and LocalPlayer.Parent then
            LocalPlayer:SetAttribute("WeaponId", currentWeapon)
        end
    end)
end]],
[[local function RefreshLocalWeaponSkin(skinId)
    if skinId then
        LocalPlayer:SetAttribute("UseGunSkin", skinId)
        LocalPlayer:SetAttribute("UseGunSkinWear", 0.001)
    else
        LocalPlayer:SetAttribute("UseGunSkin", "")
    end

    local currentWeapon = tostring(LocalPlayer:GetAttribute("WeaponId") or "")
    local currentGun = tostring(LocalPlayer:GetAttribute("UseGun") or "")

    if currentWeapon ~= "" and currentWeapon == currentGun then
        LocalPlayer:SetAttribute("WeaponId", "")
        task.delay(0.06, function()
            if LocalPlayer and LocalPlayer.Parent then
                LocalPlayer:SetAttribute("WeaponId", currentWeapon)
            end
        end)
    end
end

local function RefreshLocalMeleeSkin(skinId)
    if skinId then
        LocalPlayer:SetAttribute("UseMeleeSkin", skinId)
        LocalPlayer:SetAttribute("UseMeleeSkinWear", 0.001)
    else
        LocalPlayer:SetAttribute("UseMeleeSkin", "")
    end

    local currentWeapon = tostring(LocalPlayer:GetAttribute("WeaponId") or "")
    local currentMelee = tostring(LocalPlayer:GetAttribute("UseMelee") or "")

    if currentWeapon ~= "" and currentWeapon == currentMelee then
        LocalPlayer:SetAttribute("WeaponId", "")
        task.delay(0.06, function()
            if LocalPlayer and LocalPlayer.Parent then
                LocalPlayer:SetAttribute("WeaponId", currentWeapon)
            end
        end)
    end
end]],
    "gun and melee refresh"
)

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

    local function makeSkinPanel(kind)
        local isMelee = kind == "melee"
        local sectionTitle = isMelee and "Faca / Melee" or "Arma / Gun"
        local skinAttr = isMelee and "UseMeleeSkin" or "UseGunSkin"
        local weaponAttr = isMelee and "UseMelee" or "UseGun"
        local dropdownId = isMelee and "ScopedMeleeSkin" or "ScopedGunSkin"
        local dropdownTitle = isMelee and "Knife Skin" or "Gun Skin"
        local placeholderKind = isMelee and "Knife" or "Gun"

        local controlSection = Tabs.Skins:AddSection(sectionTitle, "solar/palette-bold")
        local weaponParagraph = controlSection:AddParagraph({
            Title = "Equipado",
            Content = tostring(LocalPlayer:GetAttribute(weaponAttr) or "N/A"),
        })

        local selectedSkinId = tostring(LocalPlayer:GetAttribute(skinAttr) or "")
        if selectedSkinId == "" then selectedSkinId = nil end

        local skinIds = {}
        local catalogGeneration = 0
        local previewGeneration = 0

        local skinDropdown
        skinDropdown = controlSection:AddDropdown(dropdownId, {
            Title = dropdownTitle,
            Values = {"Carregando..."},
            Default = "Carregando...",
            DropdownOutsideWindow = true,
            Callback = function(value)
                if not value or value == "Carregando..." then
                    return
                end

                if value == "Default" then
                    selectedSkinId = nil
                    if isMelee then
                        RefreshLocalMeleeSkin(nil)
                    else
                        RefreshLocalWeaponSkin(nil)
                    end
                else
                    selectedSkinId = skinIds[value]
                    if selectedSkinId then
                        if isMelee then
                            RefreshLocalMeleeSkin(selectedSkinId)
                        else
                            RefreshLocalWeaponSkin(selectedSkinId)
                        end
                    end
                end
            end,
        })

        local previewSection = Tabs.Skins:AddSection(
            isMelee and "Preview 3D - Faca" or "Preview 3D - Arma",
            "solar/cube-bold"
        )

        local previewModel, previewCamera = CreatePreviewPlaceholder(placeholderKind)
        local viewport = previewSection:AddViewport({
            Object = previewModel,
            Camera = previewCamera,
            Height = 190,
            AspectRatio = "16:9",
            Interactive = true,
            Focused = false,
        })

        local function refreshPreview()
            previewGeneration = previewGeneration + 1
            local generation = previewGeneration
            local skinAtRequest = selectedSkinId

            task.spawn(function()
                for attempt = 1, 15 do
                    if attempt > 1 then task.wait(0.18) end
                    if generation ~= previewGeneration or UIClosed then return end

                    local ok, newModel, newCamera = pcall(
                        CreateWeaponPreview,
                        skinAtRequest,
                        kind
                    )

                    if generation ~= previewGeneration or UIClosed then
                        if ok and newModel then
                            pcall(function() newModel:Destroy() end)
                        end
                        return
                    end

                    if ok and newModel and viewport then
                        viewport:SetObject(newModel)
                        if newCamera then viewport:SetCamera(newCamera) end

                        if newModel.Name ~= "WeaponPreviewUnavailable" then
                            return
                        end
                    end
                end
            end)
        end

        local function rebuildCatalog()
            catalogGeneration = catalogGeneration + 1
            local generation = catalogGeneration
            local weaponId = tostring(LocalPlayer:GetAttribute(weaponAttr) or "")

            selectedSkinId = tostring(LocalPlayer:GetAttribute(skinAttr) or "")
            if selectedSkinId == "" then selectedSkinId = nil end

            if weaponParagraph and weaponParagraph.SetDesc then
                weaponParagraph:SetDesc(weaponId ~= "" and weaponId or "N/A")
            end

            if skinDropdown and skinDropdown.SetValues then
                skinDropdown:SetValues({"Carregando..."})
            end

            task.spawn(function()
                local ok, choices, ids = pcall(BuildSkinChoices, weaponId)

                if generation ~= catalogGeneration or UIClosed then
                    return
                end

                choices = ok and choices or {"Default"}
                skinIds = ok and ids or {}

                if skinDropdown and skinDropdown.SetValues then
                    skinDropdown:SetValues(choices)
                    skinDropdown:SetValue("Default")
                end

                refreshPreview()
            end)
        end

        table.insert(Connections, LocalPlayer:GetAttributeChangedSignal(skinAttr):Connect(function()
            local value = tostring(LocalPlayer:GetAttribute(skinAttr) or "")
            selectedSkinId = value ~= "" and value or nil
            task.defer(refreshPreview)
        end))

        table.insert(Connections, LocalPlayer:GetAttributeChangedSignal(weaponAttr):Connect(function()
            task.defer(rebuildCatalog)
        end))

        task.defer(rebuildCatalog)
    end

    makeSkinPanel("gun")
    makeSkinPanel("melee")

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
