from pathlib import Path

fluent_path = Path('Libs/Fluent.lua')
game_path = Path('Games/MurderDuel.lua')

fluent = fluent_path.read_text(encoding='utf-8')
game = game_path.read_text(encoding='utf-8')

# 1) Dropdowns: clicking the same selector toggles it closed, and opening
#    another selector first closes every other open dropdown through its
#    own Close() method so arrow/shine/scroll state stays synchronized.
old_click = '''            c.AddSignal(
                p.MouseButton1Click,
                function()
                    l:Open()
                end
            )'''
new_click = '''            c.AddSignal(
                p.MouseButton1Click,
                function()
                    if l.Opened then
                        l:Close()
                    else
                        l:Open()
                    end
                end
            )'''
click_count = fluent.count(old_click)
assert click_count >= 1, f'dropdown click handler not found: {click_count}'
fluent = fluent.replace(old_click, new_click)

old_open = '''            function l.Open(B)
                l.Opened = true
'''
new_open = '''            function l.Open(B)
                if l.Opened then
                    return
                end
                local _closeQueue = {}
                for state in next, _openDropdowns do
                    if state ~= l then
                        table.insert(_closeQueue, state)
                    end
                end
                for _, state in ipairs(_closeQueue) do
                    if state and state.Close then
                        pcall(function()
                            state:Close()
                        end)
                    end
                end
                l.Opened = true
'''
open_count = fluent.count(old_open)
assert open_count >= 1, f'dropdown open handler not found: {open_count}'
fluent = fluent.replace(old_open, new_open)

# 2) Robust game/avatar image resolution.
insert_anchor = '''    local function shortJobId()
'''
assert insert_anchor in game, 'shortJobId anchor not found'
helpers = '''    local function resolveGameIcon()
        local fallback = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150"
        local resolved = fallback
        pcall(function()
            local info = MarketplaceService:GetProductInfo(game.PlaceId)
            local iconId = info and tonumber(info.IconImageAssetId)
            if iconId and iconId > 0 then
                resolved = "rbxassetid://" .. tostring(iconId)
            end
        end)
        return resolved
    end

    local function resolveAvatarThumbnail()
        local fallback = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150"
        local resolved = fallback
        pcall(function()
            local content = Players:GetUserThumbnailAsync(
                LocalPlayer.UserId,
                Enum.ThumbnailType.HeadShot,
                Enum.ThumbnailSize.Size150x150
            )
            if type(content) == "string" and content ~= "" then
                resolved = content
            end
        end)
        return resolved
    end

'''
game = game.replace(insert_anchor, helpers + insert_anchor, 1)

game_icon_old = 'Image = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150",'
avatar_old = 'Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150",'
assert game_icon_old in game, 'game icon expression not found'
assert avatar_old in game, 'avatar expression not found'
game = game.replace(game_icon_old, 'Image = resolveGameIcon(),', 1)
game = game.replace(avatar_old, 'Image = resolveAvatarThumbnail(),', 1)

# 3) Persistent CE button outside the main window, usable with touch/mouse.
window_anchor = '''    WindowRef = Window

    local Tabs = {
'''
assert window_anchor in game, 'WindowRef/Tabs anchor not found'
mobile_button = '''    WindowRef = Window

    DestroyNamedGui("CAT_EMPIRE_MobileToggle")
    local mobileToggleGui = Instance.new("ScreenGui")
    mobileToggleGui.Name = "CAT_EMPIRE_MobileToggle"
    mobileToggleGui.ResetOnSpawn = false
    mobileToggleGui.IgnoreGuiInset = true
    mobileToggleGui.DisplayOrder = 1000000
    mobileToggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    mobileToggleGui.Parent = GetPlayerGui()

    local mobileToggle = Instance.new("TextButton")
    mobileToggle.Name = "CE"
    mobileToggle.AnchorPoint = Vector2.new(0, 0.5)
    mobileToggle.Position = UDim2.new(0, 14, 0.5, 0)
    mobileToggle.Size = UDim2.fromOffset(54, 54)
    mobileToggle.BackgroundColor3 = Color3.fromRGB(220, 30, 60)
    mobileToggle.BackgroundTransparency = 0.08
    mobileToggle.BorderSizePixel = 0
    mobileToggle.AutoButtonColor = true
    mobileToggle.Text = "CE"
    mobileToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    mobileToggle.TextSize = 15
    mobileToggle.Font = Enum.Font.GothamBold
    mobileToggle.ZIndex = 1000001
    mobileToggle.Parent = mobileToggleGui

    local mobileCorner = Instance.new("UICorner")
    mobileCorner.CornerRadius = UDim.new(0, 12)
    mobileCorner.Parent = mobileToggle

    local mobileStroke = Instance.new("UIStroke")
    mobileStroke.Color = Color3.fromRGB(255, 85, 110)
    mobileStroke.Transparency = 0.2
    mobileStroke.Thickness = 1
    mobileStroke.Parent = mobileToggle

    table.insert(Connections, mobileToggle.Activated:Connect(function()
        if UIClosed or not WindowRef then
            return
        end
        pcall(function()
            WindowRef:Minimize()
        end)
    end))

    local Tabs = {
'''
game = game.replace(window_anchor, mobile_button, 1)

cleanup_anchor = '''    safeStep("DestroyFOVGui", function() DestroyNamedGui("FOVCircle") end)
'''
assert cleanup_anchor in game, 'cleanup FOV anchor not found'
game = game.replace(
    cleanup_anchor,
    cleanup_anchor + '    safeStep("DestroyMobileToggle", function() DestroyNamedGui("CAT_EMPIRE_MobileToggle") end)\n',
    1,
)

# Static invariants for this patch.
assert 'if l.Opened then\n                        l:Close()' in fluent
assert 'for state in next, _openDropdowns do' in fluent
assert 'state:Close()' in fluent
assert 'resolveGameIcon()' in game
assert 'resolveAvatarThumbnail()' in game
assert 'Players:GetUserThumbnailAsync' in game
assert 'CAT_EMPIRE_MobileToggle' in game
assert 'mobileToggle.Activated:Connect' in game
assert 'WindowRef:Minimize()' in game
assert 'Silent Aim' not in game
assert 'Aim Assist' not in game
assert 'Aim FOV' not in game
assert 'Camera FOV' not in game

fluent_path.write_text(fluent, encoding='utf-8')
game_path.write_text(game, encoding='utf-8')
