-- ============================================================
-- CAT EMPIRE UI
-- Reference-style translucent Roblox UI adapted for DanoninScript.
-- UI-only library: keeps the existing MurderDuel.lua API surface.
-- ============================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Library = {
    Options = {},
    Windows = {},
}

-- Keep these three accent values stable. MurderDuel.lua's existing
-- customization code recognizes them when recoloring the panel.
local C = {
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
}

local function create(className, props, parent)
    local obj = Instance.new(className)
    for key, value in pairs(props or {}) do
        obj[key] = value
    end
    if parent then
        obj.Parent = parent
    end
    return obj
end

local function corner(parent, radius)
    return create("UICorner", {
        CornerRadius = UDim.new(0, radius or 6),
    }, parent)
end

local function stroke(parent, color, transparency, thickness)
    return create("UIStroke", {
        Color = color or C.Border,
        Transparency = transparency == nil and 0.25 or transparency,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
end

local function padding(parent, left, right, top, bottom)
    return create("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or left or 0),
        PaddingTop = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or top or 0),
    }, parent)
end

local function list(parent, gap, horizontal)
    return create("UIListLayout", {
        FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, gap or 0),
    }, parent)
end

local function text(parent, value, size, color, font, xAlign)
    return create("TextLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = tostring(value or ""),
        TextColor3 = color or C.Text,
        TextSize = size or 11,
        Font = font or Enum.Font.Gotham,
        TextXAlignment = xAlign or Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, parent)
end

local function buttonBase(parent)
    return create("TextButton", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, parent)
end

local function tween(obj, props, time)
    local ok = pcall(function()
        TweenService:Create(
            obj,
            TweenInfo.new(time or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            props
        ):Play()
    end)

    if not ok then
        for key, value in pairs(props) do
            pcall(function()
                obj[key] = value
            end)
        end
    end
end

local function makeGlass(parent, color, transparency, zIndex)
    local frame = create("Frame", {
        BackgroundColor3 = color or C.Row,
        BackgroundTransparency = transparency or 0.35,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        ZIndex = zIndex or 1,
    }, parent)
    return frame
end

-- ============================================================
-- OPTIONS
-- ============================================================

local Option = {}
Option.__index = Option

function Option.new(id, value)
    local self = setmetatable({}, Option)
    self.Id = id
    self.Value = value
    self.Callbacks = {}
    self._render = nil
    Library.Options[id] = self
    return self
end

function Option:OnChanged(callback)
    if type(callback) == "function" then
        table.insert(self.Callbacks, callback)
        task.defer(function()
            local ok, err = pcall(callback, self.Value)
            if not ok then
                warn("[CAT EMPIRE UI] callback error:", err)
            end
        end)
    end
    return self
end

function Option:SetValue(value)
    if self.Value == value then
        if self._render then
            pcall(self._render, value)
        end
        return self
    end

    self.Value = value

    if self._render then
        local ok, err = pcall(self._render, value)
        if not ok then
            warn("[CAT EMPIRE UI] render error:", err)
        end
    end

    for _, callback in ipairs(self.Callbacks) do
        task.defer(function()
            local ok, err = pcall(callback, value)
            if not ok then
                warn("[CAT EMPIRE UI] callback error:", err)
            end
        end)
    end

    return self
end

-- ============================================================
-- WINDOW
-- ============================================================

local Window = {}
Window.__index = Window

local SetSidebarIconColor

function Window:_connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(self._connections, connection)
    return connection
end

function Window:_setMinimized(value)
    if self.Destroyed then
        return
    end
    self.Minimized = value == true
    self.Root.Visible = not self.Minimized
end

function Window:ToggleMinimize()
    self:_setMinimized(not self.Minimized)
end

function Window:SetScale(value)
    if self.Destroyed then
        return
    end
    value = math.clamp(tonumber(value) or 1, 0.50, 1.10)
    self.ScaleValue = value
    if self.UIScale then
        self.UIScale.Scale = value
    end
end

function Window:GetScale()
    return self.ScaleValue or 1
end

function Window:Destroy()
    if self.Destroyed then
        return
    end

    self.Destroyed = true

    local env = _G
    if type(getgenv) == "function" then
        local ok, resolved = pcall(getgenv)
        if ok and type(resolved) == "table" then
            env = resolved
        end
    end

    if env and type(env.CAT_EMPIRE_CLEANUP) == "function" then
        pcall(env.CAT_EMPIRE_CLEANUP)
    end

    for _, connection in ipairs(self._connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    self._connections = {}

    if self.Gui then
        pcall(function()
            self.Gui:Destroy()
        end)
    end
end

function Window:_selectTab(tab)
    if self.Destroyed then
        return
    end

    for _, candidate in ipairs(self.Tabs) do
        local active = candidate == tab

        if candidate.Page then
            candidate.Page.Visible = active
        end

        if candidate.Indicator then
            candidate.Indicator.Visible = active
        end

        if candidate.Button then
            candidate.Button.BackgroundTransparency = active and 0.58 or 1
            candidate.Button.BackgroundColor3 = active and C.AccentDark or C.Sidebar
        end

        if candidate.IconHolder then
            SetSidebarIconColor(candidate.IconHolder, active and C.Text or C.Muted)
        end

        if candidate.TitleLabel then
            candidate.TitleLabel.TextColor3 = active and C.Text or C.Muted
        end
    end

    self.ActiveTab = tab
end

local ICONS = {
    pc = "pc",
    eye = "eye",
    folder = "folder",
    players = "players",
    settings = "settings",
    paint = "paint",
}

local SIDEBAR_ICON_FILES = {
    pc = "combat.png",
    eye = "visuals.png",
    folder = "misc.png",
    settings = "settings.png",
}

local SidebarIconCache = {}

local function ResolveSidebarIcon(iconName)
    local remoteName = SIDEBAR_ICON_FILES[iconName]
    if not remoteName then
        return nil
    end

    if SidebarIconCache[iconName] ~= nil then
        return SidebarIconCache[iconName] or nil
    end

    local env = _G
    if type(getgenv) == "function" then
        local ok, resolved = pcall(getgenv)
        if ok and type(resolved) == "table" then
            env = resolved
        end
    end

    local assetFn =
        (env and (env.getcustomasset or env.getsynasset))
        or rawget(_G, "getcustomasset")
        or rawget(_G, "getsynasset")

    local writeFn = (env and env.writefile) or rawget(_G, "writefile")
    local isFileFn = (env and env.isfile) or rawget(_G, "isfile")

    if type(assetFn) ~= "function" or type(writeFn) ~= "function" then
        SidebarIconCache[iconName] = false
        return nil
    end

    local localName = "CAT_EMPIRE_sidebar_icon_v13_" .. remoteName
    local url =
        "https://raw.githubusercontent.com/"
        .. "DanoninCat/DanoninScript/main/Assets/SidebarIcons/"
        .. remoteName

    local ok = pcall(function()
        local exists = type(isFileFn) == "function" and isFileFn(localName)
        if not exists then
            writeFn(localName, game:HttpGet(url))
        end
    end)

    if not ok then
        SidebarIconCache[iconName] = false
        return nil
    end

    local okAsset, asset = pcall(assetFn, localName)
    if okAsset and asset then
        SidebarIconCache[iconName] = asset
        return asset
    end

    SidebarIconCache[iconName] = false
    return nil
end

local function DrawSidebarIcon(parent, iconName)
    local holder = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
    }, parent)

    local exactAsset = ResolveSidebarIcon(iconName)
    if exactAsset then
        create("ImageLabel", {
            Name = "ExactSidebarPNG",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = exactAsset,
            ImageColor3 = C.Muted,
            ScaleType = Enum.ScaleType.Fit,
            Size = UDim2.fromScale(1, 1),
        }, holder)
        return holder
    end

    local function line(pos, size, radius)
        local f = create("Frame", {
            BackgroundColor3 = C.Muted,
            BorderSizePixel = 0,
            Position = pos,
            Size = size,
        }, holder)
        if radius then
            corner(f, radius)
        end
        return f
    end

    if iconName == "pc" then
        local screen = create("Frame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(4, 6),
            Size = UDim2.fromOffset(18, 13),
        }, holder)
        stroke(screen, C.Muted, 0, 1)
        corner(screen, 2)
        line(UDim2.fromOffset(12, 20), UDim2.fromOffset(2, 4), 1)
        line(UDim2.fromOffset(8, 24), UDim2.fromOffset(10, 2), 1)
    elseif iconName == "eye" then
        local eye = create("Frame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(3, 8),
            Size = UDim2.fromOffset(20, 11),
        }, holder)
        corner(eye, 8)
        stroke(eye, C.Muted, 0, 1)
        local pupil = line(UDim2.fromOffset(11, 11), UDim2.fromOffset(5, 5), 3)
        pupil.BackgroundColor3 = C.Muted
    elseif iconName == "folder" then
        line(UDim2.fromOffset(4, 7), UDim2.fromOffset(9, 4), 2)
        line(UDim2.fromOffset(3, 10), UDim2.fromOffset(20, 12), 2)
    elseif iconName == "settings" then
        local gear = text(holder, "⚙", 18, C.Muted, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
        gear.Size = UDim2.fromScale(1, 1)
    elseif iconName == "players" then
        line(UDim2.fromOffset(10, 6), UDim2.fromOffset(7, 7), 4)
        line(UDim2.fromOffset(6, 15), UDim2.fromOffset(15, 8), 6)
    else
        line(UDim2.fromOffset(11, 11), UDim2.fromOffset(5, 5), 3)
    end

    return holder
end

SetSidebarIconColor = function(iconHolder, color)
    if not iconHolder then
        return
    end

    for _, obj in ipairs(iconHolder:GetDescendants()) do
        if obj:IsA("Frame") and obj.BackgroundTransparency < 1 then
            obj.BackgroundColor3 = color
        elseif obj:IsA("UIStroke") then
            obj.Color = color
        elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
            obj.ImageColor3 = color
        elseif obj:IsA("TextLabel") then
            obj.TextColor3 = color
        end
    end
end

-- ============================================================
-- CONTAINER API
-- ============================================================

local Container = {}
Container.__index = Container

function Container:_ensureSection()
    if self._currentSection then
        return self._currentSection
    end
    self:AddSection("")
    return self._currentSection
end

function Container:AddSection(titleValue)
    local section = create("Frame", {
        Name = "Section",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = self._nextOrder,
    }, self._scroll)

    self._nextOrder += 1

    list(section, 4, false)

    if titleValue and titleValue ~= "" then
        local titleWrap = create("Frame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 28),
            LayoutOrder = 0,
        }, section)

        local accentDot = create("Frame", {
            BackgroundColor3 = C.Accent,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(2, 10),
            Size = UDim2.fromOffset(5, 5),
        }, titleWrap)
        corner(accentDot, 3)

        local titleLabel = text(titleWrap, titleValue, 13, C.Text, Enum.Font.GothamMedium)
        titleLabel.Position = UDim2.fromOffset(13, 0)
        titleLabel.Size = UDim2.new(1, -13, 1, 0)
    end

    local holder = create("Frame", {
        Name = "Rows",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 1,
    }, section)

    list(holder, 5, false)

    self._currentSection = holder
    return section
end

local function makeRow(container, height)
    local holder = container:_ensureSection()

    local row = create("Frame", {
        BackgroundColor3 = C.Row,
        BackgroundTransparency = 0.48,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, height),
    }, holder)

    corner(row, 5)
    stroke(row, C.Border, 0.52, 1)

    return row
end

local function bindRowHover(window, row, hit)
    window:_connect(hit.MouseEnter, function()
        tween(row, {
            BackgroundColor3 = C.RowHover,
            BackgroundTransparency = 0.34,
        }, 0.08)
    end)

    window:_connect(hit.MouseLeave, function()
        tween(row, {
            BackgroundColor3 = C.Row,
            BackgroundTransparency = 0.48,
        }, 0.08)
    end)
end

function Container:AddToggle(id, config)
    config = config or {}

    local row = makeRow(self, 40)

    local titleLabel = text(row, config.Title or id, 11, C.Text, Enum.Font.Gotham)
    titleLabel.Position = UDim2.fromOffset(10, 0)
    titleLabel.Size = UDim2.new(1, -66, 1, 0)

    local switch = create("Frame", {
        BackgroundColor3 = Color3.fromRGB(35, 30, 45),
        BorderSizePixel = 0,
        Position = UDim2.new(1, -48, 0.5, -9),
        Size = UDim2.fromOffset(38, 18),
    }, row)
    corner(switch, 9)
    stroke(switch, C.Border, 0.48, 1)

    local knob = create("Frame", {
        BackgroundColor3 = C.Knob,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(3, 3),
        Size = UDim2.fromOffset(12, 12),
    }, switch)
    corner(knob, 6)

    local hit = buttonBase(row)
    hit.Size = UDim2.fromScale(1, 1)
    hit.ZIndex = 5

    local option = Option.new(id, config.Default == true)

    option._render = function(value)
        local enabled = value == true
        tween(switch, {
            BackgroundColor3 = enabled and C.Accent or Color3.fromRGB(35, 30, 45),
        }, 0.08)
        tween(knob, {
            Position = enabled and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3),
        }, 0.08)
    end

    option._render(option.Value)

    self._window:_connect(hit.MouseButton1Click, function()
        option:SetValue(not option.Value)
    end)

    bindRowHover(self._window, row, hit)
    return option
end

function Container:AddSlider(id, config)
    config = config or {}

    local minValue = tonumber(config.Min) or 0
    local maxValue = tonumber(config.Max) or 100
    local rounding = tonumber(config.Rounding) or 0
    local defaultValue = tonumber(config.Default) or minValue

    local row = makeRow(self, 42)

    local titleLabel = text(row, config.Title or id, 11, C.Text, Enum.Font.Gotham)
    titleLabel.Position = UDim2.fromOffset(10, 0)
    titleLabel.Size = UDim2.new(0.55, -10, 1, 0)

    local valueLabel = text(row, "", 9, C.Muted2, Enum.Font.Code, Enum.TextXAlignment.Right)
    valueLabel.Position = UDim2.new(0.55, 0, 0, 0)
    valueLabel.Size = UDim2.fromOffset(46, 42)

    local track = create("Frame", {
        BackgroundColor3 = Color3.fromRGB(34, 29, 42),
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.new(0.30, 0, 0, 5),
    }, row)
    corner(track, 3)

    local fill = create("Frame", {
        BackgroundColor3 = C.Accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 1, 0),
    }, track)
    corner(fill, 3)

    local knob = create("Frame", {
        BackgroundColor3 = C.Accent,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
    }, track)
    corner(knob, 7)
    stroke(knob, C.AccentSoft, 0.25, 1)

    local sliderHit = buttonBase(row)
    sliderHit.Position = UDim2.new(0.66, 0, 0, 0)
    sliderHit.Size = UDim2.new(0.34, 0, 1, 0)
    sliderHit.ZIndex = 5

    local function roundValue(value)
        local scale = 10 ^ rounding
        return math.floor(value * scale + 0.5) / scale
    end

    local option = Option.new(id, math.clamp(roundValue(defaultValue), minValue, maxValue))

    local function formatValue(value)
        if rounding <= 0 then
            return tostring(math.floor(value + 0.5))
        end
        return string.format("%." .. tostring(rounding) .. "f", value)
    end

    option._render = function(value)
        value = math.clamp(tonumber(value) or minValue, minValue, maxValue)
        local alpha = (value - minValue) / math.max(maxValue - minValue, 0.0001)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueLabel.Text = formatValue(value)
    end

    option._render(option.Value)

    local dragging = false

    local function updateFromX(x)
        local width = math.max(track.AbsoluteSize.X, 1)
        local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
        local value = roundValue(minValue + (maxValue - minValue) * alpha)
        option:SetValue(value)
    end

    self._window:_connect(sliderHit.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = true
            updateFromX(input.Position.X)
        end
    end)

    self._window:_connect(UserInputService.InputChanged, function(input)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        then
            updateFromX(input.Position.X)
        end
    end)

    self._window:_connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = false
        end
    end)

    bindRowHover(self._window, row, sliderHit)
    return option
end

local function buildPopupSelect(container, id, config, withSwatch)
    config = config or {}

    local values = config.Values or {}
    local index = tonumber(config.Default) or 1
    index = math.clamp(index, 1, math.max(#values, 1))
    local initial = values[index] or ""

    local row = makeRow(container, 42)
    local titleLabel = text(row, config.Title or id, 11, C.Text, Enum.Font.Gotham)
    titleLabel.Position = UDim2.fromOffset(10, 0)
    titleLabel.Size = UDim2.new(0.48, -10, 1, 0)

    local valueBox = create("Frame", {
        BackgroundColor3 = Color3.fromRGB(17, 13, 23),
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        Position = UDim2.new(0.68, 0, 0.5, -14),
        Size = UDim2.new(0.32, -10, 0, 28),
        ZIndex = 10,
    }, row)
    corner(valueBox, 5)
    stroke(valueBox, C.Border, 0.32, 1)

    local colorMap = config.ColorMap or {}
    local swatch = nil
    local textOffset = 9

    if withSwatch then
        swatch = create("Frame", {
            BackgroundColor3 = colorMap[initial] or C.Accent,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(8, 9),
            Size = UDim2.fromOffset(10, 10),
            ZIndex = 11,
        }, valueBox)
        corner(swatch, 3)
        textOffset = 24
    end

    local valueLabel = text(valueBox, initial, 9, C.Muted, Enum.Font.Gotham)
    valueLabel.Position = UDim2.fromOffset(textOffset, 0)
    valueLabel.Size = UDim2.new(1, -(textOffset + 22), 1, 0)
    valueLabel.ZIndex = 11

    local arrow = text(valueBox, "⌄", 11, C.Muted2, Enum.Font.Gotham, Enum.TextXAlignment.Center)
    arrow.Position = UDim2.new(1, -22, 0, 0)
    arrow.Size = UDim2.fromOffset(22, 28)
    arrow.ZIndex = 11

    local option = Option.new(id, initial)
    option._render = function(value)
        valueLabel.Text = tostring(value)
        if swatch then
            swatch.BackgroundColor3 = colorMap[value] or C.Accent
        end
    end
    option._render(initial)

    local hit = buttonBase(valueBox)
    hit.Size = UDim2.fromScale(1, 1)
    hit.ZIndex = 12

    local popup = nil

    local function closePopup()
        if popup then
            popup:Destroy()
            popup = nil
        end
        arrow.Text = "⌄"
    end

    container._window:_connect(hit.MouseButton1Click, function()
        if popup then
            closePopup()
            return
        end

        if #values == 0 then
            return
        end

        arrow.Text = "⌃"

        local itemHeight = 30
        local maxVisible = math.min(#values, 8)
        local popupHeight = maxVisible * itemHeight + 10

        popup = create("ScrollingFrame", {
            Name = id .. "_DropdownPopup",
            BackgroundColor3 = Color3.fromRGB(11, 8, 16),
            BackgroundTransparency = 0.08,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(
                valueBox.AbsolutePosition.X,
                valueBox.AbsolutePosition.Y + valueBox.AbsoluteSize.Y + 4
            ),
            Size = UDim2.fromOffset(math.max(valueBox.AbsoluteSize.X, 150), popupHeight),
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = C.Accent,
            ZIndex = 6000,
        }, container._window.Gui)
        corner(popup, 7)
        stroke(popup, C.AccentDark, 0.26, 1)
        padding(popup, 5, 5, 5, 5)
        list(popup, 3, false)

        for _, value in ipairs(values) do
            local item = create("TextButton", {
                BackgroundColor3 = value == option.Value and C.AccentDark or C.Row,
                BackgroundTransparency = value == option.Value and 0.48 or 0.3,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                Size = UDim2.new(1, -2, 0, itemHeight - 3),
                ZIndex = 6001,
            }, popup)
            corner(item, 5)

            local itemOffset = 9
            if withSwatch then
                local itemSwatch = create("Frame", {
                    BackgroundColor3 = colorMap[value] or C.Accent,
                    BorderSizePixel = 0,
                    Position = UDim2.fromOffset(7, 8),
                    Size = UDim2.fromOffset(10, 10),
                    ZIndex = 6002,
                }, item)
                corner(itemSwatch, 3)
                itemOffset = 24
            end

            local itemLabel = text(item, value, 10, C.Text, Enum.Font.Gotham)
            itemLabel.Position = UDim2.fromOffset(itemOffset, 0)
            itemLabel.Size = UDim2.new(1, -(itemOffset + 5), 1, 0)
            itemLabel.ZIndex = 6002

            container._window:_connect(item.MouseEnter, function()
                tween(item, {BackgroundColor3 = C.RowHover, BackgroundTransparency = 0.15}, 0.06)
            end)

            container._window:_connect(item.MouseLeave, function()
                if value ~= option.Value then
                    tween(item, {BackgroundColor3 = C.Row, BackgroundTransparency = 0.3}, 0.06)
                end
            end)

            container._window:_connect(item.MouseButton1Click, function()
                option:SetValue(value)
                closePopup()
            end)
        end
    end)

    bindRowHover(container._window, row, hit)
    return option
end

function Container:AddDropdown(id, config)
    return buildPopupSelect(self, id, config, false)
end

function Container:AddSelect(id, config)
    -- If Icon is empty, no leading placeholder is created. This keeps
    -- the ESP color rows clean and removes the old square/icon gap.
    return buildPopupSelect(self, id, config, true)
end

function Container:AddButton(config)
    if type(config) == "string" then
        config = {Title = config}
    end
    config = config or {}

    local row = makeRow(self, 40)

    local titleLabel = text(row, config.Title or "Button", 11, C.Text, Enum.Font.Gotham)
    titleLabel.Position = UDim2.fromOffset(10, 0)
    titleLabel.Size = UDim2.new(1, -42, 1, 0)

    local arrow = text(row, "›", 16, C.Muted2, Enum.Font.Gotham, Enum.TextXAlignment.Center)
    arrow.Position = UDim2.new(1, -30, 0, 0)
    arrow.Size = UDim2.fromOffset(24, 40)

    local hit = buttonBase(row)
    hit.Size = UDim2.fromScale(1, 1)
    hit.ZIndex = 5

    self._window:_connect(hit.MouseButton1Click, function()
        if type(config.Callback) == "function" then
            local ok, err = pcall(config.Callback)
            if not ok then
                warn("[CAT EMPIRE UI] button callback error:", err)
            end
        end
    end)

    bindRowHover(self._window, row, hit)
    return row
end

function Container:AddParagraph(config)
    config = config or {}

    local row = makeRow(self, 62)

    local titleLabel = text(row, config.Title or "", 11, C.Text, Enum.Font.GothamMedium)
    titleLabel.Position = UDim2.fromOffset(10, 6)
    titleLabel.Size = UDim2.new(1, -20, 0, 18)

    local body = text(row, config.Content or "", 9, C.Muted2, Enum.Font.Gotham)
    body.Position = UDim2.fromOffset(10, 25)
    body.Size = UDim2.new(1, -20, 0, 30)
    body.TextWrapped = true
    body.TextYAlignment = Enum.TextYAlignment.Top

    return row
end

function Container:AddLabel(value)
    local holder = self:_ensureSection()

    local label = text(holder, value or "", 9, C.Muted, Enum.Font.Code)
    label.Size = UDim2.new(1, 0, 0, 22)

    local api = {}
    function api:SetText(newValue)
        label.Text = tostring(newValue or "")
    end
    api.Label = label
    return api
end

-- ============================================================
-- TABS / GROUPS
-- ============================================================

local Tab = {}
Tab.__index = Tab

function Tab:_ensureDefault()
    if self.DefaultContainer then
        return self.DefaultContainer
    end

    local scroll = create("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = C.Accent,
        ScrollBarImageTransparency = 0.05,
    }, self.Body)

    padding(scroll, 8, 8, 6, 8)
    list(scroll, 7, false)

    local container = setmetatable({
        _scroll = scroll,
        _currentSection = nil,
        _nextOrder = 1,
        _window = self.Window,
    }, Container)

    self.DefaultContainer = container
    return container
end

function Tab:AddGroup(config)
    config = config or {}

    local columns = math.max(1, tonumber(config.Columns) or 2)
    local gap = tonumber(config.Gap) or 8

    if self.DefaultContainer and self.DefaultContainer._scroll then
        self.DefaultContainer._scroll.Visible = false
    end

    local group = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
    }, self.Body)

    local layout = list(group, gap, true)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.VerticalAlignment = Enum.VerticalAlignment.Top

    local api = {
        _frame = group,
        _window = self.Window,
        _columns = columns,
        _gap = gap,
        _count = 0,
    }

    function api:AddElement()
        self._count += 1

        local offsetLoss = math.floor((gap * (columns - 1)) / columns)
        local scroll = create("ScrollingFrame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(1 / columns, -offsetLoss, 1, 0),
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = C.Accent,
            ScrollBarImageTransparency = 0.05,
        }, group)

        padding(scroll, 4, 4, 6, 8)
        list(scroll, 7, false)

        return setmetatable({
            _scroll = scroll,
            _currentSection = nil,
            _nextOrder = 1,
            _window = self._window,
        }, Container)
    end

    return api
end

function Tab:AddSection(...) return self:_ensureDefault():AddSection(...) end
function Tab:AddToggle(...) return self:_ensureDefault():AddToggle(...) end
function Tab:AddSlider(...) return self:_ensureDefault():AddSlider(...) end
function Tab:AddDropdown(...) return self:_ensureDefault():AddDropdown(...) end
function Tab:AddSelect(...) return self:_ensureDefault():AddSelect(...) end
function Tab:AddButton(...) return self:_ensureDefault():AddButton(...) end
function Tab:AddParagraph(...) return self:_ensureDefault():AddParagraph(...) end
function Tab:AddLabel(...) return self:_ensureDefault():AddLabel(...) end

function Window:AddTab(config)
    config = config or {}

    local titleValue = config.Title or "Tab"
    local iconValue = ICONS[config.Icon] or "•"

    local tab = setmetatable({
        Window = self,
        Title = titleValue,
    }, Tab)

    local sidebarButton = create("TextButton", {
        BackgroundColor3 = C.Sidebar,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Size = UDim2.new(1, -10, 0, 36),
    }, self.SidebarList)
    corner(sidebarButton, 5)

    local indicator = create("Frame", {
        BackgroundColor3 = C.Accent,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 7),
        Size = UDim2.fromOffset(3, 22),
        Visible = false,
    }, sidebarButton)
    corner(indicator, 2)

    local iconFrame = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(9, 5),
        Size = UDim2.fromOffset(24, 26),
    }, sidebarButton)

    local iconHolder = DrawSidebarIcon(iconFrame, iconValue)

    local titleLabel = text(sidebarButton, titleValue, 11, C.Muted, Enum.Font.Gotham)
    titleLabel.Position = UDim2.fromOffset(40, 0)
    titleLabel.Size = UDim2.new(1, -46, 1, 0)

    local page = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromScale(1, 1),
        Visible = false,
    }, self.Pages)

    local pageHeader = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 54),
    }, page)

    local pageIconFrame = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(2, 13),
        Size = UDim2.fromOffset(24, 24),
    }, pageHeader)
    local pageIconHolder = DrawSidebarIcon(pageIconFrame, iconValue)
    SetSidebarIconColor(pageIconHolder, C.Text)

    local pageLabel = text(pageHeader, titleValue, 20, C.Text, Enum.Font.GothamMedium)
    pageLabel.Position = UDim2.fromOffset(34, 5)
    pageLabel.Size = UDim2.new(1, -34, 0, 38)

    local body = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 54),
        Size = UDim2.new(1, 0, 1, -54),
    }, page)

    tab.Button = sidebarButton
    tab.Indicator = indicator
    tab.IconHolder = iconHolder
    tab.TitleLabel = titleLabel
    tab.Page = page
    tab.Body = body

    table.insert(self.Tabs, tab)

    self:_connect(sidebarButton.MouseButton1Click, function()
        self:_selectTab(tab)
    end)

    self:_connect(sidebarButton.MouseEnter, function()
        if self.ActiveTab ~= tab then
            tween(sidebarButton, {
                BackgroundColor3 = C.RowHover,
                BackgroundTransparency = 0.62,
            }, 0.08)
        end
    end)

    self:_connect(sidebarButton.MouseLeave, function()
        if self.ActiveTab ~= tab then
            tween(sidebarButton, {
                BackgroundColor3 = C.Sidebar,
                BackgroundTransparency = 1,
            }, 0.08)
        end
    end)

    if #self.Tabs == 1 then
        self:_selectTab(tab)
    end

    return tab
end

-- ============================================================
-- LIBRARY
-- ============================================================

local function ResolveCatEmpireLogo()
    local env = _G

    if type(getgenv) == "function" then
        local ok, resolved = pcall(getgenv)
        if ok and type(resolved) == "table" then
            env = resolved
        end
    end

    local assetFn = rawget(env, "getcustomasset") or rawget(env, "getsynasset")
    local writeFn = rawget(env, "writefile")
    local isFileFn = rawget(env, "isfile")

    if type(assetFn) ~= "function" or type(writeFn) ~= "function" then
        return nil
    end

    local fileName = "CAT_EMPIRE_sidebar_logo_v12.jpg"
    local url =
        "https://raw.githubusercontent.com/"
        .. "DanoninCat/DanoninScript/main/Assets/"
        .. "CatEmpireLogo.jpg"

    local ok = pcall(function()
        local exists = type(isFileFn) == "function" and isFileFn(fileName)
        if not exists then
            writeFn(fileName, game:HttpGet(url))
        end
    end)

    if not ok then
        return nil
    end

    local okAsset, asset = pcall(assetFn, fileName)
    if okAsset then
        return asset
    end

    return nil
end

function Library:CreateWindow(config)
    config = config or {}

    local screenName = config.ScreenGuiName or "CAT_EMPIRE"

    local previous = PlayerGui:FindFirstChild(screenName)
    if previous then
        pcall(function()
            previous:Destroy()
        end)
    end

    self.Options = {}
    Library.Options = self.Options

    local width =
        (config.Size and config.Size.X and config.Size.X.Offset)
        or 760
    local height =
        (config.Size and config.Size.Y and config.Size.Y.Offset)
        or 460

    width = math.max(width, 760)
    height = math.max(height, 460)

    local gui = create("ScreenGui", {
        Name = screenName,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 1000,
    }, PlayerGui)

    local root = create("Frame", {
        Name = "Window",
        BackgroundColor3 = C.Background,
        BackgroundTransparency = 0.18,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(width, height),
        ClipsDescendants = true,
        Active = true,
    }, gui)

    corner(root, 9)
    stroke(root, C.AccentDark, 0.32, 1)

    local themeBackground = create("ImageLabel", {
        Name = "CAT_EMPIRE_ThemeBackground",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = "rbxassetid://74252111742950",
        ImageTransparency = 0.46,
        ScaleType = Enum.ScaleType.Crop,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 0,
    }, root)

    local glass = makeGlass(root, C.AccentDark, 0.82, 1)

    local uiScale = create("UIScale", {
        Scale = 1,
    }, root)

    local viewport = Vector2.new(1280, 720)
    pcall(function()
        local camera = workspace.CurrentCamera
        if camera then
            viewport = camera.ViewportSize
        end
    end)

    local defaultScale = 1
    if UserInputService.TouchEnabled then
        local fitX = math.max(0.5, (viewport.X - 30) / width)
        local fitY = math.max(0.5, (viewport.Y - 30) / height)
        defaultScale = math.clamp(math.min(fitX, fitY, 0.78), 0.55, 0.78)
    end
    uiScale.Scale = defaultScale

    local topbar = create("Frame", {
        Name = "TitleBar",
        BackgroundColor3 = C.Topbar,
        BackgroundTransparency = 0.34,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 44),
        ZIndex = 5,
    }, root)

    local topLine = create("Frame", {
        BackgroundColor3 = C.AccentDark,
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, -1),
        Size = UDim2.new(1, 0, 0, 1),
        ZIndex = 6,
    }, topbar)

    local titleBlock = create("Frame", {
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

    local controlWrap = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -7, 0, 7),
        Size = UDim2.fromOffset(116, 30),
        ZIndex = 8,
    }, topbar)

    local minimizeButton = create("TextButton", {
        BackgroundColor3 = C.Row,
        BackgroundTransparency = 0.75,
        BorderSizePixel = 0,
        Text = "—",
        TextColor3 = C.Muted,
        TextSize = 13,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = false,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(34, 28),
        ZIndex = 9,
    }, controlWrap)
    corner(minimizeButton, 5)

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

    local closeButton = create("TextButton", {
        BackgroundColor3 = C.Row,
        BackgroundTransparency = 0.75,
        BorderSizePixel = 0,
        Text = "×",
        TextColor3 = C.Muted,
        TextSize = 16,
        Font = Enum.Font.Gotham,
        AutoButtonColor = false,
        Position = UDim2.fromOffset(80, 0),
        Size = UDim2.fromOffset(34, 28),
        ZIndex = 9,
    }, controlWrap)
    corner(closeButton, 5)

    local sidebarVisual = create("Frame", {
        Name = "SidebarVisual",
        BackgroundColor3 = C.Sidebar,
        BackgroundTransparency = 0.42,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 44),
        Size = UDim2.new(0, 150, 1, -44),
        ZIndex = 2,
    }, root)

    create("Frame", {
        BackgroundColor3 = C.Border,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -1, 0, 0),
        Size = UDim2.new(0, 1, 1, 0),
        ZIndex = 3,
    }, sidebarVisual)

    local sidebarList = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(8, 8),
        Size = UDim2.new(1, -8, 1, -16),
        ZIndex = 4,
    }, sidebarVisual)
    list(sidebarList, 4, false)

    local contentVisual = create("Frame", {
        Name = "ContentVisual",
        BackgroundColor3 = C.Content,
        BackgroundTransparency = 0.50,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(150, 44),
        Size = UDim2.new(1, -150, 1, -44),
        ZIndex = 2,
    }, root)

    local pages = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -24, 1, -16),
        ZIndex = 3,
    }, contentVisual)

    local dragZone = create("Frame", {
        Name = "DragZone",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, -130, 0, 44),
        Active = true,
        ZIndex = 20,
    }, topbar)

    local externalToggle = create("TextButton", {
        Name = "CAT_EMPIRE_Toggle",
        BackgroundColor3 = C.Accent,
        BackgroundTransparency = 0.10,
        BorderSizePixel = 0,
        Text = "CE",
        TextColor3 = C.Text,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = false,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 12, 0.5, 0),
        Size = UDim2.fromOffset(42, 42),
        ZIndex = 3000,
    }, gui)
    corner(externalToggle, 10)
    stroke(externalToggle, C.AccentSoft, 0.18, 1)

    -- Compatibility proxies: MurderDuel.lua changes Sidebar/Content
    -- BackgroundTransparency for its background presets. The visible glass
    -- surfaces stay reference-style while those legacy assignments remain safe.
    local sidebarProxy = create("Frame", {
        Name = "SidebarProxy",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(0, 0),
        Visible = false,
    })
    local contentProxy = create("Frame", {
        Name = "ContentProxy",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(0, 0),
        Visible = false,
    })

    local window = setmetatable({
        Gui = gui,
        Root = root,
        UIScale = uiScale,
        ScaleValue = defaultScale,
        ExternalToggle = externalToggle,
        Titlebar = dragZone,
        Sidebar = sidebarProxy,
        SidebarVisual = sidebarVisual,
        SidebarList = sidebarList,
        Content = contentProxy,
        ContentVisual = contentVisual,
        Pages = pages,
        Tabs = {},
        ActiveTab = nil,
        FullWidth = width,
        FullHeight = height,
        Minimized = false,
        Destroyed = false,
        MinButton = minimizeButton,
        MaxButton = maximizeButton,
        Maximized = false,
        RestorePosition = nil,
        RestoreSize = nil,
        _connections = {},
    }, Window)

    window.TitleBar = {
        MaxButton = maximizeButton,
        MinButton = minimizeButton,
        CloseButton = closeButton,
    }

    window:_connect(externalToggle.MouseButton1Click, function()
        window:ToggleMinimize()
    end)

    window:_connect(minimizeButton.MouseButton1Click, function()
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

    window:_connect(closeButton.MouseButton1Click, function()
        window:Destroy()
    end)

    for _, btn in ipairs({externalToggle, minimizeButton, maximizeButton, closeButton}) do
        window:_connect(btn.MouseEnter, function()
            tween(btn, {BackgroundColor3 = C.AccentSoft, BackgroundTransparency = 0.16}, 0.08)
        end)
        window:_connect(btn.MouseLeave, function()
            tween(btn, {
                BackgroundColor3 = btn == externalToggle and C.Accent or C.Row,
                BackgroundTransparency = btn == externalToggle and 0.10 or 0.75,
            }, 0.08)
        end)
    end

    local dragging = false
    local dragStart = nil
    local startPos = nil

    window:_connect(dragZone.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = true
            dragStart = input.Position
            startPos = root.Position
        end
    end)

    window:_connect(UserInputService.InputChanged, function(input)
        if not dragging or not dragStart or not startPos then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        then
            local delta = input.Position - dragStart
            root.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)

    window:_connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = false
        end
    end)

    local minimizeKey = config.MinimizeKey or Enum.KeyCode.LeftControl
    window:_connect(UserInputService.InputBegan, function(input, processed)
        if processed then
            return
        end
        if minimizeKey == Enum.KeyCode.Unknown
            or input.UserInputType ~= Enum.UserInputType.Keyboard
        then
            return
        end
        if input.KeyCode == minimizeKey then
            window:ToggleMinimize()
        end
    end)

    table.insert(self.Windows, window)
    return window
end

function Library:Notify(config)
    config = config or {}

    local latest = self.Windows[#self.Windows]
    if not latest or latest.Destroyed or not latest.Gui then
        print("[CAT EMPIRE]", config.Title or "Notice", config.Content or "")
        return
    end

    local toast = create("Frame", {
        BackgroundColor3 = C.Section,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 14),
        Size = UDim2.fromOffset(250, 60),
        ZIndex = 7000,
    }, latest.Gui)
    corner(toast, 7)
    stroke(toast, C.AccentDark, 0.15, 1)

    create("Frame", {
        BackgroundColor3 = C.Accent,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 7),
        Size = UDim2.fromOffset(3, 46),
        ZIndex = 7001,
    }, toast)

    local titleLabel = text(toast, config.Title or "CAT EMPIRE", 10, C.Text, Enum.Font.GothamMedium)
    titleLabel.Position = UDim2.fromOffset(12, 7)
    titleLabel.Size = UDim2.new(1, -22, 0, 18)
    titleLabel.ZIndex = 7001

    local body = text(toast, config.Content or "", 9, C.Muted, Enum.Font.Gotham)
    body.Position = UDim2.fromOffset(12, 25)
    body.Size = UDim2.new(1, -22, 0, 27)
    body.TextWrapped = true
    body.ZIndex = 7001

    task.delay(tonumber(config.Duration) or 3, function()
        if toast and toast.Parent then
            pcall(function()
                toast:Destroy()
            end)
        end
    end)
end

return Library
