return function(ctx)
    local S, LP, Links = ctx.State, ctx.Player, ctx.Links
    local RS = game:GetService("RunService")
    local Game = ctx.Game
    local pickup = Game:FindFirstChild("EggPickup")
    local state = {stage = "idle", target = nil, started = 0, lastError = "", cooldown = 0}
    local speed = 230
    local flyHeight = 38
    local reserve = 2.5
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
        state.cooldown=now()+0.6
        transition("idle",message)
    end
    local function destination()
        local plate=plotBase()
        if not plate then return nil end
        return plate.Position+Vector3.new(0,math.max(5,plate.Size.Y/2+5),0),plate
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
        local targetSpeed=math.clamp(distance/remaining*1.4,70,450)
        local actualSpeed=math.max(speed,targetSpeed)
        local step=math.min(distance,actualSpeed*math.clamp(dt,0,0.09))
        if step<=0 then return false end
        local nextPoint=here+delta.Unit*step
        part.CFrame=CFrame.new(nextPoint)
        return step>=distance-0.1
    end
    local function pilot(dt)
        if not S.Running then return end
        if not S.AutoCollectEggs then
            if state.stage~="idle" then reset("Auto Collect Eggs stopped") end
            return
        end
        local t=now()
        if state.stage=="idle" then
            if t<state.cooldown then return end
            if count()>0 then
                transition("return","Returning carried eggs to plot")
                return
            end
            local candidates=ctx.EggCandidates()
            local first=candidates[1]
            if not first or (blocked[first.Id] or 0)>t then return end
            local part=root()
            if not part then return end
            state.target=first
            transition("pickup","Travelling to egg: "..first.Name)
        elseif state.stage=="pickup" then
            local target=state.target
            local part=root()
            if not target or not part then reset();return end
            if t-state.started>6 then
                blocked[target.Id]=t+8
                reset("Egg approach timeout")
                return
            end
            local pickupPos=target.Pos+Vector3.new(0,3,0)
            if (part.Position-pickupPos).Magnitude>10 then
                part.CFrame=CFrame.new(pickupPos)
            end
            if pickup and pickup:IsA("RemoteEvent") then
                pickup:FireServer(target.Id)
                transition("await","Waiting for egg pickup confirmation")
            else
                reset("EggPickup remote unavailable")
            end
        elseif state.stage=="await" then
            if count()>0 then
                transition("return","Egg acquired; airborne return started")
                return
            end
            if t-state.started>3.0 then
                if state.target then blocked[state.target.Id]=t+8 end
                reset("Egg not confirmed by server")
            end
        elseif state.stage=="awaitBasket" then
            if count()>0 then
                transition("return","Returning acquired egg")
            elseif t-state.started>1.8 then
                reset("Waiting for egg replication timed out")
            end
        elseif state.stage=="return" then
            if count()==0 then reset("Egg delivered");return end
            local part=root()
            local target,plate=destination()
            if not part or not target then
                if t-state.started>5 then reset("Plot not available") end
                return
            end
            if soonestExpiry() and t>=soonestExpiry()-0.2 then
                transition("verify","Egg deadline reached")
                return
            end
            if inside(plate,part.Position) then
                transition("verify","Plot reached; awaiting server delivery")
                return
            end
            local high=Vector3.new(target.X,math.max(part.Position.Y,target.Y+flyHeight),target.Z)
            moveFlight(dt,high)
            if inside(plate,part.Position) then
                transition("verify","Plot arrival detected")
            end
        elseif state.stage=="verify" then
            if count()==0 then reset("Egg delivery confirmed");return end
            local part=root()
            local goal,plate=destination()
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
            if count()==0 then reset("Egg delivery confirmed");return end
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
            return S.AutoCollectEggs and state.stage~="idle"
        end,
        State=function() return state.stage end,
        SetSpeed=function(v) speed=math.clamp(tonumber(v) or 230,60,500) end,
    }
end