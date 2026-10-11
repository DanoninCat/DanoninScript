return function(ctx)
    local S, LP, Links = ctx.State, ctx.Player, ctx.Links
    local RS = game:GetService("RunService")
    local Game = ctx.Game
    local pickup = Game:FindFirstChild("EggPickup")
    local teleportPlot=Game:FindFirstChild("TeleportToPlot")
    local state = {stage = "idle", target = nil, started = 0, lastError = "", cooldown = 0}
    local speed = 175
    local MAX_STABLE_SPEED = 185
    local lastMountRequest = 0
    local waitingForMountSince = nil
    local flyHeight = 38
    local reserve = 4.5
    local pickupSettle=0.55
    local maxPickupRetries=3
    local conservativeLifetimes = {Common=20,Rare=25,Epic=35,Legendary=30,Mythic=30,Divine=27,Ethereal=21,Secret=20}
    local blocked = {}

    local function now()
        return workspace:GetServerTimeNow()
    end
    local function basket()
        return LP:FindFirstChild("Basket")
    end
    local function count()
        local b = basket()
        return b and #b:GetChildren() or 0
    end
    local function soonestExpiry()
        local b = basket()
        if not b then return nil end
        local deadline
        for _, egg in ipairs(b:GetChildren()) do
            local t = tonumber(egg:GetAttribute("BreakAt"))
            if t and (not deadline or t < deadline) then deadline=t end
        end
        return deadline
    end
    local function root()
        local char = LP.Character
        local part = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not part or not hum or hum.Health <= 0 then return nil end
        return part
    end
    local function plotBase()
        local plot=ctx.GetPlot()
        local data=plot and plot:FindFirstChild("Data")
        local owner=data and data:FindFirstChild("Owner")
        if owner and owner.Value ~= LP then return nil end
        local plate=plot and plot:FindFirstChild("Baseplate")
        return plate and plate:IsA("BasePart") and plate or nil
    end
    local function inside(plate, pos)
        if not plate or typeof(pos)~="Vector3" then return false end
        local localPos=plate.CFrame:PointToObjectSpace(pos)
        return math.abs(localPos.X)<=plate.Size.X/2+1
            and math.abs(localPos.Z)<=plate.Size.Z/2+1
    end
    local function transition(nextStage, message)
        state.stage=nextStage
        state.started=now()
        if message then ctx.Status(message) end
    end
    local function reset(message)
        state.target=nil
        state.risky=false
        state.initialDeadline=nil
        state.arrived=false
        state.pickupRetries=0
        state.pickupLastAt=nil
        state.approachAt=nil
        state.nativeTeleportAt=nil
        state.nativeTeleportRequested=false
        state.nativeTeleportEvaluated=false
        state.receivedDeposit=false
        state.lastApproachTeleport=nil
        state.retryAt=nil
        state.lastRefusal=nil
        state.warnedLate=false
        state.waitingNotified=false
        state.cooldown=now()+0.7
        transition("idle",message)
    end
    local function destination(current)
        local plate=plotBase()
        if not plate then return nil end
        local localPos=plate.CFrame:PointToObjectSpace(current or plate.Position)
        local margin=math.min(5,plate.Size.X*.15,plate.Size.Z*.15)
        local x=math.clamp(localPos.X,-plate.Size.X/2+margin,plate.Size.X/2-margin)
        local z=math.clamp(localPos.Z,-plate.Size.Z/2+margin,plate.Size.Z/2-margin)
        local point=plate.CFrame:PointToWorldSpace(Vector3.new(x,plate.Size.Y/2+4,z))
        return point,plate
    end
    local function findEggPrompt(egg)
        local rendered=workspace:FindFirstChild("RenderedEggs")
        if not rendered then return nil,nil end
        local nearest,nearestPos,score
        for _,model in ipairs(rendered:GetChildren()) do
            if model.Name==egg.Name then
                local prompt=model:FindFirstChildWhichIsA("ProximityPrompt",true)
                if prompt and prompt.Enabled and prompt.Parent then
                    local host=prompt.Parent
                    local pos=(host:IsA("BasePart") and host.Position)
                        or (host:IsA("Attachment") and host.WorldPosition)
                    if pos then
                        local distance=(Vector2.new(egg.Pos.X,egg.Pos.Z)
                            -Vector2.new(pos.X,pos.Z)).Magnitude
                        if not score or distance<score then
                            nearest,nearestPos,score=prompt,pos,distance
                        end
                    end
                end
            end
        end
        return nearest,nearestPos
    end
    local function pickupPosition(egg)
        local prompt,pos=findEggPrompt(egg)
        return pos or egg.Pos,prompt
    end
    local function beginReturn(message)
        state.initialDeadline=soonestExpiry()
        state.nativeTeleportRequested=false
        state.nativeTeleportEvaluated=false
        state.nativeTeleportAt=nil
        transition("return",message)
    end
    local function estimateReturn(egg)
        local plotPoint=destination(egg.Pos)
        if not plotPoint then return math.huge,0 end
        local distance=(Vector2.new(egg.Pos.X,egg.Pos.Z)-Vector2.new(plotPoint.X,plotPoint.Z)).Magnitude
        local speed=math.clamp(tonumber(S.EggFlightSpeed) or 175,60,MAX_STABLE_SPEED)
        local duration=tonumber(egg.BreakSeconds) or conservativeLifetimes[egg.Rarity] or 20
        return distance/speed+reserve, duration
    end
    local function feasible(egg)
        local eta,available=estimateReturn(egg)
        return eta<available,eta,available
    end
    local function eligible(egg)
        local safe,eta,limit=feasible(egg)
        -- Rare priority must not silently disappear behind the ETA filter.
        -- An unsafe trip remains an attempt, not a delivery guarantee.
        local highest=(tonumber(egg.Rank) or 0)>=7
        local attempt=not safe and highest and S.EggPriority=="Rarest"
        return safe or attempt,attempt,eta,limit
    end
    local function finishOrFail()
        local part=root()
        local plate=plotBase()
        local insidePlot=part and plate and inside(plate,part.Position)
        local withinTime=not state.initialDeadline or now()<state.initialDeadline
        if state.receivedDeposit then
            reset("Egg delivery confirmed by server")
        elseif (insidePlot or state.arrived) and withinTime then
            reset("Egg removed at plot; awaiting independent deposit proof")
        else
            if state.risky and state.target then
                blocked[state.target.Id]=now()+60
            end
            reset("Egg removed from basket without confirmed on-time delivery")
        end
    end
    local function moveFlight(dt,target)
        local part=root()
        if not part then return false end
        local here=part.Position
        local delta=target-here
        local distance=delta.Magnitude
        if distance<4 then return true end
        local deadline=soonestExpiry()
        local remaining=deadline and math.max(0.5,deadline-now()-reserve) or 8
        speed=math.clamp(tonumber(S.EggFlightSpeed) or 175,60,MAX_STABLE_SPEED)
        -- Never exceed the measured stable movement threshold, even near expiry.
        local step=math.min(distance,speed*math.clamp(dt,0,0.09))
        if step<=0 then return false end
        local nextPoint=here+delta.Unit*step
        part.CFrame=CFrame.new(nextPoint)
        return step>=distance-0.1
    end
    local function pilot(dt)
        if not S.Running then return end
        if not S.AutoCollectEggs and not S.AutoDeliverEggs then
            if state.stage~="idle" then reset("Egg automation stopped") end
            return
        end
        local t=now()
        if state.stage=="idle" then
            if t<state.cooldown then return end
            if count()>0 then
                beginReturn("Returning carried eggs to plot")
                return
            end
            if not S.AutoCollectEggs then return end
            local candidates=ctx.EggCandidates()
            local first
            for _,egg in ipairs(candidates) do
                if (blocked[egg.Id] or 0)<=t then
                    local allowed,risky,eta,limit=eligible(egg)
                    if allowed then
                        first=egg
                        state.risky=risky
                        if risky then
                            ctx.Status(string.format(
                                "Priority attempt %s: estimated return %.0fs / %.0fs lifetime (delivery at risk)",
                                tostring(egg.Name),eta,limit))
                        end
                        break
                    end
                    blocked[egg.Id]=t+5
                    ctx.Status(string.format("Skipping %s: return %.1fs vs %.1fs lifetime",
                        tostring(egg.Name),eta,limit))
                end
            end
            if not first then return end
            if type(ctx.IsMounted)=="function" and not ctx.IsMounted() then
                waitingForMountSince=waitingForMountSince or t
                if t-waitingForMountSince>7 then
                    blocked[first.Id]=t+10
                    waitingForMountSince=nil
                    state.cooldown=t+2
                    ctx.Status("Mount unavailable; Halloween may resume")
                    return
                end
                if type(ctx.EnsureMount)=="function" and t-lastMountRequest>2.5 then
                    lastMountRequest=t
                    ctx.EnsureMount()
                end
                ctx.Status("Waiting for fastest pet mount")
                return
            end
            waitingForMountSince=nil
            local part=root()
            if not part then return end
            state.target=first
            if workspace.StreamingEnabled then
                task.spawn(function()
                    pcall(function() workspace:RequestStreamAroundAsync(first.Pos) end)
                end)
            end
            state.pickupRetries=0
            state.approachAt=nil
            state.retryAt=nil
            transition("pickup","Travelling to egg: "..first.Name)
        elseif state.stage=="pickup" then
            local target=state.target
            local part=root()
            if not target or not part then reset();return end
            if type(ctx.IsMounted)=="function" and not ctx.IsMounted() then
                transition("waitMount","Mount lost; waiting to remount")
                return
            end
            if t-state.started>6 then
                blocked[target.Id]=t+8
                reset("Egg approach timeout")
                return
            end
            local worldPos,prompt=pickupPosition(target)
            local pickupPos=worldPos+Vector3.new(0,2,0)
            local reach=prompt and math.max(4,prompt.MaxActivationDistance-1) or 6
            if (part.Position-pickupPos).Magnitude>reach then
                if t-(state.lastApproachTeleport or 0)>.65 then
                    state.lastApproachTeleport=t
                    part.CFrame=CFrame.new(pickupPos)
                end
                state.approachAt=nil
                return
            end
            state.approachAt=state.approachAt or t
            if t-state.approachAt<pickupSettle+math.clamp(
                tonumber(S.EggHoldSeconds) or 0,0,5) then return end
            if state.retryAt and t<state.retryAt then return end
            if not pickup or not pickup:IsA("RemoteEvent") then
                reset("EggPickup remote unavailable")
                return
            end
            if not prompt and workspace.StreamingEnabled
                and t-state.started<1.25 then
                return
            end
            state.pickupRetries=(state.pickupRetries or 0)+1
            state.pickupLastAt=t
            local fired=false
            if prompt and prompt.Enabled and type(fireproximityprompt)=="function" then
                fired=pcall(fireproximityprompt,prompt)
            end
            if not fired then pickup:FireServer(target.Id) end
            transition("await","Collecting "..target.Name.." (attempt "..state.pickupRetries..")")
        elseif state.stage=="waitMount" then
            if type(ctx.IsMounted)~="function" or ctx.IsMounted() then
                transition("pickup","Mount restored")
            elseif t-state.started>5 then
                reset("Mount unavailable")
            elseif type(ctx.EnsureMount)=="function" and t-lastMountRequest>2.5 then
                lastMountRequest=t
                ctx.EnsureMount()
            end
        elseif state.stage=="await" then
            if count()>0 then
                beginReturn("Egg acquired; returning immediately")
                return
            end
            if t-state.started>1.7 then
                if state.target and state.pickupRetries<maxPickupRetries then
                    state.retryAt=t+.35
                    state.approachAt=nil
                    transition("pickup","Retrying egg pickup at the same target")
                else
                    if state.target then blocked[state.target.Id]=t+15 end
                    reset("Egg pickup not confirmed after retries")
                end
            end
        elseif state.stage=="awaitBasket" then
            if count()>0 then
                beginReturn("Egg acquired; returning immediately")
            elseif t-state.started>2.8 then
                if state.target then blocked[state.target.Id]=t+10 end
                reset("Pickup acknowledged, but basket did not replicate")
            end
        elseif state.stage=="return" then
            if not S.AutoCollectEggs and not S.AutoDeliverEggs then
                reset("Egg delivery paused");return
            end
            if count()==0 then finishOrFail();return end
            local part=root()
            local target,plate=destination(part and part.Position)
            if not part or not target then
                if t-state.started>5 then reset("Plot not available") end
                return
            end
            if teleportPlot and teleportPlot:IsA("RemoteEvent")
                and not state.nativeTeleportRequested then
                state.nativeTeleportRequested=true
                state.nativeTeleportAt=t
                pcall(function() teleportPlot:FireServer() end)
                ctx.Status("Checking native plot teleport while carrying egg")
                return
            end
            if state.nativeTeleportAt and t-state.nativeTeleportAt<.45 then return end
            if state.nativeTeleportRequested and not state.nativeTeleportEvaluated then
                state.nativeTeleportEvaluated=true
                if not inside(plate,part.Position) then
                    local remaining=(soonestExpiry() or t)-t
                    local speedNow=math.clamp(tonumber(S.EggFlightSpeed) or 175,60,MAX_STABLE_SPEED)
                    local estimated=(Vector2.new(part.Position.X,part.Position.Z)
                        -Vector2.new(target.X,target.Z)).Magnitude/speedNow
                    ctx.Status(string.format(
                        "Native plot teleport not confirmed; air return %.0fs, remaining %.0fs",
                        estimated,remaining))
                end
            end
            local expires=soonestExpiry()
            if expires and t>=expires-0.2 and not state.warnedLate then
                state.warnedLate=true
                ctx.Status("Egg deadline nearly exhausted; maintaining controlled return")
            end
            if inside(plate,part.Position) then
                state.arrived=true
                transition("verify","Plot reached; awaiting server delivery")
                return
            end
            local direct=Vector3.new(target.X,math.max(part.Position.Y,target.Y+18),target.Z)
            moveFlight(dt,direct)
            if inside(plate,part.Position) then
                state.arrived=true
                transition("verify","Plot arrival detected")
            end
        elseif state.stage=="verify" then
            if count()==0 then finishOrFail();return end
            local part=root()
            local goal,plate=destination(part and part.Position)
            if part and goal and inside(plate,part.Position) then
                if part.Position.Y>goal.Y+8 then
                    moveFlight(dt,goal)
                end
            elseif part and goal then
                transition("return","Re-aligning plot position")
            end
            if state.initialDeadline and t>state.initialDeadline+1.5 then
                if state.risky and state.target then blocked[state.target.Id]=t+60 end
                reset("Egg delivery deadline expired without server confirmation")
            elseif t-state.started>5 and not state.waitingNotified then
                state.waitingNotified=true
                ctx.Status("Inside plot; waiting for server to confirm delivery")
            end
        elseif state.stage=="confirm" then
            if count()==0 then finishOrFail();return end
            if t-state.started>2 then reset("Delivery not confirmed by server") end
        end
    end

    if pickup and pickup:IsA("RemoteEvent") then
        Links[#Links+1]=pickup.OnClientEvent:Connect(function(result, name, id)
            if result=="Deposited" then
                if state.stage=="return" or state.stage=="verify" or state.stage=="confirm" then
                    state.receivedDeposit=true
                    ctx.Status("Server acknowledged egg deposit")
                    if count()==0 then finishOrFail() end
                end
                return
            end
            if state.stage~="await" then return end
            if id~=nil and state.target and tostring(id)~=tostring(state.target.Id) then return end
            if result=="PickedUp" then
                transition("awaitBasket","Pickup acknowledged: "..tostring(name or "egg"))
            elseif result=="Refused" then
                state.lastRefusal=tostring(name or "refused")
                if state.target and state.pickupRetries<maxPickupRetries then
                    state.retryAt=now()+.5
                    state.approachAt=nil
                    transition("pickup","Pickup refused ("..state.lastRefusal.."); repositioning")
                else
                    if state.target then blocked[state.target.Id]=now()+15 end
                    reset("Pickup refused: "..state.lastRefusal)
                end
            elseif result=="BasketFull" then
                if count()>0 then
                    beginReturn("Basket full; delivering already carried eggs")
                else
                    reset("Basket full; waiting for inventory")
                end
            end
        end)
    end

    Links[#Links+1]=RS.Heartbeat:Connect(function(dt)
        local ok,err=pcall(pilot,dt)
        if not ok then
            state.lastError=tostring(err)
            S.LastError="EggTransport: "..tostring(err)
            reset("Egg transport recovered from error")
        end
    end)
    return {
        IsBusy=function()
            return (S.AutoCollectEggs or S.AutoDeliverEggs) and state.stage~="idle"
        end,
        State=function() return state.stage end,
        SetSpeed=function(v) speed=math.clamp(tonumber(v) or 175,60,MAX_STABLE_SPEED) end,
        WantsPriority=function()
            if state.stage~="idle" then return true end
            if count()>0 then return S.AutoDeliverEggs or S.AutoCollectEggs end
            if not S.AutoCollectEggs then return false end
            local t=now()
            for _,egg in ipairs(ctx.EggCandidates()) do
                if (blocked[egg.Id] or 0)<=t and eligible(egg) then return true end
            end
            return false
        end,
    }
end