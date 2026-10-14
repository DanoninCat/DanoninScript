return function(ctx)
    local S, LP, RS = ctx.S, ctx.Player, ctx.RS
    local C = ctx.Config
    local plotConfig=C.PlotUpgradeConfig or {}
    local treadmillConfig=C.TreadmillUpgradeConfig or {}
    local axeConfig=C.PickaxeConfig or {}
    local trailsConfig=C.TrailsConfig or {}
    local function cash()
        return tonumber(LP:GetAttribute("Cash")) or 0
    end
    local function number(obj,attr,fallback)
        local value=obj and obj:GetAttribute(attr)
        return type(value)=="number" and value or fallback
    end
    local function awaitChange(key, attr, obj, value)
        if not obj or not obj.Parent then return false end
        if not ctx.Throttle(key..":"..tostring(value),7) then return false end
        local before=obj:GetAttribute(attr)
        local ok=ctx.Remote(key)
        if not ok then return false end
        ctx.Status("Requested "..key.." (waiting for server)")
        return before
    end
    ctx.Worker("AutoUpgradePlot",3,function()
        local plot=ctx.Plot()
        if not plot then return end
        local level=number(plot,"PlotLevel",plotConfig.DefaultLevel or 1)
        local max=plotConfig.MaxLevel or 9
        if level>=max then return end
        local price=plotConfig.UpgradeCost and plotConfig.UpgradeCost(level)
        if type(price)=="number" and cash()>=price and ctx.Throttle("plot:"..level,7) then
            ctx.Remote("UpgradePlotRequest")
            ctx.Status("Upgrade Pen "..level.." requested")
        end
    end)
    ctx.Worker("AutoUpgradeTreadmill",3,function()
        local plot=ctx.Plot()
        if not plot then return end
        local level=number(plot,"TreadmillLevel",1)
        if level>= (treadmillConfig.MaxLevel or 9) then return end
        if plot:GetAttribute("TreadmillUnlocked")==false then
            local unlockCfg=ctx.Shared and ctx.Shared:FindFirstChild("TreadmillUnlockConfig")
            if unlockCfg then
                local ok,info=pcall(require,unlockCfg)
                local required=ok and (info.Cost or info.UnlockCost or info.Price)
                if type(required)=="number" and cash()>=required and ctx.Throttle("treadmill:unlock",8) then
                    ctx.Remote(info.UnlockRemote or "UnlockTreadmillRequest")
                end
            end
            return
        end
        local price=treadmillConfig.UpgradeCost and treadmillConfig.UpgradeCost(level)
        if type(price)=="number" and cash()>=price and ctx.Throttle("treadmill:"..level,8) then
            ctx.Remote("UpgradeTreadmillRequest")
            ctx.Status("Treadmill upgrade "..level.." requested")
        end
    end)
    local function ownedSet(attribute, equipped)
        local set = {}
        local initial = tonumber(equipped)
        if initial and initial > 0 then set[initial] = true end
        if type(attribute) == "string" then
            for value in attribute:gmatch("[^,]+") do
                local id = tonumber(value)
                if id then set[id] = true end
            end
        end
        return set
    end
    local function bestAffordable(items, owned, current, getId)
        local highestOwned = tonumber(current) or 0
        for id in pairs(owned) do
            if id > highestOwned then highestOwned = id end
        end
        local budget = cash()
        local best, bestId
        for index, item in ipairs(items) do
            local id = tonumber(getId(item, index))
            local price = tonumber(item.Price)
            if id and price and price <= budget and id > highestOwned
                and not owned[id] and (not bestId or id > bestId) then
                best, bestId = item, id
            end
        end
        return best, bestId
    end
    ctx.Worker("AutoBuyTrails", 4, function()
        local attrName = trailsConfig.OwnedAttribute or "OwnedTrails"
        local equippedName = trailsConfig.EquippedAttribute or "EquippedTrail"
        local equipped = tonumber(LP:GetAttribute(equippedName)) or 0
        local owned = ownedSet(LP:GetAttribute(attrName), equipped)
        local best, id = bestAffordable(trailsConfig.Trails or {}, owned, equipped, function(item)
            return item.Id
        end)
        if best and ctx.Throttle("trail:"..id, 8) then
            local ok = ctx.Remote("TrailShopRequest", "Buy", id)
            if ok then ctx.Status("Best affordable Trail requested: "..best.Name) end
        end
    end)
    ctx.Worker("AutoBuyPickaxe", 4, function()
        local tier = tonumber(LP:GetAttribute("PickaxeTier")) or axeConfig.DefaultTier or 1
        local owned = ownedSet(LP:GetAttribute("OwnedPickaxes"), tier)
        local best, id = bestAffordable(axeConfig.Tiers or {}, owned, tier, function(_, index)
            return index
        end)
        if best and ctx.Throttle("pickaxe:"..id, 8) then
            local ok = ctx.Remote("PickaxeShopRequest", "Buy", id)
            if ok then ctx.Status("Best affordable Pickaxe requested: "..best.Name) end
        end
    end)
    ctx.Worker("AutoPlaceBest",8,function()
        local plot=ctx.Plot()
        if not plot or plot:GetAttribute("RestoringPets")==true then return end
        if not ctx.Throttle("pets:equipbest",10) then return end
        local ok=ctx.Remote("PetsInventoryRemote","EquipBest",nil)
        if ok then ctx.Status("Equip Best requested; awaiting server state") end
    end)
    local function locateTreadmill(plot)
        if not plot then return nil end
        -- The native tutorial identifies owned machines by model name plus its Hitbox.
        for _, model in ipairs(plot:GetChildren()) do
            if model:IsA("Model") and model.Name ~= "TreadmillBoard"
                and string.find(model.Name, "Treadmill", 1, true) then
                local hitbox = model:FindFirstChild("Hitbox")
                if hitbox and hitbox:IsA("BasePart") then
                    return hitbox
                end
            end
        end
        return nil
    end
    ctx.Worker("AutoTrainTreadmill", 0.85, function()
        if not ctx.CanMove("Train") or ctx.InHell() then return end
        local plot = ctx.Plot()
        if not plot then S.Step="Train: waiting for Pen"; return end
        local hitbox = locateTreadmill(plot)
        if not hitbox then
            S.Step = "Train: treadmill not replicated or unlocked"
            return
        end
        local root, hum = ctx.Root()
        if not root then return end
        local goal = hitbox.Position + Vector3.new(0, hitbox.Size.Y / 2 + math.max(2,hum.HipHeight), 0)
        local delta = root.Position - goal
        if Vector3.new(delta.X, 0, delta.Z).Magnitude > 1.75 or math.abs(delta.Y) > 3.5 then
            ctx.Move("Train", goal, 0, true)
            S.Step = "Training: positioning on treadmill"
            return
        end
        local speed = ctx.Config.SpeedConfig or {}
        if LP:GetAttribute(speed.InUseAttribute or "TreadmillInUse") == true then
            S.Step = "Training: active on treadmill"
        else
            S.Step = "Training: positioned; waiting for server session"
        end
    end)
end
