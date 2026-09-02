-- ============================================================
-- CAT EMPIRE UI
-- Custom flat black/purple UI library for DanoninScript.
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
    Sidebar = Color3.fromRGB(10, 10, 12),
    Content = Color3.fromRGB(12, 12, 15),
    Section = Color3.fromRGB(15, 15, 18),
    Row = Color3.fromRGB(19, 19, 23),
    RowHover = Color3.fromRGB(23, 21, 29),
    Border = Color3.fromRGB(37, 34, 44),
    BorderSoft = Color3.fromRGB(29, 27, 34),
    Accent = Color3.fromRGB(151, 70, 255),
    AccentDark = Color3.fromRGB(92, 36, 160),
    AccentSoft = Color3.fromRGB(49, 29, 72),
    Text = Color3.fromRGB(235, 235, 239),
    Muted = Color3.fromRGB(134, 132, 143),
    Muted2 = Color3.fromRGB(93, 91, 101),
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

    self.Sidebar.Visible = not self.Minimized
    self.Content.Visible = not self.Minimized

    local targetHeight = self.Minimized and 32 or self.FullHeight
    self.Root.Size = UDim2.fromOffset(self.FullWidth, targetHeight)
    self.MinButton.Text = self.Minimized and "+" or "—"
end

function Window:ToggleMinimize()
    self:_setMinimized(not self.Minimized)
end

function Window:Destroy()
    if self.Destroyed then
        return
    end

    self.Destroyed = true

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

        candidate.Page.Visible = active
        candidate.Indicator.Visible = active
        candidate.Button.BackgroundColor3 = active and C.AccentSoft or C.Sidebar
        candidate.Button.TextColor3 = active and C.Text or C.Muted
        candidate.IconLabel.TextColor3 = active and C.Accent or C.Muted
    end

    self.ActiveTab = tab
end

local ICONS = {
    crosshair = "◉",
    eye = "◌",
    ["flask-conical"] = "◇",
    cloud = "○",
    settings = "⚙",
}

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
        BackgroundColor3 = C.Section,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = self._nextOrder,
    }, self._scroll)

    self._nextOrder += 1

    corner(section, 5)
    stroke(section, C.Border, 0.16, 1)
    padding(section, 8, 8, 7, 8)
    list(section, 5, false)

    if titleValue and titleValue ~= "" then
        local titleLabel = text(
            section,
            titleValue,
            10,
            C.Muted,
            Enum.Font.GothamMedium
        )

        titleLabel.Size = UDim2.new(1, 0, 0, 18)
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

    list(holder, 4, false)

    self._currentSection = holder
    return section
end

local function makeRow(container, height)
    local holder = container:_ensureSection()

    local row = create("Frame", {
        BackgroundColor3 = C.Row,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, height),
    }, holder)

    corner(row, 4)
    stroke(row, C.BorderSoft, 0.32, 1)

    return row
end

function Container:AddToggle(id, config)
    config = config or {}

    local row = makeRow(self, 33)

    local titleLabel = text(
        row,
        config.Title or id,
        10,
        C.Text,
        Enum.Font.Gotham
    )

    titleLabel.Position = UDim2.fromOffset(9, 0)
    titleLabel.Size = UDim2.new(1, -58, 1, 0)

    local switch = create("Frame", {
        BackgroundColor3 = C.Border,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(34, 18),
        Position = UDim2.new(1, -43, 0.5, -9),
    }, row)

    corner(switch, 9)

    local knob = create("Frame", {
        BackgroundColor3 = C.Muted,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(12, 12),
        Position = UDim2.fromOffset(3, 3),
    }, switch)

    corner(knob, 6)

    local hit = buttonBase(row)
    hit.Size = UDim2.fromScale(1, 1)
    hit.ZIndex = 5

    local option = Option.new(id, config.Default == true)

    option._render = function(value)
        local enabled = value == true

        tween(
            switch,
            {
                BackgroundColor3 = enabled and C.AccentDark or C.Border,
            },
            0.1
        )

        tween(
            knob,
            {
                BackgroundColor3 = enabled and C.Accent or C.Muted,
                Position = enabled
                    and UDim2.fromOffset(19, 3)
                    or UDim2.fromOffset(3, 3),
            },
            0.1
        )
    end

    option._render(option.Value)

    self._window:_connect(hit.MouseButton1Click, function()
        option:SetValue(not option.Value)
    end)

    self._window:_connect(hit.MouseEnter, function()
        tween(row, {BackgroundColor3 = C.RowHover}, 0.08)
    end)

    self._window:_connect(hit.MouseLeave, function()
        tween(row, {BackgroundColor3 = C.Row}, 0.08)
    end)

    return option
end

function Container:AddSlider(id, config)
    config = config or {}

    local minValue = tonumber(config.Min) or 0
    local maxValue = tonumber(config.Max) or 100
    local rounding = tonumber(config.Rounding) or 0
    local defaultValue = tonumber(config.Default) or minValue

    local row = makeRow(self, 53)

    local titleLabel = text(
        row,
        config.Title or id,
        10,
        C.Text,
        Enum.Font.Gotham
    )

    titleLabel.Position = UDim2.fromOffset(9, 4)
    titleLabel.Size = UDim2.new(1, -72, 0, 18)

    local valueLabel = text(
        row,
        "",
        10,
        C.Muted,
        Enum.Font.Code,
        Enum.TextXAlignment.Right
    )

    valueLabel.Position = UDim2.new(1, -67, 0, 4)
    valueLabel.Size = UDim2.fromOffset(58, 18)

    local track = create("Frame", {
        BackgroundColor3 = Color3.fromRGB(34, 32, 39),
        BorderSizePixel = 0,
        Position = UDim2.new(0, 9, 1, -18),
        Size = UDim2.new(1, -18, 0, 3),
    }, row)

    corner(track, 2)

    local fill = create("Frame", {
        BackgroundColor3 = C.Accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 1, 0),
    }, track)

    corner(fill, 2)

    local knob = create("Frame", {
        BackgroundColor3 = C.Accent,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(9, 9),
    }, track)

    corner(knob, 5)

    local sliderHit = buttonBase(row)
    sliderHit.Position = UDim2.new(0, 4, 1, -28)
    sliderHit.Size = UDim2.new(1, -8, 0, 24)
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
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = C.Accent,
        ScrollBarImageTransparency = 0.35,
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
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = C.Accent,
            ScrollBarImageTransparency = 0.45,
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
        BorderSizePixel = 0,
        Text = "     " .. titleValue,
        TextColor3 = C.Muted,
        TextSize = 10,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = false,
        Size = UDim2.new(1, -12, 0, 34),
    }, self.SidebarList)

    corner(sidebarButton, 3)

    local indicator = create("Frame", {
        BackgroundColor3 = C.Accent,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0.5, -8),
        Size = UDim2.fromOffset(2, 16),
        Visible = false,
    }, sidebarButton)

    corner(indicator, 1)

    local iconLabel = text(
        sidebarButton,
        iconValue,
        12,
        C.Muted,
        Enum.Font.Gotham,
        Enum.TextXAlignment.Center
    )

    iconLabel.Position = UDim2.fromOffset(8, 0)
    iconLabel.Size = UDim2.fromOffset(18, 34)

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

    local pageTitle = text(
        pageHeader,
        titleValue,
        20,
        C.Text,
        Enum.Font.GothamMedium
    )

    pageTitle.Position = UDim2.fromOffset(8, 4)
    pageTitle.Size = UDim2.new(1, -16, 0, 30)

    local body = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 42),
        Size = UDim2.new(1, 0, 1, -42),
    }, page)

    tab.Button = sidebarButton
    tab.Indicator = indicator
    tab.IconLabel = iconLabel
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
                        BackgroundColor3 =
                            Color3.fromRGB(
                                15,
                                14,
                                18
                            ),
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
                        BackgroundColor3 =
                            C.Sidebar,
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
        or 590

    local height =
        (
            config.Size
            and config.Size.Y
            and config.Size.Y.Offset
        )
        or 390

    width = math.max(width, 560)
    height = math.max(height, 350)

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
        BackgroundTransparency = 0.02,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(width, height),
        ClipsDescendants = true,
    }, gui)

    corner(root, 4)

    stroke(
        root,
        Color3.fromRGB(46, 39, 57),
        0.06,
        1
    )

    local titlebar = create("Frame", {
        Name = "TitleBar",
        BackgroundColor3 = Color3.fromRGB(9, 9, 11),
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 32),
    }, root)

    local titleLabel = text(
        titlebar,
        config.Title or "CAT EMPIRE",
        10,
        C.Text,
        Enum.Font.GothamMedium
    )

    titleLabel.Position = UDim2.fromOffset(12, 0)
    titleLabel.Size = UDim2.new(1, -94, 1, 0)

    local minButton = create("TextButton", {
        Name = "Minimize",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "—",
        TextColor3 = C.Muted,
        TextSize = 13,
        Font = Enum.Font.Gotham,
        AutoButtonColor = false,
        Size = UDim2.fromOffset(32, 22),
        Position = UDim2.new(1, -68, 0, 5),
    }, titlebar)

    local closeButton = create("TextButton", {
        Name = "Close",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "×",
        TextColor3 = C.Muted,
        TextSize = 14,
        Font = Enum.Font.Gotham,
        AutoButtonColor = false,
        Size = UDim2.fromOffset(32, 22),
        Position = UDim2.new(1, -36, 0, 5),
    }, titlebar)

    local sidebar = create("Frame", {
        Name = "Sidebar",
        BackgroundColor3 = C.Sidebar,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 32),
        Size = UDim2.new(0, 118, 1, -32),
    }, root)

    create("Frame", {
        BackgroundColor3 = C.BorderSoft,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -1, 0, 0),
        Size = UDim2.new(0, 1, 1, 0),
    }, sidebar)

    local sidebarList = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(6, 9),
        Size = UDim2.new(1, -6, 1, -18),
    }, sidebar)

    list(sidebarList, 3, false)

    local content = create("Frame", {
        Name = "Content",
        BackgroundColor3 = C.Content,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(118, 32),
        Size = UDim2.new(1, -118, 1, -32),
    }, root)

    local pages = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(8, 6),
        Size = UDim2.new(1, -16, 1, -12),
    }, content)

    local window = setmetatable({
        Gui = gui,
        Root = root,
        Titlebar = titlebar,
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
        MinButton = minButton,
        _connections = {},
    }, Window)

    -- Compatibility for MurderDuel.lua's optional title-bar hook.
    window.TitleBar = {
        MaxButton = nil,
        MinButton = {
            Frame = minButton,
        },
    }

    -- Drag only by the compact title bar.
    local dragging = false
    local dragStart = nil
    local startPos = nil

    window:_connect(
        titlebar.InputBegan,
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

    window:_connect(
        minButton.MouseButton1Click,
        function()
            window:ToggleMinimize()
        end
    )

    window:_connect(
        closeButton.MouseButton1Click,
        function()
            window:Destroy()
        end
    )

    window:_connect(
        minButton.MouseEnter,
        function()
            minButton.TextColor3 = C.Text
        end
    )

    window:_connect(
        minButton.MouseLeave,
        function()
            minButton.TextColor3 = C.Muted
        end
    )

    window:_connect(
        closeButton.MouseEnter,
        function()
            closeButton.TextColor3 = C.Accent
        end
    )

    window:_connect(
        closeButton.MouseLeave,
        function()
            closeButton.TextColor3 = C.Muted
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
