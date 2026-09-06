from pathlib import Path
import hashlib
import re
import subprocess

FLUENT = Path("Libs/Fluent.lua")
GAME = Path("Games/MurderDuel.lua")

fluent = FLUENT.read_text(encoding="utf-8")
game = GAME.read_text(encoding="utf-8")


def blob(path: str) -> str:
    return subprocess.check_output(["git", "hash-object", path], text=True).strip()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    assert count == 1, f"{label}: expected 1 exact match, found {count}"
    return text.replace(old, new, 1)


def regex_once(text: str, pattern: str, repl: str, label: str) -> str:
    out, count = re.subn(pattern, repl, text, count=1, flags=re.S)
    assert count == 1, f"{label}: expected 1 regex match, found {count}"
    return out


# ============================================================
# PASS 1 — BASE / SCOPE
# ============================================================

assert blob("Libs/Fluent.lua") == "de211348b0393c4559723bf980a83b7315a6a9d1"
assert blob("Games/MurderDuel.lua") == "bacfa73b6e017030f66cfd9abb9ac0f62b452648"

CREATE_UI = "local function CreateUI()"
SETUP = "local function SetupConnections()"

pre_ui = game.split(CREATE_UI, 1)[0]
post_ui = SETUP + game.split(SETUP, 1)[1]
pre_hash = hashlib.sha256(pre_ui.encode()).hexdigest()
post_hash = hashlib.sha256(post_ui.encode()).hexdigest()

# ============================================================
# FLUENT — MATCH THE SUPPLIED UI VISUAL LANGUAGE
# ============================================================

old_palette = '''local C = {
    Background = Color3.fromRGB(8, 8, 12),
    Topbar = Color3.fromRGB(10, 9, 15),
    Sidebar = Color3.fromRGB(10, 9, 15),
    Content = Color3.fromRGB(10, 9, 15),
    Section = Color3.fromRGB(14, 12, 20),
    Row = Color3.fromRGB(16, 13, 22),
    RowHover = Color3.fromRGB(24, 18, 34),
    Border = Color3.fromRGB(50, 42, 72),
    BorderSoft = Color3.fromRGB(34, 28, 48),
    Accent = Color3.fromRGB(92, 72, 255),
    AccentDark = Color3.fromRGB(67, 54, 214),
    AccentSoft = Color3.fromRGB(126, 110, 255),
    Text = Color3.fromRGB(248, 245, 255),
    Muted = Color3.fromRGB(213, 207, 226),
    Muted2 = Color3.fromRGB(150, 143, 168),
    Knob = Color3.fromRGB(250, 248, 255),
}'''

new_palette = '''local C = {
    Background = Color3.fromRGB(30, 6, 9),
    Topbar = Color3.fromRGB(24, 5, 8),
    Sidebar = Color3.fromRGB(26, 6, 10),
    Content = Color3.fromRGB(30, 6, 9),
    Section = Color3.fromRGB(18, 8, 14),
    Row = Color3.fromRGB(14, 8, 14),
    RowHover = Color3.fromRGB(50, 12, 22),
    Border = Color3.fromRGB(100, 10, 25),
    BorderSoft = Color3.fromRGB(60, 8, 18),
    Accent = Color3.fromRGB(220, 30, 60),
    AccentDark = Color3.fromRGB(120, 15, 35),
    AccentSoft = Color3.fromRGB(235, 70, 95),
    Text = Color3.fromRGB(255, 235, 240),
    Muted = Color3.fromRGB(220, 185, 195),
    Muted2 = Color3.fromRGB(180, 100, 115),
    Knob = Color3.fromRGB(250, 248, 255),
}'''
fluent = replace_once(fluent, old_palette, new_palette, "reference palette")

fluent = replace_once(
    fluent,
    '''    -- Subtle tinted layer similar to the translucent reference UI.
    -- It intentionally uses the default accent-dark color directly so the
    -- existing panel-color selector can recolor it without special APIs.
    local glass = makeGlass(root, C.AccentDark, 0.86, 1)''',
    '''    local themeBackground = create("ImageLabel", {
        Name = "CAT_EMPIRE_ThemeBackground",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = "rbxassetid://74252111742950",
        ImageTransparency = 0.46,
        ScaleType = Enum.ScaleType.Crop,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 0,
    }, root)

    local glass = makeGlass(root, C.AccentDark, 0.82, 1)''',
    "reference background",
)

fluent = regex_once(
    fluent,
    r'''    local logoWrap = create\("Frame", \{.*?    local controlWrap = create\("Frame", \{''',
    '''    local titleBlock = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(16, 5),
        Size = UDim2.new(0.62, -16, 0, 34),
        ZIndex = 7,
    }, topbar)

    local titleLabel = text(titleBlock, config.Title or "CAT EMPIRE", 11, C.Text, Enum.Font.GothamMedium)
    titleLabel.Position = UDim2.fromOffset(0, 0)
    titleLabel.Size = UDim2.new(1, 0, 0, 17)
    titleLabel.ZIndex = 7

    local subtitleText = tostring(config.SubTitle or "")
    local subtitle = text(titleBlock, subtitleText, 8, C.Muted2, Enum.Font.Gotham)
    subtitle.Position = UDim2.fromOffset(0, 16)
    subtitle.Size = UDim2.new(1, 0, 0, 15)
    subtitle.Visible = subtitleText ~= ""
    subtitle.ZIndex = 7

    local controlWrap = create("Frame", {''',
    "reference title block",
)

fluent = replace_once(
    fluent,
    "        Size = UDim2.fromOffset(76, 30),",
    "        Size = UDim2.fromOffset(116, 30),",
    "control width",
)

fluent = replace_once(
    fluent,
    '''    corner(minimizeButton, 5)

    local closeButton = create("TextButton", {''',
    '''    corner(minimizeButton, 5)

    local maximizeButton = create("TextButton", {
        BackgroundColor3 = C.Row,
        BackgroundTransparency = 0.75,
        BorderSizePixel = 0,
        Text = "□",
        TextColor3 = C.Muted,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = false,
        Position = UDim2.fromOffset(40, 0),
        Size = UDim2.fromOffset(34, 28),
        ZIndex = 9,
    }, controlWrap)
    corner(maximizeButton, 5)

    local closeButton = create("TextButton", {''',
    "maximize button",
)

fluent = regex_once(
    fluent,
    r'''(    local closeButton = create\("TextButton", \{.*?        AutoButtonColor = false,\n)        Position = UDim2.fromOffset\(40, 0\),''',
    r'''\1        Position = UDim2.fromOffset(80, 0),''',
    "move close button",
)

fluent = regex_once(
    fluent,
    r'''    local menuLabel = text\(sidebarVisual, "MENU".*?    local sidebarList = create\("Frame", \{''',
    '''    local sidebarList = create("Frame", {''',
    "remove MENU caption",
)
fluent = replace_once(
    fluent,
    '''        Position = UDim2.fromOffset(8, 30),
        Size = UDim2.new(1, -8, 1, -38),''',
    '''        Position = UDim2.fromOffset(8, 8),
        Size = UDim2.new(1, -8, 1, -16),''',
    "sidebar alignment",
)

fluent = regex_once(
    fluent,
    r'''    local pageAccent = create\("Frame", \{.*?    local pageLabel = text\(pageHeader, titleValue, 20, C.Text, Enum.Font.GothamMedium\)\n    pageLabel.Position = UDim2.fromOffset\(14, 5\)\n    pageLabel.Size = UDim2.new\(1, -14, 0, 38\)''',
    '''    local pageIconFrame = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(2, 13),
        Size = UDim2.fromOffset(24, 24),
    }, pageHeader)
    local pageIconHolder = DrawSidebarIcon(pageIconFrame, iconValue)
    SetSidebarIconColor(pageIconHolder, C.Text)

    local pageLabel = text(pageHeader, titleValue, 20, C.Text, Enum.Font.GothamMedium)
    pageLabel.Position = UDim2.fromOffset(34, 5)
    pageLabel.Size = UDim2.new(1, -34, 0, 38)''',
    "page header icon",
)

fluent = replace_once(
    fluent,
    "        Size = UDim2.new(1, -90, 0, 44),",
    "        Size = UDim2.new(1, -130, 0, 44),",
    "drag clearance",
)

fluent = replace_once(
    fluent,
    '''        MinButton = minimizeButton,
        _connections = {},''',
    '''        MinButton = minimizeButton,
        MaxButton = maximizeButton,
        Maximized = false,
        RestorePosition = nil,
        RestoreSize = nil,
        _connections = {},''',
    "maximize state",
)
fluent = replace_once(
    fluent,
    '''        MaxButton = nil,
        MinButton = minimizeButton,''',
    '''        MaxButton = maximizeButton,
        MinButton = minimizeButton,''',
    "expose maximize button",
)

fluent = replace_once(
    fluent,
    '''    window:_connect(minimizeButton.MouseButton1Click, function()
        window:ToggleMinimize()
    end)

    window:_connect(closeButton.MouseButton1Click, function()''',
    '''    window:_connect(minimizeButton.MouseButton1Click, function()
        window:ToggleMinimize()
    end)

    window:_connect(maximizeButton.MouseButton1Click, function()
        if window.Maximized then
            window.Maximized = false
            if window.RestorePosition then root.Position = window.RestorePosition end
            if window.RestoreSize then root.Size = window.RestoreSize end
            maximizeButton.Text = "□"
        else
            window.Maximized = true
            window.RestorePosition = root.Position
            window.RestoreSize = root.Size
            local camera = workspace.CurrentCamera
            local vp = camera and camera.ViewportSize or Vector2.new(1280, 720)
            root.Position = UDim2.fromScale(0.5, 0.5)
            root.Size = UDim2.fromOffset(math.max(760, vp.X - 24), math.max(460, vp.Y - 24))
            maximizeButton.Text = "❐"
        end
    end)

    window:_connect(closeButton.MouseButton1Click, function()''',
    "maximize behavior",
)
fluent = replace_once(
    fluent,
    "    for _, btn in ipairs({externalToggle, minimizeButton, closeButton}) do",
    "    for _, btn in ipairs({externalToggle, minimizeButton, maximizeButton, closeButton}) do",
    "maximize hover",
)

# ============================================================
# MURDER DUEL — CORRECT BRANDING / SETTINGS NAMES
# ============================================================

game = replace_once(game, '        SubTitle = "",', '        SubTitle = "Murder Duel",', "window subtitle")

game = replace_once(
    game,
    '''    local panelAccentPresets = {
        Purple = Color3.fromRGB(92, 72, 255),
        Blue = Color3.fromRGB(45, 120, 255),
        Red = Color3.fromRGB(235, 65, 75),
        Pink = Color3.fromRGB(230, 70, 180),
        White = Color3.fromRGB(225, 225, 235),
    }''',
    '''    local panelAccentPresets = {
        Crimson = Color3.fromRGB(220, 30, 60),
        Purple = Color3.fromRGB(92, 72, 255),
        Blue = Color3.fromRGB(45, 120, 255),
        Pink = Color3.fromRGB(230, 70, 180),
        White = Color3.fromRGB(225, 225, 235),
    }''',
    "theme names",
)

game = replace_once(
    game,
    '''    local defaultAccent = Color3.fromRGB(92, 72, 255)
    local defaultAccentDark = Color3.fromRGB(67, 54, 214)
    local defaultAccentSoft = Color3.fromRGB(126, 110, 255)''',
    '''    local defaultAccent = Color3.fromRGB(220, 30, 60)
    local defaultAccentDark = Color3.fromRGB(120, 15, 35)
    local defaultAccentSoft = Color3.fromRGB(235, 70, 95)''',
    "default theme colors",
)

game = replace_once(
    game,
    "        local newAccent = panelAccentPresets[name] or panelAccentPresets.Purple",
    "        local newAccent = panelAccentPresets[name] or panelAccentPresets.Crimson",
    "theme fallback",
)

game = replace_once(
    game,
    '        Values = {"Purple", "Blue", "Red", "Pink", "White"},',
    '        Values = {"Crimson", "Purple", "Blue", "Pink", "White"},',
    "theme selector",
)

game = replace_once(
    game,
    '''    local function SetBaseTransparency(value)
        Window.Sidebar.BackgroundTransparency = value
        Window.Content.BackgroundTransparency = value
    end''',
    '''    local function SetBaseTransparency(value)
        local sidebar = Window.SidebarVisual or Window.Sidebar
        local content = Window.ContentVisual or Window.Content
        if sidebar then sidebar.BackgroundTransparency = value end
        if content then content.BackgroundTransparency = value end
    end''',
    "visible background surfaces",
)

FLUENT.write_text(fluent, encoding="utf-8")
GAME.write_text(game, encoding="utf-8")

# ============================================================
# PASS 2 — VISUAL / API INVARIANTS
# ============================================================

assert 'Text = "□"' in fluent
assert "maximizeButton.MouseButton1Click" in fluent
assert "CAT_EMPIRE_ThemeBackground" in fluent
assert "rbxassetid://74252111742950" in fluent
assert "local pageIconHolder = DrawSidebarIcon(pageIconFrame, iconValue)" in fluent
assert "input.UserInputType ~= Enum.UserInputType.Keyboard" in fluent
assert 'Title = "CAT EMPIRE"' in game
assert 'SubTitle = "Murder Duel"' in game
assert 'Content = "Danonin"' in game
assert "https://discord.gg/yykVnTjd2Y" in game
assert 'Values = {"Crimson", "Purple", "Blue", "Pink", "White"}' in game
assert "Window.SidebarVisual or Window.Sidebar" in game

for token in [
    'AddToggle("AimbotEnabled", {Title = "Aimbot", Default = false})',
    'AddToggle("ESPBox", {Title = "Box", Default = false})',
    'AddToggle("ESPSkeleton", {Title = "Skeleton", Default = false})',
    'AddToggle("ESPName", {Title = "Name", Default = false})',
    'AddToggle("ESPDistance", {Title = "Distance", Default = false})',
    'AddToggle("ESPLines", {Title = "Lines", Default = false})',
    'AddToggle("FOVCircle", {Title = "Draw FOV", Default = false})',
]:
    assert token in game, f"missing OFF default: {token}"

# ============================================================
# PASS 3 — RUNTIME / LIFECYCLE / SCOPE STATIC CHECKS
# ============================================================

assert hashlib.sha256(game.split(CREATE_UI, 1)[0].encode()).hexdigest() == pre_hash
assert hashlib.sha256((SETUP + game.split(SETUP, 1)[1]).encode()).hexdigest() == post_hash
assert "Silent Aim" not in game
assert "Aim Assist" not in game
assert "Diagnóstico" not in game and "Diagnostico" not in game
assert "Camera FOV" not in game and "Aim FOV" not in game
assert "local FOVStroke = nil" in game
assert 'data.BoxStroke = Instance.new("UIStroke")' in game
assert "local function GetESPHeadTopScreen" in game
assert "CAT_EMPIRE_sidebar_logo_v12.jpg" in fluent
assert "CAT_EMPIRE_sidebar_icon_v13_" in fluent

changed = set(subprocess.check_output(["git", "diff", "--name-only"], text=True).splitlines())
assert changed == {"Libs/Fluent.lua", "Games/MurderDuel.lua"}, changed

print("PASS 1: base/scope OK")
print("PASS 2: visual/API invariants OK")
print("PASS 3: runtime/lifecycle invariants OK")
