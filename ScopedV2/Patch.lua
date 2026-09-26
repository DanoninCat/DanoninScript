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
    error("[CAT_EMPIRE UI Patch] Could not replace ESP preview")
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
    local previewModel, previewCamera = CreateESPPreview()
    local espPreviewViewport = previewSection:AddViewport({
        Object = previewModel,
        Camera = previewCamera,
        Height = 300,
        AspectRatio = "16:9",
        Interactive = true,
        Focused = true,
    })

    RefreshESPPreview = function()
        if not espPreviewViewport then
            return
        end
        local newModel = CreateESPPreview()
        if newModel then
            espPreviewViewport:SetObject(newModel)
            espPreviewViewport:Focus()
        end
    end

    table.insert(Connections, LocalPlayer.CharacterAdded:Connect(function()
        task.delay(0.5, function()
            if RefreshESPPreview then
                RefreshESPPreview()
            end
        end)
    end))]],
    "real avatar ESP preview"
)

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
    local skinChoices, skinIds = BuildSkinChoices()

    local skinPreviewSection = Tabs.Skins:AddSection("Preview 3D", "solar/cube-bold")

    local selectedSkinId = tostring(LocalPlayer:GetAttribute("UseGunSkin") or "")
    if selectedSkinId == "" then
        selectedSkinId = nil
    end

    local weaponPreviewModel, weaponPreviewCamera = CreateWeaponPreview(selectedSkinId)
    local skinViewport = skinPreviewSection:AddViewport({
        Object = weaponPreviewModel,
        Camera = weaponPreviewCamera,
        Height = 300,
        AspectRatio = "16:9",
        Interactive = true,
        Focused = true,
    })

    local function refreshSkinPreview()
        if not skinViewport then
            return
        end

        local newModel = CreateWeaponPreview(selectedSkinId)
        if newModel then
            skinViewport:SetObject(newModel)
            skinViewport:Focus()
        end
    end

    skinControlSection:AddParagraph({
        Title = "Arma Atual",
        Content = tostring(LocalPlayer:GetAttribute("UseGun") or "N/A"),
    })

    skinControlSection:AddDropdown("ScopedGunSkin", {
        Title = "Gun Skin",
        Values = skinChoices,
        Default = "Default",
        DropdownOutsideWindow = true,
        Callback = function(value)
            if value == "Default" then
                selectedSkinId = nil
                RefreshLocalWeaponSkin(nil)
            else
                selectedSkinId = skinIds[value]
                RefreshLocalWeaponSkin(selectedSkinId)
            end

            -- Preview is built directly from Assets.ViewModel + SkinLoader,
            -- so it can update immediately without waiting for Hand.lua.
            task.defer(refreshSkinPreview)
        end,
    })

    table.insert(Connections, LocalPlayer:GetAttributeChangedSignal("UseGunSkin"):Connect(function()
        local value = tostring(LocalPlayer:GetAttribute("UseGunSkin") or "")
        selectedSkinId = value ~= "" and value or nil
        task.defer(refreshSkinPreview)
    end))

    table.insert(Connections, LocalPlayer:GetAttributeChangedSignal("WeaponId"):Connect(function()
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

if not string.find(source, "AddRobloxProfileCard(accountSection)", 1, true) then
    error("[CAT_EMPIRE UI Patch] Roblox profile card missing")
end

if not string.find(source, "local skinViewport = skinPreviewSection:AddViewport", 1, true) then
    error("[CAT_EMPIRE UI Patch] Skin viewport missing")
end

return loadstring(source)()
