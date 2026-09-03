from pathlib import Path

p = Path('Games/MurderDuel.lua')
s = p.read_text(encoding='utf-8')

old_loop = '''local AimLoopRunning = false

local function AimLoop()
    if AimLoopRunning then return end
    AimLoopRunning = true

    while not UIClosed do
        RunService.RenderStepped:Wait()

        if not State.Aim.Enabled then
            TargetData.Current = nil
            TargetData.Position = nil
            break
        end

        local target = GetClosestTarget()
        local myChar = LocalPlayer.Character

        if target and myChar then
            local targetPosition = GetHeadPosition(target)
            local myRoot = GetTargetPart(myChar)
            local screenPos, onScreen = ProjectToScreen(targetPosition)

            TargetData.Current = target
            TargetData.Position = targetPosition
            TargetData.Visible = onScreen

            if myRoot then
                TargetData.Distance = GetDistance(myRoot.Position, targetPosition)
            end

            if screenPos then
                local mousePos = Vector2.new(Mouse.X, Mouse.Y)
                TargetData.Angle = (
                    Vector2.new(screenPos.X, screenPos.Y) - mousePos
                ).Magnitude
            end

            -- Mantém o comportamento que já existia no script.
            local camera = GetCamera()

            if State.Aim.Silent and camera then
                local tool = myChar:FindFirstChildOfClass("Tool")
                if tool then
                    local direction = (targetPosition - camera.CFrame.Position).Unit
                    camera.CFrame = CFrame.new(
                        camera.CFrame.Position,
                        camera.CFrame.Position + direction
                    )
                end
            elseif State.Aim.Assist and screenPos and onScreen then
                local mousePos = Vector2.new(Mouse.X, Mouse.Y)
                local targetScreen = Vector2.new(screenPos.X, screenPos.Y)
                local diff = targetScreen - mousePos
                local strength = State.Aim.Strength * State.Aim.Smoothing
                local newMousePos = mousePos + diff * strength

                pcall(function()
                    Mouse.X = newMousePos.X
                    Mouse.Y = newMousePos.Y
                end)
            end
        else
            TargetData.Current = nil
            TargetData.Position = nil
            TargetData.Visible = false
        end
    end

    AimLoopRunning = false
end'''

new_loop = '''local CombatLoopRunning = false

local function IsCombatTrackingEnabled()
    return State.Aim.Enabled
        or State.Aim.Silent
        or State.Aim.Assist
end

local function ResetTargetData()
    TargetData.Current = nil
    TargetData.Position = nil
    TargetData.Distance = 0
    TargetData.Angle = 0
    TargetData.Visible = false
end

local function CombatTrackingLoop()
    if CombatLoopRunning then
        return
    end

    CombatLoopRunning = true

    while not UIClosed do
        RunService.RenderStepped:Wait()

        if not IsCombatTrackingEnabled() then
            ResetTargetData()
            break
        end

        local target = GetClosestTarget()
        local myChar = LocalPlayer.Character

        if target and myChar then
            local targetPosition = GetHeadPosition(target)
            local myRoot = GetTargetPart(myChar)
            local screenPos, onScreen = ProjectToScreen(targetPosition)

            TargetData.Current = target
            TargetData.Position = targetPosition
            TargetData.Visible = onScreen

            if myRoot then
                TargetData.Distance = GetDistance(
                    myRoot.Position,
                    targetPosition
                )
            else
                TargetData.Distance = 0
            end

            if screenPos then
                local mousePos = Vector2.new(Mouse.X, Mouse.Y)
                TargetData.Angle = (
                    Vector2.new(screenPos.X, screenPos.Y)
                    - mousePos
                ).Magnitude
            else
                TargetData.Angle = 0
            end
        else
            ResetTargetData()
        end
    end

    CombatLoopRunning = false
end

local function RefreshCombatTracking()
    if IsCombatTrackingEnabled() then
        if not CombatLoopRunning then
            task.spawn(CombatTrackingLoop)
        end
    else
        ResetTargetData()
    end
end'''

if s.count(old_loop) != 1:
    raise SystemExit('Expected exactly one legacy AimLoop block.')
s = s.replace(old_loop, new_loop, 1)

replacements = [
('''    Fluent.Options.AimbotEnabled:OnChanged(function(value)
        State.Aim.Enabled = value

        if value then
            task.spawn(AimLoop)
        else
            TargetData.Current = nil
            TargetData.Position = nil
            TargetData.Distance = 0
            TargetData.Angle = 0
            TargetData.Visible = false
        end
    end)''', '''    Fluent.Options.AimbotEnabled:OnChanged(function(value)
        State.Aim.Enabled = value
        RefreshCombatTracking()
    end)'''),
('''    Fluent.Options.AimAssist:OnChanged(function(value)
        State.Aim.Assist = value

        if value and Fluent.Options.SilentAim then
            State.Aim.Silent = false
            Fluent.Options.SilentAim:SetValue(false)
        end
    end)''', '''    Fluent.Options.AimAssist:OnChanged(function(value)
        State.Aim.Assist = value
        RefreshCombatTracking()
    end)'''),
('''    Fluent.Options.SilentAim:OnChanged(function(value)
        State.Aim.Silent = value

        if value and Fluent.Options.AimAssist then
            State.Aim.Assist = false
            Fluent.Options.AimAssist:SetValue(false)
        end
    end)''', '''    Fluent.Options.SilentAim:OnChanged(function(value)
        State.Aim.Silent = value
        RefreshCombatTracking()
    end)'''),
]

for old, new in replacements:
    if s.count(old) != 1:
        raise SystemExit('Expected exactly one legacy combat callback block.')
    s = s.replace(old, new, 1)

p.write_text(s, encoding='utf-8')
