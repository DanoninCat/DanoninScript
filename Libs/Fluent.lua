-- ============================================================
-- CAT EMPIRE UI
-- Source-inspired dark/indigo UI library for DanoninScript.
-- No images, no virtual ModuleScript environment.
-- Drop-in replacement for Libs/Fluent.lua used by MurderDuel.lua.
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

local C = {
    Background = Color3.fromRGB(8, 8, 10),
    Sidebar = Color3.fromRGB(9, 9, 12),
    Content = Color3.fromRGB(8, 8, 11),
    Section = Color3.fromRGB(12, 12, 16),
    SectionCap = Color3.fromRGB(18, 18, 24),
    Row = Color3.fromRGB(12, 12, 16),
    RowHover = Color3.fromRGB(20, 20, 28),
    Border = Color3.fromRGB(31, 31, 42),
    BorderSoft = Color3.fromRGB(22, 22, 30),
    Accent = Color3.fromRGB(92, 72, 255),
    AccentDark = Color3.fromRGB(67, 54, 214),
    AccentSoft = Color3.fromRGB(126, 110, 255),
    Text = Color3.fromRGB(255, 255, 255),
    Muted = Color3.fromRGB(218, 218, 228),
    Muted2 = Color3.fromRGB(158, 158, 176),
    Knob = Color3.fromRGB(255, 255, 255),
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
        CornerRadius = UDim.new(0, radius or 4),
    }, parent)
end

local function stroke(parent, color, transparency, thickness)
    return create("UIStroke", {
        Color = color or C.Border,
        Transparency = transparency or 0,
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

        -- Apply UI default to the actual backing state.
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
            self._render(value)
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

-- Forward declaration: _selectTab is defined before the icon helpers below.
-- Without this, Luau resolves SetSidebarIconColor as a global (nil) and
-- SetupUI stops while creating/selecting the first tab.
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

    -- Mark first: a cleanup callback may indirectly call Window:Destroy()
    -- again. Setting the flag before the callback prevents recursion.
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
            candidate.Indicator.Visible = false
        end

        if candidate.Button then
            candidate.Button.BackgroundColor3 =
                active and C.Accent or C.Sidebar
            candidate.Button.BackgroundTransparency =
                active and 0 or 1
        end
        if candidate.IconHolder then
            SetSidebarIconColor(
                candidate.IconHolder,
                active and C.Text or C.Muted
            )
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

local function DrawSidebarIcon(parent, iconName)
    local holder = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
    }, parent)

    local function line(pos, size, radius)
        local f = create("Frame", {
            BackgroundColor3 = C.Muted,
            BorderSizePixel = 0,
            Position = pos,
            Size = size,
        }, holder)
        if radius then corner(f, radius) end
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
        local tab = line(UDim2.fromOffset(4, 7), UDim2.fromOffset(9, 4), 2)
        local body = line(UDim2.fromOffset(3, 10), UDim2.fromOffset(20, 12), 2)
        tab.BackgroundColor3 = C.Muted
        body.BackgroundColor3 = C.Muted
    elseif iconName == "settings" then
        local gear = text(
            holder,
            "⚙",
            18,
            C.Muted,
            Enum.Font.GothamBold,
            Enum.TextXAlignment.Center
        )
        gear.Size = UDim2.fromScale(1, 1)
    elseif iconName == "players" then
        local head = line(UDim2.fromOffset(10, 6), UDim2.fromOffset(7, 7), 4)
        local body = line(UDim2.fromOffset(6, 15), UDim2.fromOffset(15, 8), 6)
        head.BackgroundColor3 = C.Muted
        body.BackgroundColor3 = C.Muted
    else
        local dot = line(UDim2.fromOffset(11, 11), UDim2.fromOffset(5, 5), 3)
        dot.BackgroundColor3 = C.Muted
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

    padding(section, 8, 8, 4, 8)
    list(section, 3, false)

    if titleValue and titleValue ~= "" then
        local titleLabel = text(
            section,
            titleValue,
            13,
            C.Text,
            Enum.Font.GothamBold
        )

        titleLabel.TextTransparency = 0.08
        titleLabel.Size = UDim2.new(1, 0, 0, 24)
        titleLabel.LayoutOrder = 0
    end

    local holder = create("Frame", {
        Name = "Rows",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 1,
    }, section)

    list(holder, 1, false)

    self._currentSection = holder
    return section
end

local function makeRow(container, height)
    local holder = container:_ensureSection()

    local row = create("Frame", {
        BackgroundColor3 = C.Row,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, height),
    }, holder)

    return row
end

function Container:AddToggle(id, config)
    config = config or {}

    local row = makeRow(self, 30)

    local titleLabel = text(
        row,
        config.Title or id,
        13,
        C.Text,
        Enum.Font.Gotham
    )

    titleLabel.Position = UDim2.fromOffset(2, 0)
    titleLabel.Size = UDim2.new(1, -38, 1, 0)

    local box = create("Frame", {
        BackgroundColor3 = Color3.fromRGB(7, 7, 9),
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.new(1, -20, 0.5, -8),
    }, row)

    corner(box, 2)
    stroke(box, C.Border, 0, 1)

    local mark = text(
        box,
        "✓",
        12,
        C.Text,
        Enum.Font.GothamBold,
        Enum.TextXAlignment.Center
    )
    mark.Size = UDim2.fromScale(1, 1)
    mark.Visible = false

    local hit = buttonBase(row)
    hit.Size = UDim2.fromScale(1, 1)
    hit.ZIndex = 5

    local option = Option.new(id, config.Default == true)

    option._render = function(value)
        local enabled = value == true
        box.BackgroundColor3 = enabled and C.Accent or Color3.fromRGB(7, 7, 9)
        mark.Visible = enabled
    end

    option._render(option.Value)

    self._window:_connect(hit.MouseButton1Click, function()
        option:SetValue(not option.Value)
    end)

    self._window:_connect(hit.MouseEnter, function()
        row.BackgroundTransparency = 0
        row.BackgroundColor3 = C.RowHover
    end)

    self._window:_connect(hit.MouseLeave, function()
        row.BackgroundTransparency = 1
    end)

    return option
end

function Container:AddSlider(id, config)
    config = config or {}

    local minValue = tonumber(config.Min) or 0
    local maxValue = tonumber(config.Max) or 100
    local rounding = tonumber(config.Rounding) or 0
    local defaultValue = tonumber(config.Default) or minValue

    local row = makeRow(self, 54)

    local titleLabel = text(
        row,
        config.Title or id,
        14,
        C.Text,
        Enum.Font.Gotham
    )

    titleLabel.Position = UDim2.fromOffset(2, 2)
    titleLabel.Size = UDim2.new(1, -72, 0, 18)

    local valueLabel = text(
        row,
        "",
        10,
        C.Muted,
        Enum.Font.Code,
        Enum.TextXAlignment.Right
    )

    valueLabel.Position = UDim2.new(1, -66, 0, 2)
    valueLabel.Size = UDim2.fromOffset(58, 18)

    local track = create("Frame", {
        BackgroundColor3 = Color3.fromRGB(4, 4, 6),
        BorderSizePixel = 0,
        Position = UDim2.new(0, 2, 1, -12),
        Size = UDim2.new(1, -4, 0, 5),
    }, row)

    corner(track, 2)

    local fill = create("Frame", {
        BackgroundColor3 = C.Accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 1, 0),
    }, track)

    corner(fill, 2)

    local knob = create("Frame", {
        BackgroundColor3 = C.Knob,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
    }, track)

    corner(knob, 7)

    local sliderHit = buttonBase(row)
    sliderHit.Position = UDim2.new(0, 2, 1, -21)
    sliderHit.Size = UDim2.new(1, -4, 0, 18)
    sliderHit.ZIndex = 5

    local function roundValue(value)
        local scale = 10 ^ rounding
        return math.floor(value * scale + 0.5) / scale
    end

    local option = Option.new(
        id,
        math.clamp(
            roundValue(defaultValue),
            minValue,
            maxValue
        )
    )

    local function formatValue(value)
        if rounding <= 0 then
            return tostring(math.floor(value + 0.5))
        end

        return string.format(
            "%." .. tostring(rounding) .. "f",
            value
        )
    end

    option._render = function(value)
        value = math.clamp(
            tonumber(value) or minValue,
            minValue,
            maxValue
        )

        local alpha =
            (value - minValue)
            / math.max(maxValue - minValue, 0.0001)

        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueLabel.Text = formatValue(value)
    end

    option._render(option.Value)

    local dragging = false

    local function updateFromX(x)
        local width = math.max(track.AbsoluteSize.X, 1)

        local alpha = math.clamp(
            (x - track.AbsolutePosition.X) / width,
            0,
            1
        )

        local value = roundValue(
            minValue
            + (maxValue - minValue) * alpha
        )

        option:SetValue(value)
    end

    self._window:_connect(sliderHit.InputBegan, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
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

        if
            input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        then
            updateFromX(input.Position.X)
        end
    end)

    self._window:_connect(UserInputService.InputEnded, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = false
        end
    end)

    return option
end

function Container:AddDropdown(id, config)
    config = config or {}

    local values = config.Values or {}
    local index = tonumber(config.Default) or 1

    index = math.clamp(
        index,
        1,
        math.max(#values, 1)
    )

    local initial = values[index] or ""

    local row = makeRow(self, 34)

    local titleLabel = text(
        row,
        config.Title or id,
        10,
        C.Text,
        Enum.Font.Gotham
    )

    titleLabel.Position = UDim2.fromOffset(9, 0)
    titleLabel.Size = UDim2.new(0.42, -9, 1, 0)

    local valueBox = create("Frame", {
        BackgroundColor3 = Color3.fromRGB(14, 14, 17),
        BorderSizePixel = 0,
        Position = UDim2.new(0.42, 0, 0, 4),
        Size = UDim2.new(0.58, -8, 1, -8),
    }, row)

    corner(valueBox, 3)
    stroke(valueBox, C.Border, 0.25, 1)

    local valueLabel = text(
        valueBox,
        initial,
        9,
        C.Muted,
        Enum.Font.Gotham
    )

    valueLabel.Position = UDim2.fromOffset(8, 0)
    valueLabel.Size = UDim2.new(1, -28, 1, 0)

    local arrow = text(
        valueBox,
        "⌄",
        11,
        C.Muted2,
        Enum.Font.Gotham,
        Enum.TextXAlignment.Center
    )

    arrow.Position = UDim2.new(1, -22, 0, 0)
    arrow.Size = UDim2.fromOffset(22, 26)

    local hit = buttonBase(valueBox)
    hit.Size = UDim2.fromScale(1, 1)
    hit.ZIndex = 5

    local option = Option.new(id, initial)

    option._render = function(value)
        valueLabel.Text = tostring(value)
    end

    option._render(initial)

    -- Compact reference-style dropdown:
    -- every click advances to the next value.
    self._window:_connect(hit.MouseButton1Click, function()
        if #values == 0 then
            return
        end

        local currentIndex =
            table.find(values, option.Value) or 0

        currentIndex += 1

        if currentIndex > #values then
            currentIndex = 1
        end

        option:SetValue(values[currentIndex])
    end)

    return option
end


function Container:AddSelect(id, config)
    config = config or {}

    local values = config.Values or {}
    local index = tonumber(config.Default) or 1
    index = math.clamp(index, 1, math.max(#values, 1))

    local initial = values[index] or ""
    local row = makeRow(self, 36)

    local iconLabel = text(
        row,
        config.Icon or "🪣",
        14,
        C.Accent,
        Enum.Font.GothamBold,
        Enum.TextXAlignment.Center
    )
    iconLabel.Position = UDim2.fromOffset(1, 0)
    iconLabel.Size = UDim2.fromOffset(24, 36)

    local titleLabel = text(
        row,
        config.Title or id,
        10,
        C.Text,
        Enum.Font.Gotham
    )
    titleLabel.Position = UDim2.fromOffset(28, 0)
    titleLabel.Size = UDim2.new(0.36, -28, 1, 0)

    local valueBox = create("Frame", {
        BackgroundColor3 = Color3.fromRGB(13, 13, 20),
        BorderSizePixel = 0,
        Position = UDim2.new(0.36, 0, 0, 4),
        Size = UDim2.new(0.64, -6, 1, -8),
        ZIndex = 10,
    }, row)
    corner(valueBox, 4)
    stroke(valueBox, C.Border, 0.15, 1)

    local swatch = create("Frame", {
        BackgroundColor3 = C.Accent,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(7, 7),
        Size = UDim2.fromOffset(10, 10),
        ZIndex = 11,
    }, valueBox)
    corner(swatch, 3)

    local valueLabel = text(
        valueBox,
        initial,
        9,
        C.Muted,
        Enum.Font.Gotham
    )
    valueLabel.Position = UDim2.fromOffset(23, 0)
    valueLabel.Size = UDim2.new(1, -46, 1, 0)
    valueLabel.ZIndex = 11

    local arrow = text(
        valueBox,
        "⌄",
        11,
        C.Muted2,
        Enum.Font.Gotham,
        Enum.TextXAlignment.Center
    )
    arrow.Position = UDim2.new(1, -22, 0, 0)
    arrow.Size = UDim2.fromOffset(22, 28)
    arrow.ZIndex = 11

    local option = Option.new(id, initial)

    local colorMap = config.ColorMap or {}

    option._render = function(value)
        valueLabel.Text = tostring(value)
        swatch.BackgroundColor3 =
            colorMap[value] or C.Accent
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
    end

    self._window:_connect(hit.MouseButton1Click, function()
        if popup then
            closePopup()
            return
        end

        if #values == 0 then
            return
        end

        popup = create("Frame", {
            Name = id .. "_SelectPopup",
            BackgroundColor3 = Color3.fromRGB(10, 10, 16),
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(
                valueBox.AbsolutePosition.X,
                valueBox.AbsolutePosition.Y + valueBox.AbsoluteSize.Y + 4
            ),
            Size = UDim2.fromOffset(
                math.max(valueBox.AbsoluteSize.X, 120),
                (#values * 28) + 8
            ),
            ZIndex = 5000,
        }, self._window.Gui)
        corner(popup, 5)
        stroke(popup, C.Border, 0, 1)
        padding(popup, 4, 4, 4, 4)
        list(popup, 2, false)

        for _, value in ipairs(values) do
            local item = create("TextButton", {
                BackgroundColor3 = Color3.fromRGB(13, 13, 20),
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                Size = UDim2.new(1, 0, 0, 26),
                ZIndex = 5001,
            }, popup)
            corner(item, 3)

            local itemSwatch = create("Frame", {
                BackgroundColor3 = colorMap[value] or C.Accent,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(7, 8),
                Size = UDim2.fromOffset(10, 10),
                ZIndex = 5002,
            }, item)
            corner(itemSwatch, 3)

            local itemLabel = text(
                item,
                value,
                10,
                C.Text,
                Enum.Font.Gotham
            )
            itemLabel.Position = UDim2.fromOffset(24, 0)
            itemLabel.Size = UDim2.new(1, -28, 1, 0)
            itemLabel.ZIndex = 5002

            self._window:_connect(item.MouseButton1Click, function()
                option:SetValue(value)
                closePopup()
            end)
        end
    end)

    return option
end

function Container:AddButton(config)
    if type(config) == "string" then
        config = {Title = config}
    end

    config = config or {}

    local row = makeRow(self, 33)

    local titleLabel = text(
        row,
        config.Title or "Button",
        10,
        C.Text,
        Enum.Font.GothamMedium,
        Enum.TextXAlignment.Center
    )

    titleLabel.Size = UDim2.fromScale(1, 1)

    local hit = buttonBase(row)
    hit.Size = UDim2.fromScale(1, 1)
    hit.ZIndex = 5

    self._window:_connect(hit.MouseEnter, function()
        tween(row, {BackgroundColor3 = C.AccentSoft}, 0.08)
        titleLabel.TextColor3 = C.Text
    end)

    self._window:_connect(hit.MouseLeave, function()
        tween(row, {BackgroundColor3 = C.Row}, 0.08)
    end)

    self._window:_connect(hit.MouseButton1Click, function()
        if type(config.Callback) == "function" then
            local ok, err = pcall(config.Callback)

            if not ok then
                warn(
                    "[CAT EMPIRE UI] button callback error:",
                    err
                )
            end
        end
    end)

    return row
end

function Container:AddParagraph(config)
    config = config or {}

    local row = makeRow(self, 58)

    local titleLabel = text(
        row,
        config.Title or "",
        10,
        C.Text,
        Enum.Font.GothamMedium
    )

    titleLabel.Position = UDim2.fromOffset(9, 5)
    titleLabel.Size = UDim2.new(1, -18, 0, 18)

    local body = text(
        row,
        config.Content or "",
        9,
        C.Muted,
        Enum.Font.Gotham
    )

    body.Position = UDim2.fromOffset(9, 23)
    body.Size = UDim2.new(1, -18, 0, 28)
    body.TextWrapped = true
    body.TextYAlignment = Enum.TextYAlignment.Top

    return row
end

function Container:AddLabel(value)
    local holder = self:_ensureSection()

    local label = text(
        holder,
        value or "",
        9,
        C.Muted,
        Enum.Font.Code
    )

    label.Size = UDim2.new(1, 0, 0, 20)

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
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = C.Accent,
        ScrollBarImageTransparency = 0.08,
    }, self.Body)

    padding(scroll, 8, 8, 7, 8)
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

    local columns =
        math.max(1, tonumber(config.Columns) or 2)

    local gap =
        tonumber(config.Gap) or 8

    if
        self.DefaultContainer
        and self.DefaultContainer._scroll
    then
        self.DefaultContainer._scroll.Visible = false
    end

    local group = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
    }, self.Body)

    local layout = list(group, gap, true)
    layout.HorizontalAlignment =
        Enum.HorizontalAlignment.Left
    layout.VerticalAlignment =
        Enum.VerticalAlignment.Top

    local api = {
        _frame = group,
        _window = self.Window,
        _columns = columns,
        _gap = gap,
        _count = 0,
    }

    function api:AddElement()
        self._count += 1

        local offsetLoss =
            math.floor(
                (gap * (columns - 1))
                / columns
            )

        local scroll = create("ScrollingFrame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(
                1 / columns,
                -offsetLoss,
                1,
                0
            ),
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = C.Accent,
            ScrollBarImageTransparency = 0.08,
        }, group)

        padding(scroll, 4, 4, 7, 8)
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

function Tab:AddSection(...)
    return self:_ensureDefault():AddSection(...)
end

function Tab:AddToggle(...)
    return self:_ensureDefault():AddToggle(...)
end

function Tab:AddSlider(...)
    return self:_ensureDefault():AddSlider(...)
end

function Tab:AddDropdown(...)
    return self:_ensureDefault():AddDropdown(...)
end

function Tab:AddSelect(...)
    return self:_ensureDefault():AddSelect(...)
end

function Tab:AddButton(...)
    return self:_ensureDefault():AddButton(...)
end

function Tab:AddParagraph(...)
    return self:_ensureDefault():AddParagraph(...)
end

function Tab:AddLabel(...)
    return self:_ensureDefault():AddLabel(...)
end

function Window:AddTab(config)
    config = config or {}

    local titleValue =
        config.Title or "Tab"

    local iconValue =
        ICONS[config.Icon] or "•"

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

    corner(sidebarButton, 4)

    local indicator = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        Size = UDim2.fromOffset(0, 0),
    }, sidebarButton)

    local iconFrame = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(8, 4),
        Size = UDim2.fromOffset(26, 28),
    }, sidebarButton)

    local iconHolder = DrawSidebarIcon(
        iconFrame,
        iconValue
    )

    local titleLabel = text(
        sidebarButton,
        titleValue,
        13,
        C.Muted,
        Enum.Font.GothamMedium
    )
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
        Size = UDim2.new(1, 0, 0, 42),
    }, page)

    local pageTag = create("Frame", {
        BackgroundColor3 = C.Accent,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 1),
        Size = UDim2.fromOffset(math.max(72, #titleValue * 8 + 26), 28),
    }, pageHeader)
    corner(pageTag, 4)

    local pageLabel = text(
        pageTag,
        titleValue,
        13,
        C.Text,
        Enum.Font.GothamBold,
        Enum.TextXAlignment.Center
    )
    pageLabel.Size = UDim2.fromScale(1, 1)

    local body = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 42),
        Size = UDim2.new(1, 0, 1, -42),
    }, page)

    tab.Button = sidebarButton
    tab.Indicator = indicator
    tab.IconHolder = iconHolder
    tab.TitleLabel = titleLabel
    tab.Page = page
    tab.Body = body

    table.insert(self.Tabs, tab)

    self:_connect(
        sidebarButton.MouseButton1Click,
        function()
            self:_selectTab(tab)
        end
    )

    self:_connect(
        sidebarButton.MouseEnter,
        function()
            if self.ActiveTab ~= tab then
                tween(
                    sidebarButton,
                    {
                        BackgroundColor3 = C.SectionCap,
                        BackgroundTransparency = 0,
                    },
                    0.08
                )
            end
        end
    )

    self:_connect(
        sidebarButton.MouseLeave,
        function()
            if self.ActiveTab ~= tab then
                tween(
                    sidebarButton,
                    {
                        BackgroundColor3 = C.Sidebar,
                        BackgroundTransparency = 1,
                    },
                    0.08
                )
            end
        end
    )

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

    local assetFn =
        rawget(env, "getcustomasset")
        or rawget(env, "getsynasset")

    local writeFn =
        rawget(env, "writefile")

    local isFileFn =
        rawget(env, "isfile")

    if type(assetFn) ~= "function"
        or type(writeFn) ~= "function"
    then
        return nil
    end

    local fileName = "CAT_EMPIRE_sidebar_logo_v12.jpg"
    local url =
        "https://raw.githubusercontent.com/" ..
        "DanoninCat/DanoninScript/main/Assets/" ..
        "CatEmpireLogo.jpg"

    local ok = pcall(function()
        local exists =
            type(isFileFn) == "function"
            and isFileFn(fileName)

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

    local screenName =
        config.ScreenGuiName
        or "CAT_EMPIRE"

    local previous =
        PlayerGui:FindFirstChild(screenName)

    if previous then
        pcall(function()
            previous:Destroy()
        end)
    end

    self.Options = {}
    Library.Options = self.Options

    local width =
        (
            config.Size
            and config.Size.X
            and config.Size.X.Offset
        )
        or 760

    local height =
        (
            config.Size
            and config.Size.Y
            and config.Size.Y.Offset
        )
        or 460

    -- Reference-like compact base size.
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
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(width, height),
        ClipsDescendants = true,
        Active = true,
    }, gui)

    corner(root, 5)
    stroke(root, C.Border, 0, 1)

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

        defaultScale = math.clamp(
            math.min(fitX, fitY, 0.78),
            0.55,
            0.78
        )
    end

    uiScale.Scale = defaultScale

    local sidebar = create("Frame", {
        Name = "Sidebar",
        BackgroundColor3 = C.Sidebar,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(0, 156, 1, 0),
    }, root)

    create("Frame", {
        BackgroundColor3 = C.Border,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -1, 0, 0),
        Size = UDim2.new(0, 1, 1, 0),
    }, sidebar)

    local logoWrap = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(14, 14),
        Size = UDim2.new(1, -20, 0, 48),
    }, sidebar)

    -- Always create a readable fallback. Some mobile environments return
    -- a custom-asset string but still fail to render the image. In that case
    -- the text remains visible instead of leaving the logo area empty.
    local fallback = text(
        logoWrap,
        "CAT EMPIRE",
        19,
        C.Text,
        Enum.Font.GothamBold
    )
    fallback.Size = UDim2.new(1, 0, 0, 32)

    local logoAsset = ResolveCatEmpireLogo()

    if logoAsset then
        local logoImage = create("ImageLabel", {
            Name = "CAT_EMPIRE_Logo",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = logoAsset,
            ScaleType = Enum.ScaleType.Fit,
            Position = UDim2.fromOffset(0, -2),
            Size = UDim2.new(1, 0, 0, 42),
            ZIndex = fallback.ZIndex + 1,
        }, logoWrap)
    end

    local menuLabel = text(
        sidebar,
        "MENU",
        9,
        C.Muted2,
        Enum.Font.GothamBold
    )
    menuLabel.Position = UDim2.fromOffset(15, 64)
    menuLabel.Size = UDim2.fromOffset(80, 14)

    local sidebarList = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(8, 82),
        Size = UDim2.new(1, -8, 1, -94),
    }, sidebar)

    list(sidebarList, 7, false)

    local content = create("Frame", {
        Name = "Content",
        BackgroundColor3 = C.Content,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(156, 0),
        Size = UDim2.new(1, -156, 1, 0),
    }, root)

    local pages = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(14, 10),
        Size = UDim2.new(1, -28, 1, -18),
    }, content)

    local dragZone = create("Frame", {
        Name = "DragZone",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 28),
        Active = true,
        ZIndex = 40,
    }, root)

    -- External open/close button. It is outside Root so it stays visible.
    local externalToggle = create("TextButton", {
        Name = "CAT_EMPIRE_Toggle",
        BackgroundColor3 = C.Accent,
        BorderSizePixel = 0,
        Text = "CE",
        TextColor3 = C.Text,
        TextSize = 13,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = false,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 12, 0.5, 0),
        Size = UDim2.fromOffset(42, 42),
        ZIndex = 3000,
    }, gui)

    corner(externalToggle, 8)
    stroke(externalToggle, C.AccentSoft, 0.15, 1)

    local window = setmetatable({
        Gui = gui,
        Root = root,
        UIScale = uiScale,
        ScaleValue = defaultScale,
        ExternalToggle = externalToggle,
        Titlebar = dragZone,
        Sidebar = sidebar,
        SidebarList = sidebarList,
        Content = content,
        Pages = pages,
        Tabs = {},
        ActiveTab = nil,
        FullWidth = width,
        FullHeight = height,
        Minimized = false,
        Destroyed = false,
        MinButton = nil,
        _connections = {},
    }, Window)

    window.TitleBar = {
        MaxButton = nil,
        MinButton = nil,
    }

    window:_connect(
        externalToggle.MouseButton1Click,
        function()
            window:ToggleMinimize()
        end
    )

    -- Slight visual feedback for the floating toggle.
    window:_connect(
        externalToggle.MouseEnter,
        function()
            tween(
                externalToggle,
                {BackgroundColor3 = C.AccentSoft},
                0.08
            )
        end
    )

    window:_connect(
        externalToggle.MouseLeave,
        function()
            tween(
                externalToggle,
                {BackgroundColor3 = C.Accent},
                0.08
            )
        end
    )

    local dragging = false
    local dragStart = nil
    local startPos = nil

    window:_connect(
        dragZone.InputBegan,
        function(input)
            if
                input.UserInputType
                    == Enum.UserInputType.MouseButton1
                or input.UserInputType
                    == Enum.UserInputType.Touch
            then
                dragging = true
                dragStart = input.Position
                startPos = root.Position
            end
        end
    )

    window:_connect(
        UserInputService.InputChanged,
        function(input)
            if
                not dragging
                or not dragStart
                or not startPos
            then
                return
            end

            if
                input.UserInputType
                    == Enum.UserInputType.MouseMovement
                or input.UserInputType
                    == Enum.UserInputType.Touch
            then
                local delta =
                    input.Position - dragStart

                root.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            end
        end
    )

    window:_connect(
        UserInputService.InputEnded,
        function(input)
            if
                input.UserInputType
                    == Enum.UserInputType.MouseButton1
                or input.UserInputType
                    == Enum.UserInputType.Touch
            then
                dragging = false
            end
        end
    )

    local minimizeKey =
        config.MinimizeKey
        or Enum.KeyCode.LeftControl

    window:_connect(
        UserInputService.InputBegan,
        function(input, processed)
            if processed then
                return
            end

            if input.KeyCode == minimizeKey then
                window:ToggleMinimize()
            end
        end
    )

    table.insert(self.Windows, window)
    return window
end

function Library:Notify(config)
    config = config or {}

    local latest =
        self.Windows[#self.Windows]

    if
        not latest
        or latest.Destroyed
        or not latest.Gui
    then
        print(
            "[CAT EMPIRE]",
            config.Title or "Notice",
            config.Content or ""
        )
        return
    end

    local toast = create("Frame", {
        BackgroundColor3 = C.Section,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 14),
        Size = UDim2.fromOffset(250, 58),
        ZIndex = 500,
    }, latest.Gui)

    corner(toast, 5)
    stroke(toast, C.AccentDark, 0.1, 1)

    create("Frame", {
        BackgroundColor3 = C.Accent,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 7),
        Size = UDim2.fromOffset(2, 44),
        ZIndex = 501,
    }, toast)

    local titleLabel = text(
        toast,
        config.Title or "CAT EMPIRE",
        10,
        C.Text,
        Enum.Font.GothamMedium
    )

    titleLabel.Position = UDim2.fromOffset(11, 6)
    titleLabel.Size = UDim2.new(1, -20, 0, 18)
    titleLabel.ZIndex = 501

    local body = text(
        toast,
        config.Content or "",
        9,
        C.Muted,
        Enum.Font.Gotham
    )

    body.Position = UDim2.fromOffset(11, 24)
    body.Size = UDim2.new(1, -20, 0, 26)
    body.TextWrapped = true
    body.ZIndex = 501

    task.delay(
        tonumber(config.Duration) or 3,
        function()
            if toast and toast.Parent then
                pcall(function()
                    toast:Destroy()
                end)
            end
        end
    )
end

return Library
