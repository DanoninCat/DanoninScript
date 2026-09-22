-- Re Adventures V2 entry point.
-- Receives the embedded Core/UI modules from the Loader payload.

return function(Core, UI)
    if game.PlaceId ~= 138271828389486 and game.PlaceId ~= 94823097601547 then
        return
    end

    local env = (getgenv and getgenv()) or _G
    local fluentSource = env["__CE_F_91A7"]

    if type(fluentSource) ~= "string" or fluentSource == "" then
        warn("[ReAdventuresV2] Embedded Fluent source is unavailable.")
        return
    end

    local okFluent, Fluent = pcall(function()
        return loadstring(fluentSource)()
    end)

    if not okFluent or not Fluent then
        warn("[ReAdventuresV2] Could not initialize Fluent.")
        return
    end

    local app = Core.new({
        recorder = {
            snapshotInterval = 1,
            maxSnapshots = 7200,
        },
    })

    app:Start()

    local Window = Fluent:CreateWindow({
        Title = "Cat Empire",
        SubTitle = "Re Adventures V2",
        TabWidth = 160,
        Size = UDim2.fromOffset(720, 480),
        Acrylic = true,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightControl,
    })

    -- Runtime/status stays outside the Macros area.
    local StatusTab = Window:AddTab({
        Title = "Status",
        Icon = "activity",
    })

    StatusTab:AddSection("Current Match")

    local mapParagraph = StatusTab:AddParagraph({
        Title = "Map",
        Content = "Detecting...",
    })

    local matchParagraph = StatusTab:AddParagraph({
        Title = "Match",
        Content = "Detecting...",
    })

    local unitsParagraph = StatusTab:AddParagraph({
        Title = "Runtime",
        Content = "Detecting...",
    })

    local function setDesc(control, value)
        pcall(function()
            control:SetDesc(tostring(value))
        end)
    end

    local function refreshStatus()
        local state = app:GetState()

        setDesc(
            mapParagraph,
            string.format(
                "%s / %s\nPlaceId: %s",
                tostring(state.map.area or (state.map.isLobby and "lobby") or "unknown"),
                tostring(state.map.level or "unknown"),
                tostring(state.placeId)
            )
        )

        setDesc(
            matchParagraph,
            string.format(
                "Phase: %s\nWave: %s | Time: %s\nMoney: %s | Base Life: %s/%s",
                tostring(state.match.phase),
                tostring(state.match.wave),
                tostring(state.match.waveTime),
                tostring(state.player.money or "?"),
                tostring(state.player.baseLife or "?"),
                tostring(state.player.baseMaxLife or "?")
            )
        )

        setDesc(
            unitsParagraph,
            string.format(
                "Units: %s | Enemies: %s\nStarted: %s | Finished: %s",
                tostring(state.counters.unitsPlaced),
                tostring(state.counters.enemiesAlive),
                tostring(state.match.started),
                tostring(state.match.finished)
            )
        )
    end

    StatusTab:AddButton({
        Title = "Refresh Status",
        Callback = refreshStatus,
    })

    -- Dedicated area requested by the user.
    local macrosHandle = UI.AttachMacrosArea(Window, app, Fluent)

    app:On("waveChanged", refreshStatus)
    app:On("moneyChanged", refreshStatus)
    app:On("baseLifeChanged", refreshStatus)
    app:On("matchPhaseChanged", refreshStatus)
    app:On("mapChanged", refreshStatus)
    app:On("unitAdded", refreshStatus)
    app:On("unitRemoved", refreshStatus)
    app:On("enemyAdded", refreshStatus)
    app:On("enemyRemoved", refreshStatus)

    refreshStatus()

    env.__RE_ADVENTURES_V2 = {
        App = app,
        Window = Window,
        Macros = macrosHandle,
        Version = Core.VERSION,
    }

    return env.__RE_ADVENTURES_V2
end
