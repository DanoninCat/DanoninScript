return function(ctx)
    local S, LP, CS = ctx.S, ctx.Player, ctx.CS
    local ev=ctx.Config.HellEventConfig or {}
    local essence=ctx.Config.HellEssenceConfig or {}
    local bossCfg=ctx.Config.HellBossConfig or {}
    local batCfg=ctx.Config.BatConfig or {}
    local axeCfg=ctx.Config.PickaxeConfig or {}
    local pickaxe=ctx.Controllers.PickaxeController
    local bat=ctx.Controllers.BatController
    local gatherAttr=essence.GatherAttribute or "HellGathering"
    local amountAttr=essence.EssenceAttribute or "HellEssence"
    local goalAttr=essence.GoalAttribute or "HellEssenceGoal"
    local eggTag=essence.EggTag or "HellEssenceEgg"
    local lastHit=0
    local function stage(value)
        S.HellStep=value
    end
    local function portal()
        if type(ev.FindPortal)=="function" then
            local ok,model=pcall(ev.FindPortal)
            if ok and typeof(model)=="Instance" then return model end
        end
        local obj=workspace
        for _,child in ipairs((ev.Portal and ev.Portal.Path) or {"Build","ZoneBuilds","Zone7","JoinHell"}) do
            obj=obj and obj:FindFirstChild(child)
        end
        return obj
    end
    local function join()
        if workspace:GetAttribute(ev.JoinableAttribute or "HellJoinable")~=true then
            stage("Waiting for Hell Event (closed)")
            return
        end
        local obj=portal()
        local tp=obj and obj:FindFirstChild((ev.Portal and ev.Portal.TouchPart) or "TP",true)
        local pos=tp and ctx.Position(tp)
        if not pos then
            stage("Hell portal not found")
            return
        end
        local root=ctx.Root()
        if not root then return end
        stage("Entering portal")
        if (root.Position-pos).Magnitude>5 then
            ctx.Move("Hell",pos,0)
            return
        end
        local joinRemote=ev.JoinRemoteName or "HellJoinRemote"
        if ctx.Throttle("hell:join",2.5) then
            ctx.Remote(joinRemote)
        end
    end
    local function eggLive(obj)
        return obj and obj:IsA("BasePart") and obj:IsDescendantOf(workspace)
            and not obj:GetAttribute("Broken") and not obj:GetAttribute("Hatching")
            and not obj:GetAttribute("Despawning")
    end
    local function nearestEgg()
        local root=ctx.Root()
        if not root then return nil end
        local nearest,distance
        for _,obj in ipairs(CS:GetTagged(eggTag)) do
            if eggLive(obj) then
                local d=(obj.Position-root.Position).Magnitude
                if not distance or d<distance then nearest,distance=obj,d end
            end
        end
        return nearest
    end
    local function gather()
        local goal=tonumber(workspace:GetAttribute(goalAttr)) or essence.GoalBase or 1000
        local amount=tonumber(workspace:GetAttribute(amountAttr)) or 0
        if amount>=goal then
            stage("Essence goal reached; awaiting boss")
            return
        end
        local egg=nearestEgg()
        if not egg then
            stage("Waiting for Hell Essence Eggs ("..amount.."/"..goal..")")
            return
        end
        local root=ctx.Root()
        if not root then return end
        stage("Farming Essence "..amount.."/"..goal)
        if (root.Position-egg.Position).Magnitude>8 then
            ctx.Move("Hell",egg.Position)
            return
        end
        local tool=ctx.Equip(axeCfg.ToolName or "Pickaxe")
        if not tool then stage("Pickaxe required for Essence");return end
        if os.clock()-lastHit>math.max(0.55,axeCfg.SwingCooldown or 0.5) then
            lastHit=os.clock()
            if pickaxe and type(pickaxe.Swing)=="function" then
                local ok,err=pcall(pickaxe.Swing,egg)
                if not ok then ctx.Error("Hell pickaxe",err) end
            else
                pcall(function() tool:Activate() end)
            end
        end
    end
    local function fight()
        local bosses=CS:GetTagged(bossCfg.Tag or "HellBoss")
        local target
        for _,obj in ipairs(bosses) do
            if obj:IsA("Model") and obj.Parent then
                local hp=obj:GetAttribute("Health")
                if type(hp)~="number" or hp>0 then target=obj;break end
            end
        end
        if not target then
            stage("Waiting for Demon Boss / server progression")
            return
        end
        local pos=ctx.Position(target)
        local root=ctx.Root()
        if not root or not pos then return end
        stage("Demon Boss ("..tostring(target:GetAttribute("Health") or "?").." HP)")
        local reach=tonumber(bossCfg.BatHitReach) or 10
        if (root.Position-pos).Magnitude>math.max(4,reach-2) then
            ctx.Move("Hell",pos,0)
            return
        end
        local tool=ctx.Equip(batCfg.ToolName or "Bat")
        if not tool then stage("Bat required for Demon Boss");return end
        if os.clock()-lastHit>0.65 then
            lastHit=os.clock()
            if bat and type(bat.Swing)=="function" then
                local ok,err=pcall(bat.Swing)
                if not ok then ctx.Error("Hell boss swing",err) end
            else
                pcall(function() tool:Activate() end)
            end
        end
    end
    ctx.Worker("AutoHellEvent",0.45,function()
        if not ctx.InHell() then join(); return end
        local isGathering=workspace:GetAttribute(gatherAttr)
        if isGathering==true then
            gather()
        elseif isGathering==false then
            fight()
        else
            stage("Waiting for replicated Hell phase")
        end
    end)
    task.spawn(function()
        local enabled=false
        while S.Running do
            if enabled and not S.AutoHellEvent then stage("Paused") end
            enabled=S.AutoHellEvent
            task.wait(0.65)
        end
    end)
end