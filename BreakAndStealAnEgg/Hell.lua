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
    local bossState={defeated=false,seen=false,lastHealth=nil}
    local function findBoss()
        for _,obj in ipairs(CS:GetTagged(bossCfg.Tag or "HellBoss")) do
            if obj:IsA("Model") and obj:IsDescendantOf(workspace) then return obj end
        end
        local arena=workspace:FindFirstChild(ev.MapName or "HellBossFight")
        local obj=arena and arena:FindFirstChild(bossCfg.ModelName or "DemonBoss",true)
        if obj and obj:IsA("Model") then return obj end
        return nil
    end
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
    local function fight(target)
        if not target then
            stage("Waiting for Demon King model / server phase")
            return
        end
        local health=target:GetAttribute("Health")
        local phase=target:GetAttribute("Phase")
        if phase=="Defeated" or (type(health)=="number" and health<=0) then
            bossState.defeated=true
            stage("Demon King defeated on server; waiting for reward/exit")
            return
        end
        if phase=="Failed" then
            stage("Demon King encounter failed (server phase)")
            return
        end
        if phase~="Active" and phase~="Stunned" then
            stage("Demon King phase: "..tostring(phase or "loading").." (waiting for fight)")
            return
        end
        local batTool=ctx.Equip(batCfg.ToolName or "Bat")
        if not batTool or CS:HasTag(batTool,"AnimalTool") then
            stage("Demon King: equip native Bat")
            return
        end
        if type(health)=="number" then
            bossState.lastHealth=health
        end
        local bossPart=target:FindFirstChild(bossCfg.Rig and bossCfg.Rig.Root or "Root")
            or target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart",true)
        local root,hum=ctx.Root()
        if not root or not hum or not bossPart then
            stage("Waiting for arena position / boss root")
            return
        end
        local floorY=target:GetAttribute("FloorY")
        local feet=type(floorY)=="number"
            and floorY+hum.HipHeight+root.Size.Y/2
            or root.Position.Y
        local direction=Vector3.new(root.Position.X-bossPart.Position.X,0,root.Position.Z-bossPart.Position.Z)
        if direction.Magnitude<0.1 then direction=Vector3.new(1,0,0) end
        local aim=Vector3.new(bossPart.Position.X,feet,bossPart.Position.Z)+direction.Unit*12
        local planar=(Vector3.new(root.Position.X,0,root.Position.Z)
            -Vector3.new(bossPart.Position.X,0,bossPart.Position.Z)).Magnitude
        local reach=tonumber(bossCfg.BatHitRadius) or 32
        if planar>math.max(8,reach-7) or math.abs(root.Position.Y-feet)>5 then
            ctx.Move("Hell",aim,0)
            stage("Approaching Demon King: "..tostring(health or "?").." HP")
            return
        end
        if type(bat)~="table" or type(bat.Swing)~="function" then
            if os.clock()-lastHit>0.65 then
                lastHit=os.clock()
                pcall(function() batTool:Activate() end)
            end
            stage("Swinging Bat (native tool): "..tostring(health or "?").." HP")
            return
        end
        local nativeBoss=ctx.Controllers.HellBossController
        if nativeBoss and type(nativeBoss.CanBatHit)=="function" then
            local ok,allowed=pcall(nativeBoss.CanBatHit)
            if not ok or not allowed then
                local shields=target:GetAttribute("ShieldsUp")
                if type(shields)=="number" and shields>0 then
                    stage("Demon King shield active; waiting ("..shields..")")
                else
                    stage("Waiting for valid Demon King attack window")
                end
                return
            end
        end
        if os.clock()-lastHit>=math.max(0.5,tonumber(batCfg.HellClientCooldown) or 0.5) then
            lastHit=os.clock()
            local ok,err=pcall(bat.Swing)
            if not ok then ctx.Error("Hell boss Bat.Swing",err) end
        end
        stage("Attacking Demon King: "..tostring(health or "?").."/"..tostring(target:GetAttribute("MaxHealth") or bossCfg.MaxHealth or "?").." HP")
    end
    ctx.Worker("AutoHellEvent",0.3,function()
        if not ctx.InHell() then
            if bossState.defeated then
                stage("Demon King defeated; server return/reward pending")
            end
            join()
            return
        end
        local target=findBoss()
        local phase=target and target:GetAttribute("Phase")
        local hp=target and target:GetAttribute("Health")
        if target and (phase=="Active" or phase=="Stunned" or phase=="Intro" or phase=="Defeated"
            or (type(hp)=="number" and hp<=0)) then
            bossState.seen=true
            fight(target)
            return
        end
        if workspace:GetAttribute(gatherAttr)==true then
            gather()
        else
            fight(target)
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
