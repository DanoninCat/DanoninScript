return function(ctx)
    local S, LP, Links = ctx.State, ctx.Player, ctx.Links
    local RS = game:GetService("RunService")
    local Game = ctx.Game
    local pickup = Game:FindFirstChild("EggPickup")
    local state = {stage = "idle", target = nil, started = 0, lastError = "", cooldown = 0}
    local speed = 175
    local MAX_STABLE_SPEED = 185
    local lastMountRequest = 0
    local waitingForMountSince = nil
    local flyHeight = 38
    local reserve = 4.5
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
        state.initialDeadline=nil
        state.arrived=false
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
    local function finishOrFail()
        local part=root()
        local plate=plotBase()
        local insidePlot=part and plate and inside(plate,part.Position)
        local withinTime=not state.initialDeadline or now()<state.initialDeadline
        if (insidePlot or state.arrived) and withinTime then
            reset("Egg delivery confirmed at plot")
        else
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
                state.initialDeadline=soonestExpiry()
                transition("return","Returning carried eggs to plot")
                return
            end
            if not S.AutoCollectEggs then return end
            local candidates=ctx.EggCandidates()
            local first
            for _,egg in ipairs(candidates) do
                if (blocked[egg.Id] or 0)<=t then
                    local ok,eta,limit=feasible(egg)
                    if ok then first=egg;break end
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
            local pickupPos=target.Pos+Vector3.new(0,3,0)
            if (part.Position-pickupPos).Magnitude>10 then
                part.CFrame=CFrame.new(pickupPos)
            end
            if t-state.started < (tonumber(S.EggHoldSeconds) or 0) then return end
            if pickup and pickup:IsA("RemoteEvent") then
                pickup:FireServer(target.Id)
                transition("await","Waiting for egg pickup confirmation")
            else
                reset("EggPickup remote unavailable")
            end
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
                state.initialDeadline=soonestExpiry()
                transition("return","Egg acquired; airborne return started")
                return
            end
            if t-state.started>3.0 then
                if state.target then blocked[state.target.Id]=t+8 end
                reset("Egg not confirmed by server")
            end
        elseif state.stage=="awaitBasket" then
            if count()>0 then
                state.initialDeadline=soonestExpiry()
                transition("return","Returning acquired egg")
            elseif t-state.started>1.8 then
                reset("Waiting for egg replication timed out")
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
            if soonestExpiry() and t>=soonestExpiry()-0.2 then
                transition("verify","Egg deadline reached")
                return
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
            if t-state.started>5 then
                if count()>0 and part and goal then
                    local p=goal+Vector3.new(0,1,0)
                    part.CFrame=CFrame.new(p)
                    transition("confirm","Final delivery check")
                else
                    reset("Egg cycle finished")
                end
            end
        elseif state.stage=="confirm" then
            if count()==0 then finishOrFail();return end
            if t-state.started>2 then reset("Delivery not confirmed by server") end
        end
    end

    if pickup and pickup:IsA("RemoteEvent") then
        Links[#Links+1]=pickup.OnClientEvent:Connect(function(result, name, id)
            if state.stage~="await" then return end
            if id~=nil and state.target and tostring(id)~=tostring(state.target.Id) then return end
            if result=="PickedUp" then
                transition("awaitBasket","Pickup acknowledged: "..tostring(name or "egg"))
            elseif result=="Refused" or result=="BasketFull" then
                if state.target then blocked[state.target.Id]=now()+9 end
                reset("Pickup refused: "..tostring(result))
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
                if (blocked[egg.Id] or 0)<=t and feasible(egg) then return true end
            end
            return false
        end,
    }
end