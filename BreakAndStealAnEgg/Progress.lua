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
    local function ownedTrail(id)
        local attr=LP:GetAttribute(trailsConfig.OwnedAttribute or "OwnedTrails")
        if type(attr)=="table" then return attr[id]==true or attr[tostring(id)]==true end
        if type(attr)=="string" then
            local ok, arr=pcall(ctx.HttpService.JSONDecode,ctx.HttpService,attr)
            if ok and type(arr)=="table" then
                for k,v in pairs(arr) do
                    if tonumber(k)==id and v==true or tonumber(v)==id then return true end
                end
            end
            for n in attr:gmatch("%d+") do if tonumber(n)==id then return true end end
        end
        return false
    end
    ctx.Worker("AutoBuyTrails",4,function()
        local list=trailsConfig.Trails or {}
        for _,item in ipairs(list) do
            if S.SelectedTrails[item.Name] and not ownedTrail(item.Id)
                and type(item.Price)=="number" and item.Price<=cash() then
                if ctx.Throttle("trail:"..tostring(item.Id),9) then
                    ctx.Remote("TrailShopRequest","Buy",item.Id)
                    ctx.Status("Buy Trail: "..tostring(item.Name))
                end
                break
            end
        end
    end)
    ctx.Worker("AutoBuyPickaxe",4,function()
        local current=number(LP,"PickaxeTier",axeConfig.DefaultTier or 1)
        for tier,item in ipairs(axeConfig.Tiers or {}) do
            if tier>current and S.SelectedPickaxes[item.Name]
                and type(item.Price)=="number" and item.Price<=cash() then
                if ctx.Throttle("pickaxe:"..tier,9) then
                    ctx.Remote("PickaxeShopRequest","Buy",tier)
                    ctx.Status("Buy Pickaxe: "..tostring(item.Name))
                end
                break
            end
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
        for _,obj in ipairs(plot:GetDescendants()) do
            if obj.Name=="Treadmill" and obj:IsA("BasePart") then return obj end
            if obj.Name=="Treadmill" and obj:IsA("Model") then
                local part=obj:FindFirstChild("Run",true)
                    or obj:FindFirstChild("Belt",true)
                    or obj.PrimaryPart
                if part and part:IsA("BasePart") then return part end
            end
        end
        return nil
    end
    ctx.Worker("AutoTrainTreadmill",1.3,function()
        if not ctx.CanMove("Train") or ctx.InHell() then return end
        local plot=ctx.Plot()
        if not plot then S.Step="Train: waiting for Pen";return end
        local target=locateTreadmill(plot)
        if not target then
            S.Step="Train: treadmill not replicated/unlocked"
            return
        end
        local root,hum=ctx.Root()
        if not root then return end
        local pos=target.Position+Vector3.new(0,target.Size.Y/2+2,0)
        if (root.Position-pos).Magnitude>5 then
            ctx.Move("Train",pos,0)
        end
        S.Step="Training: checking treadmill session"
    end)
end