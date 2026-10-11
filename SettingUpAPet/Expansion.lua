return function(ctx)
    local S, LP, Tabs, Links, Game = ctx.State, ctx.Player, ctx.Tabs, ctx.Links, ctx.Game
    local RS=game:GetService("ReplicatedStorage")
    local CollectionService=game:GetService("CollectionService")
    local PetData, EggData = ctx.PetData, ctx.EggData
    local Saved=LP:FindFirstChild("SavedData")
    local Fusion=LP:FindFirstChild("FusionSlots")
    local UI={}
    local visuals={}
    local lastCall={}
    S.EggFilterMode="All"
    S.SelectedEggs={}
    S.EggHoldSeconds=0
    S.EggFlightSpeed=230
    S.AutoDeliverEggs=false
    S.AutoCollectCash=false
    S.AutoRideFastest=false
    S.AutoUnlockNests=false
    S.AutoFusePets=false
    S.AutoClaimFusion=false
    S.AutoClaimOfflineIndex=false
    S.AutoFarmHalloweenEvent=false
    S.AutoHeadlessRitual=false
    S.ShowEggDistance=false
    S.ShowPetValue=false

    local function notify(v) ctx.Notify(tostring(v)) end
    local function throttle(key,delay)
        local t=os.clock()
        if (lastCall[key] or 0)>t then return false end
        lastCall[key]=t+delay
        return true
    end
    local function val(parent,key,default)
        local inst=parent and parent:FindFirstChild(key)
        return inst and inst:IsA("ValueBase") and inst.Value or default
    end
    local function fire(name,...)
        local event=Game:FindFirstChild(name)
        if not event then notify("Missing remote: "..name); return false end
        local args=table.pack(...)
        local ok,result=pcall(function()
            if event:IsA("RemoteEvent") then
                event:FireServer(table.unpack(args,1,args.n))
                return true
            elseif event:IsA("RemoteFunction") then
                return event:InvokeServer(table.unpack(args,1,args.n))
            end
        end)
        if not ok then S.LastError=name..": "..tostring(result) end
        return ok,result
    end
    local function selection(data)
        local map={}
        if type(data)=="table" then
            for k,v in pairs(data) do
                if type(k)=="string" and v==true then map[k]=true
                elseif type(v)=="string" then map[v]=true end
            end
        end
        return map
    end
    local function toggle(tab,id,label,default)
        S[id]=default==true
        ctx.Toggles[id]=tab:AddToggle("SUP_EXTRA_"..id,{
            Title=label,Default=default==true,
            Callback=function(v) S[id]=v==true end,
        })
    end
    local function button(tab,label,callback)
        tab:AddButton({Title=label,Callback=function()
            task.spawn(function()
                local ok,e=pcall(callback)
                if not ok then S.LastError=tostring(e);notify(e) end
            end)
        end})
    end
    local function loop(key,interval,fn)
        task.spawn(function()
            while S.Running do
                if S[key] then
                    local ok,err=pcall(fn)
                    if not ok then S.LastError=key..": "..tostring(err) end
                end
                task.wait(interval)
            end
        end)
    end
    local function getPets()
        local result={}
        for _,folder in ipairs({LP.Character,LP:FindFirstChildOfClass("Backpack")}) do
            if folder then
                for _,obj in ipairs(folder:GetChildren()) do
                    if obj:IsA("Tool") and obj:GetAttribute("PetKey") then
                        local name=obj:GetAttribute("PetName") or obj.Name
                        local config=PetData[name]
                        if type(config)=="table" then
                            result[#result+1]={Tool=obj,Name=name,Speed=tonumber(config.Speed) or 0}
                        end
                    end
                end
            end
        end
        table.sort(result,function(a,b) return a.Speed>b.Speed end)
        return result
    end
    local function mounted()
        return LP:GetAttribute("IsRiding")==true or LP:GetAttribute("IsPassenger")==true
    end
    local mountPending=false
    local function mountBest()
        if mounted() or mountPending then return true end
        mountPending=true
        local best=getPets()[1]
        if not best then mountPending=false;return false end
        local root,hum=ctx.GetRoot()
        if not root or not hum then mountPending=false;return false end
        if best.Tool.Parent~=LP.Character then
            hum:EquipTool(best.Tool)
            task.wait(0.25)
        end
        if best.Tool.Parent==LP.Character then
            fire("Mounting")
        end
        mountPending=false
        return mounted()
    end
    local function ensureMount()
        if mounted() then return end
        if not mountPending then task.spawn(mountBest) end
    end
    local function collectCash()
        local pets=ctx.PetList()
        local collected=0
        for _,pet in ipairs(pets) do
            if pet.Placed and pet.Key and collected<12 and throttle("petcollect:"..tostring(pet.Key),8) then
                fire("PetCollect",pet.Key)
                collected=collected+1
                task.wait(.1)
            end
        end
    end
    local function unlockNest()
        local folder=Game:FindFirstChild("Plot")
        local event=folder and folder:FindFirstChild("Nests")
        local plot=ctx.GetPlot()
        if not event or not event:IsA("RemoteEvent") or not plot then return end
        local nests=plot:FindFirstChild("Nests")
        if not nests then return end
        local prices={0,1000,5000,100000,1000000}
        local cash=tonumber(val(Saved,"Cash",0)) or 0
        for _,nest in ipairs(nests:GetChildren()) do
            local slot=tonumber(nest.Name)
            if slot and slot>1 and slot<=#prices and cash>=prices[slot]
                and nest:FindFirstChild("Locked") and throttle("nest:"..slot,15) then
                event:FireServer(slot)
                return
            end
        end
    end
    local function fusionTick()
        if not Fusion then Fusion=LP:FindFirstChild("FusionSlots") end
        if not Fusion then return end
        local phase=Fusion:GetAttribute("FusionStatus")
        if S.AutoClaimFusion and phase=="Result" then
            local result=LP:FindFirstChild("FusionResult")
            local obj=result and result:FindFirstChild("Pet")
            local key=(obj and obj:GetAttribute("PetKey")) or Fusion:GetAttribute("FusionResultKey")
            if key and throttle("fusionclaim:"..tostring(key),7) then fire("FusionAction","Claim",key) end
        end
        if not S.AutoFusePets then return end
        if phase=="Waiting" then
            local expiry=tonumber(Fusion:GetAttribute("EndsAt"))
            if expiry and workspace:GetServerTimeNow()>=expiry and throttle("fusionfinish",8) then
                fire("FusionAction","Fuse")
            end
        elseif phase==nil and Fusion:GetAttribute("Ready")==true then
            local valid=true
            for i=1,4 do if not Fusion:FindFirstChild(tostring(i)) then valid=false end end
            if valid and throttle("fusionstart",12) then fire("FusionAction","Start") end
        end
    end
    local function claimOffline()
        if throttle("offline",25) then fire("OfflineEarnings") end
    end
    local function claimIndex()
        if type(ctx.ClaimIndex)=="function" then ctx.ClaimIndex() end
    end
    local function activateRadar()
        local char=LP.Character
        if not char then return end
        for _,tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") and CollectionService:HasTag(tool,"Radar") then
                fire("ActivateRadar")
                return
            end
        end
        notify("Equip a Radar first")
    end
    local function claimGroup()
        local fn=workspace:FindFirstChild("Functionals")
        local meat=fn and fn:FindFirstChild("Meat")
        local handle=meat and meat:FindFirstChild("Handle")
        local prompt=handle and handle:FindFirstChild("Claim")
        if not prompt or not prompt:IsA("ProximityPrompt") then
            notify("Group reward prompt not available");return
        end
        local root=ctx.GetRoot()
        if not root or (root.Position-handle.Position).Magnitude>prompt.MaxActivationDistance then
            notify("Move near the group reward stand first");return
        end
        if type(fireproximityprompt)=="function" then
            fireproximityprompt(prompt)
        else
            notify("Use the game's Claim prompt")
        end
    end
    local function claimBoost()
        local fn=workspace:FindFirstChild("Functionals")
        local boost=fn and fn:FindFirstChild("EventBoost")
        local id=boost and boost:GetAttribute("EventId")
        local endpoint=Game:FindFirstChild("ClaimEventReward")
        if not id or not endpoint or not endpoint:IsA("RemoteFunction") then
            notify("Event boost claim is currently unavailable");return
        end
        fire("ClaimEventReward",tostring(id))
    end

    local function visual(obj,key,label,color)
        local id=tostring(key)..":"..tostring(obj)
        local instance=visuals[id]
        if not obj or not obj.Parent then return end
        local anchor=obj:IsA("BasePart") and obj or
            (obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart",true)))
        if not anchor then return end
        if not instance or not instance.Parent then
            instance=Instance.new("BillboardGui")
            instance.Name="CAT_EMPIRE_INFO"
            instance.AlwaysOnTop=true
            instance.Adornee=anchor
            instance.MaxDistance=650
            instance.Size=UDim2.fromOffset(140,27)
            instance.StudsOffsetWorldSpace=Vector3.new(0,4,0)
            local text=Instance.new("TextLabel")
            text.BackgroundTransparency=1
            text.Size=UDim2.fromScale(1,1)
            text.Font=Enum.Font.GothamBold
            text.TextSize=13
            text.TextStrokeTransparency=.2
            text.Parent=instance
            instance.Parent=anchor
            visuals[id]=instance
        end
        local text=instance:FindFirstChildWhichIsA("TextLabel")
        if text then text.Text=label;text.TextColor3=color end
    end
    local function updateVisuals()
        local seen={}
        if S.EggsESP and S.ShowEggDistance then
            local folder=workspace:FindFirstChild("RenderedEggs")
            local root=ctx.GetRoot()
            if folder and root then
                for _,egg in ipairs(folder:GetChildren()) do
                    if egg:IsA("Model") or egg:IsA("BasePart") then
                        local ok,p=pcall(function()
                            return egg:IsA("Model") and egg:GetPivot().Position or egg.Position
                        end)
                        if ok and p then
                            local id="egg:"..tostring(egg)
                            seen[id]=true
                            visual(egg,"egg",tostring(math.floor((root.Position-p).Magnitude)).." studs",
                                Color3.fromRGB(225,240,255))
                        end
                    end
                end
            end
        end
        if S.ShowPetValue then
            for _,pet in ipairs(ctx.PetList()) do
                if pet.Placed and pet.Model then
                    local id="pet:"..tostring(pet.Model)
                    seen[id]=true
                    visual(pet.Model,"pet","$"..tostring(pet.Income or 0).."/s",
                        Color3.fromRGB(120,245,160))
                end
            end
        end
        for key,billboard in pairs(visuals) do
            if not seen[key] or not billboard.Parent then
                pcall(function() billboard:Destroy() end)
                visuals[key]=nil
            end
        end
    end
    local eggs={}
    for name in pairs(EggData) do if type(name)=="string" then eggs[#eggs+1]=name end end
    table.sort(eggs)
    Tabs.Eggs:AddDropdown("SUP_EXTRA_FilterMode",{
        Title="Pickup filter",Values={"All","Whitelist","Blacklist"},Default="All",
        Callback=function(v) S.EggFilterMode=v end,
    })
    Tabs.Eggs:AddDropdown("SUP_EXTRA_EggNames",{
        Title="Egg selection",Values=eggs,Multi=true,Default={},
        DropdownOutsideWindow=true,Callback=function(v) S.SelectedEggs=selection(v) end,
    })
    Tabs.Eggs:AddSlider("SUP_EXTRA_EggHold",{
        Title="Hold at egg (seconds)",Min=0,Max=5,Default=0,Rounding=1,
        Callback=function(v) S.EggHoldSeconds=tonumber(v) or 0 end,
    })
    Tabs.Eggs:AddSlider("SUP_EXTRA_EggFlightSpeed",{
        Title="Air Return Speed",Min=60,Max=500,Default=230,Rounding=0,
        Callback=function(v) S.EggFlightSpeed=tonumber(v) or 230 end,
    })
    toggle(Tabs.Eggs,"AutoDeliverEggs","Auto Deliver Carried Eggs",false)
    toggle(Tabs.Eggs,"ShowEggDistance","World Egg ESP: Show Distance",false)

    toggle(Tabs.Pets,"AutoCollectCash","Auto Collect Cash",false)
    button(Tabs.Pets,"Collect All Pet Cash Once",collectCash)
    button(Tabs.Pets,"Ride Fastest Pet",mountBest)
    toggle(Tabs.Pets,"AutoRideFastest","Auto Ride Fastest Pet",false)
    button(Tabs.Pets,"Dismount",function() fire("PetDismount") end)
    toggle(Tabs.Pets,"AutoFusePets","Auto Fuse Placed Pets",false)
    toggle(Tabs.Pets,"AutoClaimFusion","Auto Claim Fusion Result",false)
    button(Tabs.Pets,"Claim Fusion Result",function()
        local old=S.AutoClaimFusion
        S.AutoClaimFusion=true
        fusionTick()
        S.AutoClaimFusion=old
    end)

    button(Tabs.Shop,"Buy Selected Items Once",function()
        for itemId in pairs(S.SelectedItems or {}) do
            local category,name=itemId:match("^(.-) / (.+)$")
            if category and name then fire("BuyWithCash",category,name);task.wait(.18) end
        end
    end)
    button(Tabs.Shop,"Buy Selected Food Once",function()
        for itemId in pairs(S.SelectedFoods or {}) do
            local category,name=itemId:match("^(.-) / (.+)$")
            if category and name then fire("BuyWithCash",category,name);task.wait(.18) end
        end
    end)
    toggle(Tabs.Shop,"AutoUnlockNests","Auto Unlock Nests",false)
    button(Tabs.Shop,"Claim Offline Earnings",claimOffline)
    button(Tabs.Shop,"Claim Index Rewards",claimIndex)
    toggle(Tabs.Shop,"AutoClaimOfflineIndex","Auto Claim Offline + Index",false)
    button(Tabs.Shop,"Claim Group Reward",claimGroup)
    button(Tabs.Shop,"Claim Event Boost",claimBoost)
    button(Tabs.Shop,"Teleport to Event Boost",function()
        local fn=workspace:FindFirstChild("Functionals")
        local boost=fn and fn:FindFirstChild("EventBoost")
        local handle=boost and boost:FindFirstChild("Handle")
        local root=ctx.GetRoot()
        if root and handle and handle:IsA("BasePart") then
            root.CFrame=CFrame.new(handle.Position+Vector3.new(0,4,0))
        end
    end)
    button(Tabs.Shop,"Activate Radar",activateRadar)
    button(Tabs.Shop,"Teleport To Best Egg",function()
        local candidates=ctx.FilterableEggs()
        local first=candidates[1]
        local root=ctx.GetRoot()
        if first and root then root.CFrame=CFrame.new(first.Pos+Vector3.new(0,3,0)) end
    end)

    toggle(Tabs.Halloween,"AutoFarmHalloweenEvent","Auto Farm Halloween Event",false)
    toggle(Tabs.Halloween,"AutoHeadlessRitual","Auto Headless Event",false)

    local stat=Tabs.Intel:AddParagraph({Title="Account Stats",Content="Waiting for account data"})
    local best=Tabs.Intel:AddParagraph({Title="Best Pet",Content="Waiting for pet data"})
    toggle(Tabs.Intel,"ShowPetValue","Pet Value ESP",false)

    loop("AutoRideFastest",12,mountBest)
    loop("AutoCollectCash",7,collectCash)
    loop("AutoUnlockNests",8,unlockNest)
    loop("AutoFusePets",3,fusionTick)
    loop("AutoClaimFusion",4,fusionTick)
    loop("AutoHeadlessRitual",3,function()
        if S.Movement then return end
        local root=ctx.GetRoot()
        if not root then return end
        for _,prompt in ipairs(CollectionService:GetTagged("HalloweenRitualPrompt")) do
            if prompt:IsA("ProximityPrompt") and prompt.Enabled
                and prompt:GetAttribute("RitualAvailable")==true
                and prompt:IsDescendantOf(workspace) then
                local host=prompt.Parent
                local part=host:IsA("BasePart") and host or
                    (host:IsA("Attachment") and host.Parent or nil)
                if part and part:IsA("BasePart") then
                    if (root.Position-part.Position).Magnitude>prompt.MaxActivationDistance then
                        root.CFrame=CFrame.new(part.Position+Vector3.new(0,3,0))
                    end
                    if type(fireproximityprompt)=="function" and throttle("ritual:"..prompt:GetFullName(),5) then
                        fireproximityprompt(prompt)
                    end
                    return
                end
            end
        end
    end)
    loop("AutoClaimOfflineIndex",30,function()
        claimOffline()
        claimIndex()
    end)
    task.spawn(function()
        while S.Running do
            pcall(updateVisuals)
            task.wait(1.2)
        end
        for _,v in pairs(visuals) do pcall(function() v:Destroy() end) end
    end)
    task.spawn(function()
        local previousCandy,previousPumpkins
        while S.Running do
            if S.AutoFarmHalloweenEvent then
                if previousCandy==nil then
                    previousCandy,previousPumpkins=S.AutoCollectCandy,S.AutoSearchPumpkins
                end
                S.AutoCollectCandy=true
                S.AutoSearchPumpkins=true
            elseif previousCandy~=nil then
                S.AutoCollectCandy=previousCandy
                S.AutoSearchPumpkins=previousPumpkins
                previousCandy,previousPumpkins=nil,nil
            end
            local placed=ctx.PetList()
            local total=0
            local fastest
            for _,pet in ipairs(placed) do
                if pet.Placed then total=total+1 end
                if not fastest or (pet.Income or 0)>(fastest.Income or 0) then fastest=pet end
            end
            local folder=RS:FindFirstChild("ServerData")
            local active=folder and folder:FindFirstChild("ActiveEggs")
            pcall(function()
                stat:SetDesc(string.format("Cash: %s | Rebirths: %s | Luck: %s | Placed: %d | World Eggs: %d",
                    tostring(val(Saved,"Cash",0)),tostring(val(Saved,"Rebirths",0)),
                    tostring(val(Saved,"HatchUpgrades",0)),total,
                    active and #active:GetChildren() or 0))
                local petName
                if fastest then
                    petName=fastest.Model and (fastest.Model:GetAttribute("PetName") or fastest.Model.Name)
                    if not petName or type(PetData[petName])~="table" then
                        for name,config in pairs(PetData) do
                            if type(config)=="table" and fastest.Model
                                and fastest.Model.Name==name then petName=name;break end
                        end
                    end
                end
                best:SetDesc(fastest and ("Pet: "..tostring(petName or "Unknown")..
                    " | Income/s: "..tostring(fastest.Income or 0)) or "No pets found")
            end)
            task.wait(4)
        end
    end)

    for _,key in ipairs({
        "AutoDeliverEggs","AutoCollectCash","AutoRideFastest","AutoUnlockNests",
        "AutoFusePets","AutoClaimFusion","AutoClaimOfflineIndex",
        "AutoFarmHalloweenEvent","AutoHeadlessRitual","ShowEggDistance","ShowPetValue",
    }) do ctx.ConfigKeys[#ctx.ConfigKeys+1]=key end
    return {
        EnsureMount=ensureMount,
        IsMounted=mounted,
        FilterEggs=function(candidates)
            if S.EggFilterMode=="All" then return candidates end
            local filtered={}
            for _,egg in ipairs(candidates) do
                local found=S.SelectedEggs[egg.Name]==true
                if (S.EggFilterMode=="Whitelist" and found)
                    or (S.EggFilterMode=="Blacklist" and not found) then
                    filtered[#filtered+1]=egg
                end
            end
            return filtered
        end,
    }
end