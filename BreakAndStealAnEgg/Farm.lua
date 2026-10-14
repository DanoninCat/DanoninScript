return function(ctx)
    local S, LP, CS = ctx.S, ctx.Player, ctx.CS
    local EggTargeting = ctx.Config.EggTargeting or {}
    local PickaxeConfig = ctx.Config.PickaxeConfig or {}
    local nativePickaxe = ctx.Controllers.PickaxeController
    local order={"Common","Uncommon","Rare","Epic","Legendary","Mythic","Divine","Cosmic","Secret","Celestial","Inferno","Void","Omega"}
    local rank={}
    for i,name in ipairs(order) do rank[name]=i end
    local cycle={stage="search",egg=nil,origin=nil,since=0,lastSwing=0,lastCollect=0}
    local blocked=setmetatable({}, {__mode="k"})
    local lastRarityWarning=0
    local function carrying()
        return LP:GetAttribute("Carrying") ~= nil or LP:GetAttribute("CarryingJail") == true
    end
    local function rarityOf(part)
        local obj=part
        for _=1,3 do
            if not obj then break end
            for _,key in ipairs({"Rarity","EggRarity","TierRarity"}) do
                local value=obj:GetAttribute(key)
                if type(value)=="string" then
                    for _,name in ipairs(order) do
                        if value:lower()==name:lower() then return name end
                    end
                end
            end
            for _,name in ipairs(order) do
                if tostring(obj.Name):lower():find(name:lower(),1,true) then return name end
            end
            obj=obj.Parent
        end
        return "Unknown"
    end
    local function live(part)
        if not part or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then return false end
        if EggTargeting.IsLive then
            local ok,result=pcall(EggTargeting.IsLive,part)
            if ok then return result == true end
        end
        return not part:GetAttribute("Broken")
            and not part:GetAttribute("Hatching")
            and not part:GetAttribute("Despawning")
    end
    local function inHellMap(part)
        local config=ctx.Config.HellEventConfig or {}
        local hell=workspace:FindFirstChild(config.MapName or "HellBossFight")
        return hell and part:IsDescendantOf(hell) or false
    end
    local function nextEgg()
        local root=ctx.Root()
        if not root then return nil end
        local choices={}
        for _,egg in ipairs(CS:GetTagged("BreakableEgg")) do
            local rarity=rarityOf(egg)
            if live(egg) and not inHellMap(egg)
                and S.SelectedRarities[rarity] == true
                and (blocked[egg] or 0) < os.clock() then
                choices[#choices+1]={
                    egg=egg,rarity=rarity,
                    distance=(root.Position-egg.Position).Magnitude,
                }
            end
        end
        table.sort(choices,function(a,b)
            if S.EggPriority=="Nearest" then
                if a.distance~=b.distance then return a.distance<b.distance end
                return (rank[a.rarity] or 0)>(rank[b.rarity] or 0)
            end
            if (rank[a.rarity] or 0) ~= (rank[b.rarity] or 0) then
                return (rank[a.rarity] or 0)>(rank[b.rarity] or 0)
            end
            return a.distance<b.distance
        end)
        return choices[1] and choices[1].egg
    end
    local function transition(stage,message)
        cycle.stage=stage
        cycle.since=os.clock()
        S.Step=stage
        if message then ctx.Status(message) end
    end
    local function reset(message)
        cycle.egg=nil
        cycle.origin=nil
        cycle.lastCollect=0
        transition("search",message or "Searching eggs")
    end
    local function nearbyPickup()
        if not cycle.origin then return nil end
        local list=CS:GetTagged("AnimalPickup")
        local closest,prompt,dist
        for _,obj in ipairs(list) do
            if obj:IsDescendantOf(workspace) then
                local current=obj:IsA("ProximityPrompt") and obj or obj:FindFirstChildWhichIsA("ProximityPrompt",true)
                local pos=current and ctx.Position(current)
                local range=pos and (pos-cycle.origin).Magnitude
                if range and range<100 and current.Enabled
                    and (not dist or range<dist) then
                    closest,prompt,dist=obj,current,range
                end
            end
        end
        return prompt,closest
    end
    local function trigger(prompt)
        if not prompt or not prompt.Parent or not prompt.Enabled then return false end
        local root=ctx.Root()
        local pos=ctx.Position(prompt)
        if not root or not pos then return false end
        if (root.Position-pos).Magnitude > math.max(3,prompt.MaxActivationDistance-1) then
            ctx.Move("Farm",pos)
            return false
        end
        if not ctx.Throttle("farm:prompt",math.max(0.75,prompt.HoldDuration+0.45)) then return false end
        local ok=pcall(function()
            if type(fireproximityprompt)=="function" then
                fireproximityprompt(prompt)
            else
                prompt:InputHoldBegin()
                task.wait(math.max(0.12,prompt.HoldDuration+0.05))
                prompt:InputHoldEnd()
            end
        end)
        return ok
    end
    local function farm()
        if ctx.InHell() then
            S.Step="Paused (Hell area)"
            return
        end
        if not ctx.CanMove("Farm") then return end
        if carrying() and cycle.stage~="return" then
            transition("return","Pet collected; returning to Pen")
        end
        if cycle.stage=="search" then
            if not next(S.SelectedRarities) then
                S.Step="Select at least one rarity"
                return
            end
            local egg=nextEgg()
            if not egg then
                S.Step="No matching live eggs"
                return
            end
            cycle.egg=egg
            cycle.origin=egg.Position
            transition("break","Egg: "..egg.Name.." ("..rarityOf(egg)..")")
            return
        end
        if cycle.stage=="break" then
            local egg=cycle.egg
            if not live(egg) then
                transition("collect","Waiting for spawned animal")
                return
            end
            if os.clock()-cycle.since>28 then
                blocked[egg]=os.clock()+12
                reset("Egg timeout")
                return
            end
            cycle.origin=egg.Position
            local root=ctx.Root()
            if not root then return end
            local distance=(root.Position-egg.Position).Magnitude
            if distance>9 then
                ctx.Move("Farm",egg.Position)
                return
            end
            local tool=ctx.Equip(PickaxeConfig.ToolName or "Pickaxe")
            if not tool then
                S.Step="Pickaxe not available"
                return
            end
            if os.clock()-cycle.lastSwing>=math.max(0.5,PickaxeConfig.SwingCooldown or 0.5) then
                cycle.lastSwing=os.clock()
                if nativePickaxe and type(nativePickaxe.Swing)=="function" then
                    local ok,worked=pcall(nativePickaxe.Swing,egg)
                    if not ok then ctx.Error("PickaxeController.Swing",worked) end
                else
                    pcall(function() tool:Activate() end)
                end
            end
            return
        end
        if cycle.stage=="collect" then
            if carrying() then transition("return","Carrying animal");return end
            if os.clock()-cycle.since>18 then
                if cycle.egg then blocked[cycle.egg]=os.clock()+10 end
                reset("No animal collected")
                return
            end
            local prompt=nearbyPickup()
            if prompt then
                S.Step="Collecting animal (E)"
                if trigger(prompt) then cycle.lastCollect=os.clock() end
            else
                S.Step="Waiting for AnimalPickup / Steal prompt"
            end
            return
        end
        if cycle.stage=="return" then
            if not carrying() then
                reset("Delivery / transport ended")
                return
            end
            local plot=ctx.Plot()
            if not plot then S.Step="Waiting for owned Pen";return end
            local hitbox=plot:FindFirstChild("Hitbox")
            local dest=hitbox and ctx.Position(hitbox) or ctx.Position(plot)
            if not dest then S.Step="Pen location unavailable";return end
            if os.clock()-cycle.since>35 then
                S.Step="Carrying persists at Pen; manual confirmation needed"
                return
            end
            ctx.Move("Farm",dest,2)
            S.Step="Delivering to Pen"
        end
    end
    ctx.Worker("AutoFarmEggs",0.28,function()
        farm()
    end)
    task.spawn(function()
        local wasOn=false
        while S.Running do
            if wasOn and not S.AutoFarmEggs then reset("Farm paused") end
            wasOn=S.AutoFarmEggs
            task.wait(0.4)
        end
    end)
end