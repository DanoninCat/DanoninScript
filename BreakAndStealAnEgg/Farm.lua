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
    -- Movement is delegated to the native Humanoid navigation / WalkSpeed.
    local safeQuery
    do
        local m=ctx.Shared and ctx.Shared:FindFirstChild("SafeZoneQuery")
        if m and m:IsA("ModuleScript") then
            local ok,res=pcall(require,m)
            if ok then safeQuery=res end
        end
    end
    local delivery={started=false,bankSeen=false,confirmed=false,attemptAt=0,lossAt=nil,entry=nil,wasOutside=false,
        lastCarriedPos=nil, lastCarryingToken=nil, droppedAt=nil, recovering=false}
    local function safelyInside(pos)
        if safeQuery and type(safeQuery.IsPositionSafe)=="function" then
            local ok,result=pcall(safeQuery.IsPositionSafe,pos)
            return ok and result==true
        end
        return false
    end
    local function bankable(pos)
        if safeQuery and type(safeQuery.IsBankable)=="function" then
            local ok,result=pcall(safeQuery.IsBankable,LP.UserId,pos)
            return ok and result==true
        end
        return false
    end
    local function safeParts()
        if safeQuery and type(safeQuery.GetSafeParts)=="function" then
            local ok,result=pcall(safeQuery.GetSafeParts)
            if ok and type(result)=="table" then return result end
        end
        return {}
    end
    local function nearestSafePart(rootPos)
        local best,dist
        for _,part in ipairs(safeParts()) do
            if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
                local localPos=part.CFrame:PointToObjectSpace(rootPos)
                local half=part.Size*0.5
                local nearestLocal=Vector3.new(
                    math.clamp(localPos.X,-half.X,half.X),0,
                    math.clamp(localPos.Z,-half.Z,half.Z))
                local nearest=part.CFrame:PointToWorldSpace(nearestLocal)
                local d=(Vector3.new(nearest.X,0,nearest.Z)-Vector3.new(rootPos.X,0,rootPos.Z)).Magnitude
                if not dist or d<dist then best,dist=part,d end
            end
        end
        return best
    end
    local function insideSafeEdge(part,pos)
        -- Pick a point just inside the closest vertical boundary, not the Plot center.
        local localPos=part.CFrame:PointToObjectSpace(pos)
        local hx=math.max(0,part.Size.X/2-3)
        local hz=math.max(0,part.Size.Z/2-3)
        local candidate=Vector3.new(math.clamp(localPos.X,-hx,hx),0,math.clamp(localPos.Z,-hz,hz))
        local closest=part.CFrame:PointToWorldSpace(candidate)
        return Vector3.new(closest.X,part.Position.Y+part.Size.Y/2+1.2,closest.Z)
    end
    local function continuousTravel(destination)
        local root,hum=ctx.Root()
        if not root or not hum or not ctx.CanMove("Farm") or ctx.InHell() then return false end
        -- Humanoid:MoveTo uses the walk speed already maintained by the native game.
        -- Do not modify WalkSpeed or artificially cap studs per second.
        local target=Vector3.new(destination.X,root.Position.Y,destination.Z)
        local current=Vector3.new(root.Position.X,0,root.Position.Z)
        local targetFlat=Vector3.new(target.X,0,target.Z)
        if (targetFlat-current).Magnitude<2 then
            return true
        end
        hum:MoveTo(target)
        return false
    end
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
        if ctx.DeathTravel and type(ctx.DeathTravel.Stop)=="function" then
            ctx.DeathTravel.Stop()
        end
        cycle.deathTravelActive=false
        cycle.deathTravelTried=false
        cycle.egg=nil
        cycle.origin=nil
        cycle.rarity=nil
        cycle.zoneId=nil
        cycle.snapshot=nil
        cycle.pickup=nil
        cycle.inventoryBefore=nil
        cycle.lastCollect=0
        cycle.targetPet=nil
        cycle.missingAt=nil
        delivery.started=false
        delivery.bankSeen=false
        delivery.confirmed=false
        delivery.attemptAt=0
        delivery.lossAt=nil
        delivery.entry=nil
        delivery.wasOutside=false
        delivery.lastCarriedPos=nil
        delivery.lastCarryingToken=nil
        delivery.droppedAt=nil
        delivery.recovering=false
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
    local function sameAnimalAttributes(a,b)
        for _,key in ipairs({"AnimalId","AnimalUID","AnimalGuid","PetId","UniqueId","UID"}) do
            local av=a and a:GetAttribute(key)
            local bv=b and b:GetAttribute(key)
            if av~=nil and bv~=nil then return av==bv, true end
        end
        if not a or not b then return false,false end
        local aName=a:GetAttribute("AnimalName") or a.Name
        local bName=b:GetAttribute("AnimalName") or b.Name
        if aName~=bName then return false,false end
        for _,key in ipairs({"Weight","Size","Mutation","ZoneId"}) do
            local av=a:GetAttribute(key)
            local bv=b:GetAttribute(key)
            if av~=nil and bv~=nil and av~=bv then return false,false end
        end
        return true,false
    end
    local function recoveryPickup()
        local original=cycle.targetPet
        if not original then return nil end
        if original.Parent and original:IsDescendantOf(workspace)
            and original:GetAttribute("Despawning")~=true then
            local owner=original:GetAttribute("ReservedUserId")
            if owner==nil or owner==LP.UserId then return original end
        end
        -- After guard knockback the server may recreate the drop as a new model.
        -- Associate only an unambiguous nearby match with the lost original Pet.
        local where=delivery.lastCarriedPos
        if not where then return nil end
        local options={}
        for _,candidate in ipairs(CS:GetTagged("AnimalPickup")) do
            if candidate~=original and candidate:IsA("Model")
                and candidate:IsDescendantOf(workspace)
                and candidate:GetAttribute("Despawning")~=true then
                local owner=candidate:GetAttribute("ReservedUserId")
                if owner==nil or owner==LP.UserId then
                    local matching,strong=sameAnimalAttributes(original,candidate)
                    local distance=(candidate:GetPivot().Position-where).Magnitude
                    if matching and (distance<=45 or strong) then
                        options[#options+1]={model=candidate,distance=distance,strong=strong}
                    end
                end
            end
        end
        table.sort(options,function(x,y)
            if x.strong~=y.strong then return x.strong end
            return x.distance<y.distance
        end)
        if options[1] and (options[1].strong or #options==1) then
            cycle.targetPet=options[1].model
            cycle.pickup=options[1].model
            return cycle.targetPet
        end
        return nil
    end
    local function nearbyPickup()
        if cycle.targetPet then
            local model=recoveryPickup()
            if model then return findPrompt(model),model end
            return nil,nil
        end
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
        if best and not cycle.targetPet then cycle.targetPet=best end
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
        if not ctx.Throttle("farm:prompt",math.max(0.45,prompt.HoldDuration+0.25)) then return false end
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
        delivery.started=true
        delivery.bankSeen=false
        delivery.entry=nil
        delivery.attemptAt=0
        delivery.lossAt=nil
        local root=ctx.Root()
        delivery.wasOutside=root and not safelyInside(root.Position) or false
        delivery.lastCarriedPos=root and root.Position or delivery.lastCarriedPos
        delivery.lastCarryingToken=LP:GetAttribute("Carrying")
        delivery.recovering=false
        cycle.deathTravelTried=false
        cycle.deathTravelActive=false
        transition("return","Carrying Pet with native speed to Safe Zone")
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
                cycle.missingAt=nil
                local pos=model:GetPivot().Position
                if prompt then
                    S.Step=(delivery.recovering and "Recovering dropped Pet: " or "Collecting Pet: ")..tostring(cycle.rarity)
                    if trigger(prompt) then cycle.lastCollect=os.clock() end
                else
                    local part=ctx.Root()
                    if part and (part.Position-pos).Magnitude>5 then
                        if delivery.recovering then continuousTravel(pos)
                        else ctx.Move("Farm",pos,0) end
                    end
                    S.Step="Waiting for same Pet's Steal prompt"
                end
            else
                -- Never interpret disappearance as successful collection.
                cycle.missingAt=cycle.missingAt or os.clock()
                if cycle.targetPet and (not cycle.targetPet.Parent or cycle.targetPet:GetAttribute("Despawning")==true) then
                    if os.clock()-cycle.missingAt>1.4 then
                        reset("Pet disappeared without server receipt")
                    end
                elseif os.clock()-cycle.missingAt>12 then
                    reset("Spawned Pet not found / expired")
                else
                    S.Step="Waiting for Pet from selected Egg"
                end
            end
            return
        end
        if cycle.stage=="return" then
            -- Death Travel is opt-in; normal Safe Zone transport remains unchanged.
            if cycle.deathTravelActive and (not S.DeathTravel or not ctx.DeathTravel) then
                if ctx.DeathTravel then ctx.DeathTravel.Stop() end
                cycle.deathTravelActive=false
            end
            if S.DeathTravel and ctx.DeathTravel and not cycle.deathTravelTried and carrying() then
                cycle.deathTravelTried=true
                cycle.deathTravelActive=ctx.DeathTravel.Start(cycle,{
                    placedCount=placedCount,
                    newTool=newAnimalTool,
                    recoveryPickup=recoveryPickup,
                    findPrompt=findPrompt,
                    bankable=bankable,
                })
            end
            if cycle.deathTravelActive then
                local outcome=ctx.DeathTravel.Step()
                if outcome=="delivered" then
                    reset("Death Travel: Pet saved (inventory/Pen verified)")
                    return
                elseif outcome=="gone" then
                    reset("Death Travel: original Pet expired; no delivery credited")
                    return
                elseif outcome=="fallback" then
                    cycle.deathTravelActive=false
                else
                    -- Boss combat, death and recovery are handled by DeathTravel.lua.
                    return
                end
            end
        end
        if cycle.stage=="return" or cycle.stage=="place" then
            local count=placedCount()
            if cycle.beforePlaced and count>cycle.beforePlaced then
                reset("Delivered: Pen AnimalsPlaced increased")
                return
            end
            local tool=newAnimalTool()
            local carried=carrying()
            if tool and delivery.bankSeen and not carried then
                reset("Delivered: Safe Zone crossed and AnimalTool confirmed")
                return
            end
            if not carried and not tool then
                -- Server has not credited a tool or Pen placement yet.
                delivery.lossAt=delivery.lossAt or os.clock()
                if os.clock()-delivery.lossAt<1 then
                    S.Step="Awaiting server inventory confirmation"
                    return
                end
                local recovered=recoveryPickup()
                if recovered then
                    cycle.pickup=recovered
                    delivery.started=false
                    delivery.recovering=true
                    delivery.droppedAt=os.clock()
                    transition("collect","Boss dropped Pet; returning to recover SAME animal")
                    return
                end
                local original=cycle.targetPet
                if original and original.Parent and original:IsDescendantOf(workspace)
                    and original:GetAttribute("Despawning")~=true then
                    S.Step="Dropped Pet temporarily unavailable; holding current cycle"
                    return
                end
                -- Grace for a server-replicated replacement of the dropped model.
                if os.clock()-delivery.lossAt<6 then
                    S.Step="Waiting for dropped Pet replication"
                    return
                end
                reset("Original Pet unavailable after drop; no delivery receipt")
                return
            end
            delivery.lossAt=nil
            local root=ctx.Root()
            if not root then return end
            if carried then
                delivery.lastCarriedPos=root.Position
                delivery.lastCarryingToken=LP:GetAttribute("Carrying")
            end
            -- No instantaneous teleport to the Plot, even in Fast travel mode.
            local safe=nearestSafePart(root.Position)
            if not safe then
                S.Step="Waiting for replicated Safe Zone boundary"
                return
            end
            local destination=insideSafeEdge(safe,root.Position)
            if not safelyInside(root.Position) then
                delivery.wasOutside=true
                continuousTravel(destination)
                S.Step="Running continuously across Safe Zone line"
            else
                if delivery.wasOutside then delivery.bankSeen=true end
                S.Step="Inside Safe Zone: awaiting server bank confirmation"
                -- Do not credit a crossing until we have approached from outside.
                if delivery.attemptAt==0 then delivery.attemptAt=os.clock() end
                if os.clock()-delivery.attemptAt>2.5 then
                    delivery.attemptAt=os.clock()
                    local localPos=safe.CFrame:PointToObjectSpace(root.Position)
                    local hx=safe.Size.X*0.5
                    local hz=safe.Size.Z*0.5
                    local nearX=hx-math.abs(localPos.X)
                    local nearZ=hz-math.abs(localPos.Z)
                    local outsideLocal
                    if nearX<=nearZ then
                        local sign=localPos.X>=0 and 1 or -1
                        outsideLocal=Vector3.new(sign*(hx+4),0,math.clamp(localPos.Z,-hz,hz))
                    else
                        local sign=localPos.Z>=0 and 1 or -1
                        outsideLocal=Vector3.new(math.clamp(localPos.X,-hx,hx),0,sign*(hz+4))
                    end
                    local outside=safe.CFrame:PointToWorldSpace(outsideLocal)
                    delivery.entry=Vector3.new(outside.X,root.Position.Y,outside.Z)
                    delivery.wasOutside=false
                end
                if delivery.entry and not delivery.wasOutside then
                    local point=delivery.entry
                    continuousTravel(point)
                end
            end
            return
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
