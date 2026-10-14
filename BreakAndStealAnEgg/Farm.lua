return function(ctx)
    local S, LP, CS = ctx.S, ctx.Player, ctx.CS
    local EggTargeting = ctx.Config.EggTargeting or {}
    local PickaxeConfig = ctx.Config.PickaxeConfig or {}
    local nativePickaxe = ctx.Controllers.PickaxeController
    local order={"Common","Uncommon","Rare","Epic","Legendary","Mythic","Divine","Cosmic","Secret","Celestial","Inferno","Void","Omega"}
    local rank={}
    for i,name in ipairs(order) do rank[name]=i end
    local cycle={stage="search",egg=nil,origin=nil,rarity=nil,zoneId=nil,since=0,lastSwing=0,lastCollect=0}
    local visiblePrompts=setmetatable({}, {__mode="k"})
    local function snapshotAnimals()
        local snapshot=setmetatable({}, {__mode="k"})
        for _,animal in ipairs(CS:GetTagged("AnimalPickup")) do snapshot[animal]=true end
        return snapshot
    end
    local function inventoryAnimals()
        local list=setmetatable({}, {__mode="k"})
        for _,container in ipairs({LP:FindFirstChildOfClass("Backpack"),LP.Character}) do
            if container then
                for _,tool in ipairs(container:GetChildren()) do
                    if tool:IsA("Tool") and (CS:HasTag(tool,"AnimalTool") or type(tool:GetAttribute("AnimalName"))=="string") then
                        list[tool]=true
                    end
                end
            end
        end
        return list
    end
    local function newAnimalTool()
        for tool in pairs(inventoryAnimals()) do
            if tool.Parent and not (cycle.inventoryBefore or {})[tool] then return tool end
        end
        return nil
    end
    local ProximityPromptService=game:GetService("ProximityPromptService")
    local shownConnection=ProximityPromptService.PromptShown:Connect(function(prompt)
        visiblePrompts[prompt]=true
    end)
    local hiddenConnection=ProximityPromptService.PromptHidden:Connect(function(prompt)
        visiblePrompts[prompt]=nil
    end)
    ctx.Links[#ctx.Links+1]=shownConnection
    ctx.Links[#ctx.Links+1]=hiddenConnection
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
        local lookup=ctx.Config.ZoneHitboxLookup or {}
        local zones=ctx.Config.ZonesConfig or {}
        if type(lookup.GetZoneIndexAt)=="function" then
            local ok,index=pcall(lookup.GetZoneIndexAt,part.Position)
            if ok and type(index)=="number" then
                local entry=(zones.Zones or {})[index]
                if entry and type(entry.Rarity)=="string" then return entry.Rarity end
            end
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
                then
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
        cycle.rarity=nil
        cycle.zoneId=nil
        cycle.snapshot=nil
        cycle.pickup=nil
        cycle.inventoryBefore=nil
        cycle.lastCollect=0
        cycle.beforePlaced=nil
        cycle.beforeTools=nil
        transition("search",message or "Searching eggs")
    end
    local function nearOrigin(pos)
        return cycle.origin and pos and (pos-cycle.origin).Magnitude <= 65
    end
    local function eligibleAnimal(model)
        if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace)
            or model:GetAttribute("Despawning") == true then return false end
        local reserved=model:GetAttribute("ReservedUserId")
        if reserved ~= nil and reserved ~= LP.UserId then return false end
        local zone=model:GetAttribute("ZoneId")
        if cycle.zoneId and type(zone)=="string" and zone~=cycle.zoneId then return false end
        return nearOrigin(model:GetPivot().Position) and not (cycle.snapshot or {})[model]
    end
    local function findPrompt(model)
        if not model then return nil end
        local prompt=model:FindFirstChildWhichIsA("ProximityPrompt",true)
        if prompt and prompt.Enabled then return prompt end
        local pos=model:GetPivot().Position
        for candidate in pairs(visiblePrompts) do
            if candidate.Parent and candidate.Enabled and candidate.ActionText:lower()=="steal" then
                local location=ctx.Position(candidate)
                if location and (location-pos).Magnitude<13 then return candidate end
            end
        end
        return nil
    end
    local function nearbyPickup()
        if cycle.pickup and eligibleAnimal(cycle.pickup) then
            return findPrompt(cycle.pickup),cycle.pickup
        end
        cycle.pickup=nil
        local best,dist
        for _,model in ipairs(CS:GetTagged("AnimalPickup")) do
            if eligibleAnimal(model) then
                local pos=model:GetPivot().Position
                local distance=(pos-cycle.origin).Magnitude
                if not dist or distance<dist or
                    (model:GetAttribute("ReservedUserId")==LP.UserId
                     and best:GetAttribute("ReservedUserId")~=LP.UserId) then
                    best,dist=model,distance
                end
            end
        end
        cycle.pickup=best
        return findPrompt(best),best
    end
    local function trigger(prompt)
        if not prompt or not prompt.Parent or not prompt.Enabled then return false end
        local part=ctx.Root()
        local pos=ctx.Position(prompt)
        if not part or not pos then return false end
        local reach=math.max(2,prompt.MaxActivationDistance-1)
        if (part.Position-pos).Magnitude > reach then
            ctx.Move("Farm",pos,0)
            return false
        end
        if not ctx.Throttle("farm:prompt",math.max(1.6,prompt.HoldDuration+1)) then return false end
        local ok,err=pcall(function()
            if type(fireproximityprompt)=="function" then
                fireproximityprompt(prompt)
            else
                prompt:InputHoldBegin()
                task.wait(math.max(0.12,prompt.HoldDuration+0.1))
                prompt:InputHoldEnd()
            end
        end)
        if not ok then ctx.Error("Pickup prompt",err) end
        return ok
    end
    local function placedCount()
        local plot=ctx.Plot()
        return plot and tonumber(plot:GetAttribute("AnimalsPlaced")) or 0
    end
    local function startReturn()
        if cycle.stage=="return" or cycle.stage=="place" then return end
        transition("return","Animal collected; returning to Pen")
    end
    local function placementSpot(hitbox)
        if not hitbox or not hitbox:IsA("BasePart") then return nil end
        -- Try the center and small offsets, all within the owned Pen's hitbox.
        local ctrl=ctx.Controllers.AnimalToolController
        for _,delta in ipairs({
            Vector3.new(0,0,0),Vector3.new(3,0,0),Vector3.new(-3,0,0),
            Vector3.new(0,0,3),Vector3.new(0,0,-3)
        }) do
            local spot=hitbox.Position+hitbox.CFrame:VectorToWorldSpace(delta)
            if not ctrl or type(ctrl.CanPlaceAt)~="function" then return spot end
            local ok,allowed=pcall(ctrl.CanPlaceAt,spot)
            if ok and allowed then return spot end
        end
        return nil
    end
    local function farm()
        if ctx.InHell() then
            S.Step="Paused (Hell area)"
            return
        end
        if not ctx.CanMove("Farm") then
            S.Step="Paused (Hell Event / higher-priority movement)"
            return
        end
        if carrying() and cycle.stage~="return" then
            startReturn()
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
            cycle.rarity=rarityOf(egg)
            cycle.snapshot=snapshotAnimals()
            cycle.inventoryBefore=inventoryAnimals()
            cycle.beforePlaced=placedCount()
            local lookup=ctx.Config.ZoneHitboxLookup or {}
            if type(lookup.GetZoneIndexAt)=="function" then
                local ok,index=pcall(lookup.GetZoneIndexAt,egg.Position)
                if ok and type(index)=="number" then
                    cycle.zoneId="Zone"..tostring(index)
                end
            end
            transition("break","Egg: "..egg.Name.." ("..cycle.rarity..")")
            return
        end
        if cycle.stage=="break" then
            local egg=cycle.egg
            if not live(egg) then
                transition("collect","Waiting for spawned animal")
                return
            end
            -- No time limit: an egg stays selected while it is a valid, live target.
            cycle.origin=egg.Position
            local health=tonumber(egg:GetAttribute("Health"))
            S.Step=health and ("Breaking egg (HP: "..math.ceil(health)..")") or "Breaking selected egg"
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
            if carrying() then startReturn();return end
            local prompt,model=nearbyPickup()
            if model then
                local pos=model:GetPivot().Position
                if prompt then
                    S.Step="Collecting spawned animal (E) - "..cycle.rarity
                    if trigger(prompt) then cycle.lastCollect=os.clock() end
                else
                    local part=ctx.Root()
                    if part and (part.Position-pos).Magnitude>5 then ctx.Move("Farm",pos,0) end
                    S.Step="Waiting for native Steal prompt on spawned animal"
                end
            else
                S.Step="Waiting for animal from selected "..tostring(cycle.rarity).." egg"
            end
            return
        end
        if cycle.stage=="return" or cycle.stage=="place" then
            local currentPlaced=placedCount()
            if cycle.beforePlaced ~= nil and currentPlaced>cycle.beforePlaced then
                reset("Pet placed in Pen (confirmed)")
                return
            end
            local plot=ctx.Plot()
            if not plot then S.Step="Waiting for owned Pen";return end
            local hitbox=plot:FindFirstChild("Hitbox")
            if not hitbox or not hitbox:IsA("BasePart") then
                S.Step="Pen hitbox unavailable";return
            end
            local root=ctx.Root()
            if not root then return end
            if carrying() then
                if (root.Position-hitbox.Position).Magnitude>8 then
                    ctx.Move("Farm",hitbox.Position,0)
                end
                S.Step="Returning carried animal to Pen"
                return
            end
            local tool=newAnimalTool()
            if not tool then
                S.Step="Waiting for collected AnimalTool / Pen confirmation"
                return
            end
            if cycle.stage~="place" then transition("place","Placing collected animal in Pen") end
            local spot=placementSpot(hitbox)
            if not spot then
                if (root.Position-hitbox.Position).Magnitude>5 then
                    ctx.Move("Farm",hitbox.Position,0)
                end
                S.Step="Waiting for valid Pen placement position / capacity"
                return
            end
            local native=ctx.Controllers.AnimalToolController
            if native and type(native.PlaceAt)=="function" then
                local equipped=ctx.Equip(tool.Name)
                if equipped and ctx.Throttle("farm:place",2.5) then
                    local ok,accepted=pcall(native.PlaceAt,equipped,spot)
                    if not ok then ctx.Error("PlaceAt",accepted) end
                end
            else
                S.Step="Native animal placement controller unavailable"
            end
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