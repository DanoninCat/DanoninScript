if game.PlaceId ~= 124216119978534 and game.GameId ~= 124216119978534 then return end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer
local Env = (getgenv and getgenv()) or _G
if type(Env.__CE_SETTING_PET_CLEANUP) == "function" then pcall(Env.__CE_SETTING_PET_CLEANUP) end

local source = Env.__CE_F_91A7
assert(type(source) == "string" and #source > 0, "Setting up a Pet: use the main Loader")
local Fluent = assert(loadstring(source))()
local Game = RS:WaitForChild("Remotes", 12):WaitForChild("Game", 12)
local Data = RS:WaitForChild("GameData", 12)
local Services = RS:WaitForChild("GameServices", 12)
local Saved = LP:WaitForChild("SavedData", 12)
assert(Game and Data and Services and Saved, "Setting up a Pet: game data unavailable")

local function module(folder, name)
    local object = folder and folder:FindFirstChild(name)
    if not object or not object:IsA("ModuleScript") then return {} end
    local ok, result = pcall(require, object)
    return ok and result or {}
end

local EggData = module(Data, "Eggs")
local FoodData = module(Data, "Foods")
local ShopData = module(Data, "Shop")
local PetData = module(Data, "Pets")
local MutationData = module(Data, "Mutations")
local PetAging = module(Services, "PetAging")
local General = module(Services, "General")
local GeneralData = module(Data, "General")
local DayNight = module(Services, "DayNight")
local RebirthData = module(Data, "Rebirths")
local IndexData = module(Data, "IndexRewards")
local HalloweenData = module(Data, "Halloween")
local HalloweenEvent = module(Services, "HalloweenEvent")
local HatchLuck = module(Data, "HatchLuck")
local petFolder = LP:FindFirstChild("PlayerScripts")
petFolder = petFolder and petFolder:FindFirstChild("Game")
petFolder = petFolder and petFolder:FindFirstChild("Pets")
local Renderer = module(petFolder, "PetRenderer")

local S = {
    Running = true, AutoCollectEggs = false, EggsESP = false, AutoHatch = false,
    AutoLuckUpgrade = false, AutoFeed = false, AutoPlaceBest = false,
    AutoRebirth = false, AutoBuyItems = false, AutoBuyFood = false,
    AutoCollectCandy = false, AutoBuyHalloweenEggs = false,
    AutoSearchPumpkins = false, RitualAssistant = false, AutoClaimIndex = false,
    EggPriority = "Rarest", EggMinRarity = "Common", FoodChoice = "Any Available",
    SelectedItems = {}, SelectedFoods = {}, LastError = "", LastAction = "Ready",
    ConfigFile = "CATEMPIRE_SettingUpAPet.json", Movement = false, BusyPlaceBest = false,
}
local Toggles, Links, EggVisuals, RitualVisuals, Requests = {}, {}, {}, {}, {}
local RarityOrder = {
    Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5,
    Mythic = 6, Mythical = 6, Divine = 7, Secret = 8, Ethereal = 9,
}
local Window, Status, ShopItemDropdown, FoodDropdown

local function notify(message)
    pcall(function() Fluent:Notify({Title="CAT EMPIRE", Content=tostring(message), Duration=4}) end)
end
local function status(action)
    S.LastAction = tostring(action)
end
local function remote(name, ...)
    local endpoint = Game:FindFirstChild(name)
    if not endpoint then S.LastError = "Missing " .. name; return false end
    local args = table.pack(...)
    local ok, result = pcall(function()
        if endpoint:IsA("RemoteEvent") then
            endpoint:FireServer(table.unpack(args, 1, args.n))
            return true
        elseif endpoint:IsA("RemoteFunction") then
            return endpoint:InvokeServer(table.unpack(args, 1, args.n))
        end
        error("Unexpected remote type for " .. name)
    end)
    if not ok then S.LastError = name .. ": " .. tostring(result) end
    return ok, result
end
local function due(id, seconds)
    local t = os.clock()
    if (Requests[id] or 0) > t then return false end
    Requests[id] = t + seconds
    return true
end
local function value(parent, name, default)
    local object = parent and parent:FindFirstChild(name)
    return object and object:IsA("ValueBase") and object.Value or default
end
local function getRoot()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root or not hum or hum.Health <= 0 then return nil end
    return root, hum
end
local function positionOf(instance)
    if not instance or not instance.Parent then return nil end
    if instance:IsA("ProximityPrompt") then return positionOf(instance.Parent) end
    if instance:IsA("Attachment") then return instance.WorldPosition end
    if instance:IsA("BasePart") then return instance.Position end
    if instance:IsA("Model") then
        local ok, pivot = pcall(function() return instance:GetPivot() end)
        if ok then return pivot.Position end
    end
    return nil
end
local function getPlot()
    if type(General) == "table" and type(General.GetPlot) == "function" then
        local ok, plot = pcall(General.GetPlot, General, LP)
        if ok then return plot end
    end
    return nil
end
local function eventLive()
    if type(HalloweenEvent) == "table" and type(HalloweenEvent.IsLive) == "function" then
        local ok, active = pcall(HalloweenEvent.IsLive)
        return ok and active == true
    end
    return false
end

local function eggRarity(name)
    local config = EggData[name]
    local rarity = type(config) == "table" and config.Rarity or nil
    return RarityOrder[rarity] and rarity or "Common"
end
local function eggRank(name)
    return RarityOrder[eggRarity(name)] or 1
end
local function claimed(name, record, cycles)
    if record:GetAttribute("AdminSpawn") == true then
        local id = record:GetAttribute("AdminEggId")
        local owned = LP:GetAttribute("CollectedAdminEggs")
        return type(id) == "string" and type(owned) == "string"
            and owned:find("," .. id .. ",", 1, true) ~= nil
    end
    local cycle = tonumber(record:GetAttribute("Cycle"))
    if cycle and tonumber(cycles[name]) and cycle <= tonumber(cycles[name]) then return true end
    local text = LP:GetAttribute("CollectedEggs")
    return type(text) == "string" and text:find(name .. ",", 1, true) ~= nil
end
local function collectedCycles()
    local raw = LP:GetAttribute("CollectedEggCycles")
    if type(raw) ~= "string" then return {} end
    local ok, result = pcall(HttpService.JSONDecode, HttpService, raw)
    return ok and type(result) == "table" and result or {}
end
local EggCycle = {Stage="idle", Started=0, Id=nil, Name=nil, Origin=nil}
local EggBlocked = {}
local EggWorldMarkers = {}
local CandyCycle = {Stage="idle", Started=0, Target=nil, LastCarry=0}
local CandyBlocked = {}
local CandySuppressed = setmetatable({}, {__mode="k"})
local CandyDepositAckAt = 0
local function teleportNear(pos, offset)
    local root,hum=getRoot()
    if not root or typeof(pos)~="Vector3" then return false end
    if hum.Sit then hum.Sit=false end
    local destination=pos+(offset or Vector3.new(0,3,2))
    local forward=root.CFrame.LookVector
    forward=Vector3.new(forward.X,0,forward.Z)
    if forward.Magnitude<0.01 then forward=Vector3.new(0,0,-1) end
    pcall(function()
        root.AssemblyLinearVelocity=Vector3.zero
        root.AssemblyAngularVelocity=Vector3.zero
    end)
    root.CFrame=CFrame.lookAt(destination,destination+forward.Unit,Vector3.yAxis)
    return true
end
local function interactAt(pos,source)
    local root=getRoot()
    if not root or typeof(pos)~="Vector3" then return false end
    local chosen,best=nil,math.huge
    local function inspect(prompt)
        if not prompt:IsA("ProximityPrompt") or not prompt.Enabled then return end
        local p=positionOf(prompt)
        if not p then return end
        local d=(p-pos).Magnitude
        if d<best and d<=15 and (root.Position-p).Magnitude<=prompt.MaxActivationDistance+2 then
            chosen,best=prompt,d
        end
    end
    if source then
        if source:IsA("ProximityPrompt") then inspect(source) end
        for _,obj in ipairs(source:GetDescendants()) do inspect(obj) end
    end
    if not chosen then
        for _,part in ipairs(workspace:GetPartBoundsInRadius(pos,14)) do
            for _,obj in ipairs(part:GetDescendants()) do inspect(obj) end
        end
    end
    if not chosen then return false end
    local native=(type(Env)=="table" and Env.fireproximityprompt) or fireproximityprompt
    if type(native)=="function" and pcall(native,chosen) then return true end
    local ok,service=pcall(function() return game:GetService("VirtualInputManager") end)
    if ok and service then
        return pcall(function()
            service:SendKeyEvent(true,Enum.KeyCode.E,false,game)
            task.wait(math.max(.1,chosen.HoldDuration+.05))
            service:SendKeyEvent(false,Enum.KeyCode.E,false,game)
        end)
    end
    return false
end
local function localCandy()
    local runtime = LP:FindFirstChild("NoSaveData")
    return tonumber(value(runtime, "CarriedCandy", 0)) or 0
end
local function depositPosition()
    for _, marker in ipairs(CollectionService:GetTagged("HalloweenCandyDeposit")) do
        if marker:IsDescendantOf(workspace) then
            if marker:IsA("BasePart") then
                local top = marker.Size.Y * .5
                return marker.Position + Vector3.new(0, math.max(2, top + 2), 0)
            elseif marker:IsA("Model") then
                local ok, cf, size = pcall(function() return marker:GetBoundingBox() end)
                if ok then return cf.Position + Vector3.new(0, size.Y * .5 + 2, 0) end
            end
        end
    end
    local fallback = workspace:FindFirstChild("HalloweenHomeAnchor")
    return fallback and positionOf(fallback) or nil
end
local function eggCandidates()
    local data = RS:FindFirstChild("ServerData")
    local active = (data and data:FindFirstChild("ActiveEggs")) or RS:FindFirstChild("ActiveEggs")
    local root = getRoot()
    if not root or not active then return {} end
    local candidates, cycles = {}, collectedCycles()
    for _, record in ipairs(active:GetChildren()) do
        local name = record:GetAttribute("Egg")
        local pos = record:GetAttribute("Position")
        local owner = record:GetAttribute("PrivateTo")
        local drop = tonumber(record:GetAttribute("DropEndsAt")) or 0
        if type(name) == "string" and typeof(pos) == "Vector3"
            and (owner == nil or owner == LP.UserId)
            and drop <= workspace:GetServerTimeNow()
            and eggRank(name) >= (RarityOrder[S.EggMinRarity] or 1)
            and not claimed(name, record, cycles)
            and (EggBlocked[record.Name] or 0) <= os.clock() then
            candidates[#candidates + 1] = {
                Id = record.Name, Name = name, Pos = pos,
                Rank = eggRank(name),
                Weight = tonumber(record:GetAttribute("Weight")) or 0,
                Distance = (root.Position - pos).Magnitude,
            }
        end
    end
    table.sort(candidates, function(a,b)
        if S.EggPriority == "Nearest" then return a.Distance < b.Distance end
        if S.EggPriority == "Heaviest" then
            if a.Weight ~= b.Weight then return a.Weight > b.Weight end
        else
            if a.Rank ~= b.Rank then return a.Rank > b.Rank end
        end
        return a.Distance < b.Distance
    end)
    return candidates
end

local function walkTo(pos, range)
    local root, hum = getRoot()
    if not root or typeof(pos) ~= "Vector3" then return false end
    if (root.Position - pos).Magnitude <= range then return true end
    if not S.Movement and due("walk", 0.9) then
        hum:MoveTo(pos)
        status("Moving to target")
    end
    return false
end
local function collectEggs()
    local now = os.clock()
    if EggCycle.Stage == "idle" then
        if not S.AutoCollectEggs then return false end
        local egg = eggCandidates()[1]
        if not egg then return false end
        local root = getRoot()
        if not root then return false end
        EggCycle = {
            Stage="pickup", Started=now, Id=egg.Id, Name=egg.Name,
            Position=egg.Pos, Origin=root.CFrame,
        }
        status("Collect Egg: " .. egg.Name)
    end
    local cycle = EggCycle
    if cycle.Stage=="pickup" then
        if not S.AutoCollectEggs or now-cycle.Started>6 then
            cycle.Stage="return"
        elseif not teleportNear(cycle.Position) then
            cycle.Stage="return"
        else
            cycle.Stage="interact"
            cycle.Started=now
        end
    elseif cycle.Stage=="interact" then
        if now-cycle.Started>=0.45 then
            cycle.Stage="await"
            cycle.Started=now
            local prompted=interactAt(cycle.Position,workspace:FindFirstChild("RenderedEggs"))
            local ok=prompted or remote("EggPickup",cycle.Id)
            if not ok then cycle.Stage="return" end
        end
    elseif cycle.Stage == "await" then
        if now-cycle.Started>4 or not S.AutoCollectEggs then cycle.Stage="return" end
    end
    if cycle.Stage=="return" then
        if not cycle.ReturnAt then
            cycle.ReturnAt=now
            cycle.LastReturnAttempt=0
            status("Returning to plot")
        end
        local root=getRoot()
        local plot=getPlot()
        local base=plot and plot:FindFirstChild("Baseplate")
        local nearPlot=base and root
            and math.abs(root.Position.X-base.Position.X)<=base.Size.X/2+8
            and math.abs(root.Position.Z-base.Position.Z)<=base.Size.Z/2+8
            and math.abs(root.Position.Y-base.Position.Y)<=base.Size.Y/2+14
        if nearPlot then
            cycle.FirstAtPlot=cycle.FirstAtPlot or now
            if now-cycle.FirstAtPlot>=1.1 then
                EggCycle={Stage="idle",Started=0}
                status("Returned to plot")
                return false
            end
        else
            cycle.FirstAtPlot=nil
            if now-cycle.LastReturnAttempt>1.8 then
                cycle.LastReturnAttempt=now
                if base and base:IsA("BasePart") then
                    -- Retorno local enquanto transporta um ovo: teleporte nativo bloqueado.
                    teleportNear(base.Position,Vector3.new(0,base.Size.Y/2+3,0))
                elseif cycle.Origin and root then
                    teleportNear(cycle.Origin.Position,Vector3.zero)
                else
                    remote("TeleportToPlot")
                end
            end
        end
        if now-cycle.ReturnAt>10 then
            EggCycle={Stage="idle",Started=0}
            status("Plot return not confirmed: possible server restriction")
            return false
        end
    end
    return true
end

local eggResponse = Game:FindFirstChild("EggPickup")
if eggResponse and eggResponse:IsA("RemoteEvent") then
    Links[#Links+1]=eggResponse.OnClientEvent:Connect(function(result, eggName, eggId)
        if EggCycle.Stage~="await" then return end
        if eggId ~= nil and tostring(eggId)~=tostring(EggCycle.Id)
            and tostring(eggName)~=tostring(EggCycle.Name) then return end
        if result=="PickedUp" then
            status("Egg collected: "..tostring(eggName))
            EggCycle.HasEgg=true
            EggCycle.Stage="return"
        elseif result=="Refused" or result=="BasketFull" then
            EggBlocked[EggCycle.Id]=os.clock()+(result=="BasketFull" and 18 or 10)
            status("Egg pickup refused: "..tostring(eggName))
            EggCycle.Stage="return"
        end
    end)
end

local function readyEgg(egg)
    local key = egg:GetAttribute("EggKey")
    local config = EggData[egg.Name]
    local details = egg:FindFirstChild("EggData")
    local place = details and details:FindFirstChild("PlaceTime")
    if type(key) ~= "string" or type(config) ~= "table" or not place then return false end
    if LP:GetAttribute("TutorialHatchLocked") == true then
        local only = LP:GetAttribute("TutorialLockedEggKey")
        if only ~= nil and only ~= key then return false end
    end
    local weight = tonumber(value(details,"Weight",1)) or 1
    if type(GeneralData.GrowthTimeFor) ~= "function" then return false end
    local ok, duration = pcall(GeneralData.GrowthTimeFor, config.GrowthTime, weight)
    if not ok or type(duration) ~= "number" then return false end
    local elapsed = workspace:GetServerTimeNow() - tonumber(place.Value)
    if egg:GetAttribute("FlatGrow") ~= true and type(DayNight.GrowthElapsed) == "function" then
        local good, time = pcall(DayNight.GrowthElapsed, place.Value)
        if good and type(time) == "number" then elapsed = time end
    end
    return elapsed >= duration
end
local function hatchReady()
    local plot = getPlot()
    local eggs = plot and plot:FindFirstChild("Eggs")
    if not eggs then return end
    for _, egg in ipairs(eggs:GetChildren()) do
        if readyEgg(egg) then
            local key = egg:GetAttribute("EggKey")
            if due("hatch:" .. key, 8) then
                remote("Hatch", {EggKey = key})
                status("Hatching " .. egg.Name)
                return
            end
        end
    end
end
local LuckState = {Pending = nil, Until = 0, RetryAt = 0}
local function luckUpgrade()
    local now = os.clock()
    if LP:GetAttribute("Setting_LuckMultiplier") == false then
        status("Enable Luck Multiplier in game settings")
        return
    end
    local current = tonumber(value(Saved, "HatchUpgrades", nil))
    local free = tonumber(value(Saved, "FreeHatchUpgrades", 0)) or 0
    local used = tonumber(value(Saved, "UsedFreeHatchUpgrades", 0)) or 0
    local cash = tonumber(value(Saved, "Cash", 0)) or 0
    if not current or not Game:FindFirstChild("Plot") then return end
    local upgrades = Game.Plot:FindFirstChild("Upgrades")
    if not upgrades or not upgrades:IsA("RemoteEvent") then
        S.LastError = "Game.Plot.Upgrades is unavailable"
        return
    end
    if LuckState.Pending ~= nil then
        if current > LuckState.Pending then
            LuckState.Pending = nil
            LuckState.RetryAt = now + 1.5
            status("Luck upgraded to " .. tostring(current))
        elseif now < LuckState.Until then
            return
        else
            LuckState.Pending = nil
            LuckState.RetryAt = now + 12
            status("Luck: server did not confirm upgrade")
            return
        end
    end
    if now < LuckState.RetryAt then return end
    local argument
    if free > 0 then
        argument = "MaxFree"
    else
        if type(HatchLuck.GetPrice) ~= "function"
            or type(HatchLuck.GetPaidUpgrades) ~= "function" then
            S.LastError = "HatchLuck price methods unavailable"
            return
        end
        local ok, price = pcall(function()
            return HatchLuck.GetPrice(HatchLuck.GetPaidUpgrades(current, used))
        end)
        if not ok or type(price) ~= "number" or price < 0 then return end
        if cash < price then
            LuckState.RetryAt = now + 6
            return
        end
        if type(HatchLuck.GetMaxAffordable) == "function" then
            local affordableOk, count = pcall(HatchLuck.GetMaxAffordable,
                HatchLuck.GetPaidUpgrades(current, used), cash)
            if affordableOk and type(count) == "number" and count >= 2 then
                argument = "Max"
            end
        end
    end
    LuckState.Pending = current
    LuckState.Until = now + 6
    local ok, err = pcall(function()
        if argument then upgrades:FireServer(argument) else upgrades:FireServer() end
    end)
    if not ok then
        S.LastError = tostring(err)
        LuckState.Pending = nil
        LuckState.RetryAt = now + 12
    else
        status("Luck upgrade sent: " .. tostring(argument or "Single"))
    end
end

local function incomeOf(tool)
    local name = tool:GetAttribute("PetName") or tool.Name
    local config = PetData[name]
    local base = type(config) == "table" and tonumber(config.Income) or 0
    if not base or base <= 0 then return 0 end
    local unit = tonumber(PetAging.WeightStandardKG) or 1
    local income = math.floor(base * (tonumber(tool:GetAttribute("Weight")) or 1) / math.max(unit, .01))
    if type(MutationData.CombinedFactor) == "function" then
        local ok, multi = pcall(MutationData.CombinedFactor, tool:GetAttribute("Mutation"), tool:GetAttribute("SpawnMutation"))
        if ok and type(multi) == "number" then income = income * multi end
    end
    return income
end
local function ownedPets()
    local found, present = {}, {}
    if type(Renderer.GetAll) == "function" then
        local ok, pets = pcall(Renderer.GetAll)
        if ok and type(pets) == "table" then
            for _, pet in pairs(pets) do
                if pet.OwnerUserId == LP.UserId and pet.Model and pet.Model.Parent and pet.PetKey then
                    present[pet.PetKey] = true
                    found[#found + 1] = {
                        Key=pet.PetKey, Placed=true, Income=tonumber(pet.DisplayIncome) or 0,
                        Name=pet.Model:GetAttribute("PetName") or pet.PetName
                            or (type(PetData[pet.Model.Name])=="table" and pet.Model.Name)
                            or (type(pet.Name)=="string" and type(PetData[pet.Name])=="table" and pet.Name),
                        Position=positionOf(pet.Model), Model=pet.Model,
                    }
                end
            end
        end
    end
    for _, parent in ipairs({LP.Character, LP:FindFirstChildOfClass("Backpack")}) do
        if parent then
            for _, tool in ipairs(parent:GetChildren()) do
                local key = tool:GetAttribute("PetKey")
                if tool:IsA("Tool") and key and not present[key] then
                    present[key] = true
                    found[#found + 1] = {Key=key, Placed=false, Income=incomeOf(tool), Tool=tool}
                end
            end
        end
    end
    table.sort(found, function(a,b) return a.Income > b.Income end)
    return found
end
local function placeBest()
    if S.BusyPlaceBest then return end
    local root, hum = getRoot()
    local plot = getPlot()
    local plate = plot and plot:FindFirstChild("Baseplate")
    if not root or not plate or (plate.Position - root.Position).Magnitude > math.max(plate.Size.X, plate.Size.Z) then return end
    S.BusyPlaceBest = true
    local ok, err = pcall(function()
        local all = ownedPets()
        local count = math.min(tonumber(LP:GetAttribute("MaxPets")) or 5, #all)
        local best, reuse = {}, {}
        for i=1,count do best[all[i].Key]=true end
        for _, pet in ipairs(all) do
            if not S.Running or not S.AutoPlaceBest then break end
            if pet.Placed and not best[pet.Key] then
                if pet.Position then reuse[#reuse+1]=pet.Position end
                remote("PickupPet", pet.Key)
                task.wait(.25)
            end
        end
        for i=1,count do
            if not S.Running or not S.AutoPlaceBest then break end
            local pet = all[i]
            if pet and not pet.Placed and pet.Tool and pet.Tool.Parent then
                hum:EquipTool(pet.Tool)
                task.wait(.3)
                if pet.Tool.Parent == LP.Character then
                    local offset = Vector3.new(((i-1)%3-1)*4,0,-(math.floor((i-1)/3)*4+8))
                    local pos = table.remove(reuse,1) or root.CFrame:PointToWorldSpace(offset)
                    local p = plate.CFrame:PointToObjectSpace(pos)
                    pos = plate.CFrame:PointToWorldSpace(Vector3.new(
                        math.clamp(p.X,-plate.Size.X/2+2,plate.Size.X/2-2), p.Y,
                        math.clamp(p.Z,-plate.Size.Z/2+2,plate.Size.Z/2-2)))
                    remote("PlacePet", pet.Key, pos, "PlaceBest")
                    task.wait(.25)
                end
            end
        end
    end)
    S.BusyPlaceBest = false
    if not ok then S.LastError = tostring(err) end
end
local function feedPets()
    local food = S.FoodChoice
    local found
    for _, parent in ipairs({LP.Character, LP:FindFirstChildOfClass("Backpack")}) do
        if parent then
            for _, tool in ipairs(parent:GetChildren()) do
                if tool:IsA("Tool") and FoodData[tool.Name]
                    and (food == "Any Available" or tool.Name == food) then
                    found=tool
                    break
                end
            end
        end
        if found then break end
    end
    if not found then return end
    local _, hum = getRoot()
    if not hum then return end
    if found.Parent ~= LP.Character then hum:EquipTool(found); task.wait(.25) end
    if found.Parent ~= LP.Character then return end
    for _, pet in ipairs(ownedPets()) do
        if pet.Placed and due("feed:"..tostring(pet.Key), 24) then
            remote("FeedPet", pet.Key, found.Name)
            status("Feeding " .. tostring(pet.Key))
            return
        end
    end
end
local function rebirth()
    local current = tonumber(value(Saved,"Rebirths",0)) or 0
    local cash = tonumber(value(Saved,"Cash",0)) or 0
    if (tonumber(RebirthData.Cap) or math.huge) <= current then return end
    if type(RebirthData.GetCost) ~= "function" then return end
    local ok, cost = pcall(RebirthData.GetCost,current)
    if not ok or type(cost)~="number" or cash<cost then return end
    local required = type(GeneralData.RebirthRequirements)=="table" and
        GeneralData.RebirthRequirements[math.clamp(current+1,1,#GeneralData.RebirthRequirements)]
    if type(required) ~= "string" then return end
    local hasPet = false
    for _,pet in ipairs(ownedPets()) do
        if pet.Placed and pet.Model and pet.Model.Name == required then hasPet = true; break end
        if pet.Tool and (pet.Tool:GetAttribute("PetName") == required or
            (pet.Tool.Name:match("^(.-) %[") or pet.Tool.Name) == required) then hasPet = true; break end
    end
    if hasPet and due("rebirth:" .. current, 25) then remote("Rebirth"); status("Rebirth requested") end
end

local function normalizeChoice(value)
    local selected = {}
    if type(value) == "table" then
        for k,v in pairs(value) do
            if type(k)=="string" and v==true then selected[k]=true
            elseif type(v)=="string" then selected[v]=true end
        end
    end
    return selected
end
local function shopLists()
    local items, foods = {}, {}
    if type(ShopData.Categories) ~= "table" then return items,foods end
    for category, entries in pairs(ShopData.Categories) do
        if type(entries)=="table" then
            for item in pairs(entries) do
                if type(item)=="string" then
                    local id=tostring(category).." / "..item
                    if tostring(category):lower():find("food") then
                        foods[#foods+1]=id
                    else items[#items+1]=id end
                end
            end
        end
    end
    table.sort(items); table.sort(foods)
    return items,foods
end
local function applyNativeAutobuy(category, selections, enabled)
    local count = 0
    for id in pairs(selections) do
        local c, item = id:match("^(.-) / (.+)$")
        if c and item and ShopData.Categories and ShopData.Categories[c]
            and ShopData.Categories[c][item] then
            remote("Autobuy", c, item, enabled == true)
            count=count+1
            task.wait(.12)
        end
    end
    status((enabled and "Enabled " or "Disabled ") .. count .. " autobuy items")
end
local function refreshNativeAutobuy(category)
    if category=="food" then applyNativeAutobuy(category,S.SelectedFoods,S.AutoBuyFood)
    else applyNativeAutobuy(category,S.SelectedItems,S.AutoBuyItems) end
end

local HalloweenEntrance = {LastTry=0, Pending=false}
local function enterHalloween()
    if not S.AutoFarmHalloweenEvent or not eventLive()
        or LP:GetAttribute("InHalloweenZone")==true then
        HalloweenEntrance.Pending=false
        return false
    end
    local current=os.clock()
    if current-HalloweenEntrance.LastTry<2.5 then return true end
    HalloweenEntrance.LastTry=current
    local best,bestPos,score
    local function consider(prompt)
        if not prompt:IsA("ProximityPrompt") or not prompt.Enabled then return end
        if prompt.ActionText~="Enter" and prompt.ActionText~="Entrar" then return end
        local host=prompt.Parent
        local text=tostring(host and host:GetFullName() or ""):lower()
        if not text:find("halloween",1,true)
            and not text:find("portal",1,true) then return end
        local pos=positionOf(prompt)
        local root=getRoot()
        if not pos or not root then return end
        local d=(root.Position-pos).Magnitude
        if not score or d<score then best,bestPos,score=prompt,pos,d end
    end
    for _,tag in ipairs({"HalloweenEntrance","HalloweenPortal","HalloweenEnterPrompt"}) do
        for _,obj in ipairs(CollectionService:GetTagged(tag)) do
            if obj:IsA("ProximityPrompt") then consider(obj) end
            for _,desc in ipairs(obj:GetDescendants()) do consider(desc) end
        end
    end
    if not best then
        for _,obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then consider(obj) end
        end
    end
    if not best then
        status("Halloween entrance not found")
        return true
    end
    teleportNear(bestPos,Vector3.new(0,2,0))
    local acted=interactAt(bestPos,best)
    HalloweenEntrance.Pending=acted
    status(acted and "Entering Halloween; awaiting zone confirmation" or "Halloween entrance interaction unavailable")
    return true
end
local function collectCandy()
    if not eventLive() then return false end
    local now=os.clock()
    local carried=localCandy()
    local cycle=CandyCycle
    if not S.AutoFarmHalloweenEvent and carried<=0 then
        CandyCycle={Stage="idle",Started=0,LastCarry=0}
        return false
    end
    if carried>0 or cycle.Stage=="deposit" then
        local target=depositPosition()
        if not target then
            status("Halloween deposit unavailable")
            return true
        end
        if carried<=0 and (CandyDepositAckAt>=cycle.Started
            or (cycle.LastCarry>0 and now-cycle.Started>0.4)) then
            CandyCycle={Stage="idle",Started=now,LastCarry=0}
            status("Halloween candy deposited")
            return false
        end
        if cycle.Stage~="deposit" then
            cycle.Stage="deposit"
            cycle.Started=now
            cycle.LastCarry=carried
        end
        local root=getRoot()
        if root and (root.Position-target).Magnitude>7 and due("candyDepositMove",1.1) then
            teleportNear(target,Vector3.new(0,0,0))
            status("Returning to Halloween candy deposit")
        end
        if now-cycle.Started>12 then
            cycle.Started=now
            status("Awaiting Halloween candy deposit")
        end
        return true
    end
    if cycle.Stage=="approach" then
        if not cycle.TargetInstance or not cycle.TargetInstance:IsDescendantOf(workspace)
            or cycle.TargetInstance:GetAttribute("Collected")==true then
            if cycle.Target then CandyBlocked[cycle.Target]=now+20 end
            CandyCycle={Stage="idle",Started=now,LastCarry=0}
            return false
        end
        if now-cycle.Started<0.45 then return true end
        local prompted=interactAt(cycle.Position,cycle.TargetInstance)
        local ok=prompted or remote("CollectCandy",cycle.Target)
        CandyBlocked[cycle.Target]=now+20
        cycle.Stage="await"
        cycle.Started=now
        if not ok then
            CandyBlocked[cycle.Target]=now+8
            cycle.Stage="idle"
        end
        return true
    end
    if cycle.Stage=="await" then
        if carried>cycle.LastCarry
            or not cycle.TargetInstance
            or not cycle.TargetInstance:IsDescendantOf(workspace) then
            if cycle.TargetInstance then
                CandySuppressed[cycle.TargetInstance]={
                    Stamp=cycle.TargetInstance:GetAttribute("SpawnAt")
                        or cycle.TargetInstance:GetAttribute("SpawnCycle"),
                }
            end
            CandyCycle={Stage="idle",Started=now,LastCarry=carried}
            status("Halloween Candy collected")
            return false
        end
        if now-cycle.Started<=3 then return true end
        if cycle.Target then CandyBlocked[cycle.Target]=now+22 end
        CandyCycle={Stage="idle",Started=now,LastCarry=0}
        return false
    end
    if LP:GetAttribute("InHalloweenZone")~=true then return false end
    local nearest,dist
    local root=getRoot()
    if not root then return false end
    for _,inst in ipairs(CollectionService:GetTagged("HalloweenCandySpawn")) do
        local id=inst:GetAttribute("Id")
        if type(id)~="string" or id=="" then id=inst:GetFullName() end
        local suppressed=CandySuppressed[inst]
        local currentStamp=inst:GetAttribute("SpawnAt") or inst:GetAttribute("SpawnCycle")
        if suppressed and currentStamp and currentStamp~=suppressed.Stamp then
            CandySuppressed[inst]=nil
            suppressed=nil
        end
        if inst:IsA("BasePart") and inst:IsDescendantOf(workspace)
            and not suppressed
            and inst:GetAttribute("SpawnReady")~=false
            and inst:GetAttribute("Collected")~=true
            and inst:GetAttribute("Taken")~=true
            and inst:GetAttribute("Available")~=false
            and (CandyBlocked[id] or 0)<=now then
            local distance=(inst.Position-root.Position).Magnitude
            if not dist or distance<dist then nearest={Instance=inst,Id=id};dist=distance end
        end
    end
    if not nearest then return false end
    if nearest.Instance:IsDescendantOf(workspace)
        and teleportNear(nearest.Instance.Position) then
        local id=nearest.Id
        CandyCycle={
            Stage="approach",Target=id,TargetInstance=nearest.Instance,
            Position=nearest.Instance.Position,Started=now,LastCarry=0
        }
        status("Approaching Halloween candy")
    end
    return true
end
local depositRemote=Game:FindFirstChild("HalloweenCandyDeposited")
if depositRemote and depositRemote:IsA("RemoteEvent") then
    Links[#Links+1]=depositRemote.OnClientEvent:Connect(function()
        CandyDepositAckAt=os.clock()
    end)
end

local function buyHalloween()
    if not eventLive() then return end
    local config = type(HalloweenData.Eggs)=="table" and HalloweenData.Eggs["Halloween Egg"]
    local price = config and tonumber(config.Price)
    if not price or price<=0 then return end
    local currency = tonumber(value(Saved,"HalloweenCandy",0)) or 0
    if currency < price or not due("halloweenBuy", 4) then return end
    local ok, result = remote("BuyHalloweenEgg","Halloween Egg")
    if ok and result==true then status("Halloween Egg bought") end
end
local function claimIndex()
    if type(IndexData.StageAt)~="function" or type(IndexData.DiscoveredCount)~="function" then return end
    local owned = value(Saved,"OwnedPets",nil)
    local stage = tonumber(value(Saved,"IndexRewardStage",0)) or 0
    if owned==nil then return end
    local ok, count = pcall(IndexData.DiscoveredCount,owned)
    local ok2, nextStage = pcall(IndexData.StageAt,stage)
    if ok and ok2 and type(count)=="number" and type(nextStage)=="table" and tonumber(nextStage.Goal)
        and count>=nextStage.Goal and due("index:"..stage,10) then
        remote("ClaimIndexReward","Normal")
        status("Index reward claimed")
    end
end

local function clearVisual(map)
    for object, instances in pairs(map) do
        for _, visual in ipairs(instances) do pcall(function() visual:Destroy() end) end
        map[object] = nil
    end
end
local function highlight(map, obj, label, color)
    if map[obj] or not obj.Parent then return end
    local host = obj
    if obj:IsA("ProximityPrompt") then host = obj.Parent end
    if host:IsA("Attachment") then host = host.Parent end
    local h = Instance.new("Highlight")
    h.Name = "CAT_EMPIRE_ESP"
    h.Adornee = obj:IsA("PVInstance") and obj or host
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.FillColor = color
    h.OutlineColor = color
    h.FillTransparency = .82
    h.OutlineTransparency = .04
    h.Parent = host
    local anchor = host:IsA("BasePart") and host or host:FindFirstChildWhichIsA("BasePart",true)
    local visuals = {h}
    if anchor then
        local b = Instance.new("BillboardGui")
        b.Name = "CAT_EMPIRE_TAG"
        b.Adornee = anchor
        b.AlwaysOnTop = true
        b.MaxDistance = 0
        b.Size = UDim2.fromOffset(245,52)
        b.StudsOffsetWorldSpace = Vector3.new(0,3,0)
        local t = Instance.new("TextLabel")
        t.BackgroundTransparency = 1
        t.Size = UDim2.fromScale(1,1)
        t.Text = label
        t.TextColor3 = color
        t.TextStrokeTransparency = .2
        t.Font = Enum.Font.GothamBold
        t.TextScaled = true
        t.Parent = b
        b.Parent = host
        visuals[#visuals+1]=b
    end
    map[obj]=visuals
end
local function refreshESP()
    local marked = {}
    local function markEgg(obj,rarity,eggName)
        marked[obj]=true
        local colors={
            Common=Color3.fromRGB(210,215,225),
            Uncommon=Color3.fromRGB(140,220,140),
            Rare=Color3.fromRGB(75,175,255),
            Epic=Color3.fromRGB(175,95,255),
            Legendary=Color3.fromRGB(255,194,70),
            Mythic=Color3.fromRGB(255,90,180),
            Mythical=Color3.fromRGB(255,90,180),
            Divine=Color3.fromRGB(255,236,115),
            Secret=Color3.fromRGB(240,85,85),
            Ethereal=Color3.fromRGB(95,245,225),
        }
        local color=colors[rarity] or colors.Common
        local text=rarity
        if S.ShowEggName and eggName then text=text.." | "..eggName end
        if S.ShowEggDistance then
            local p=positionOf(obj)
            local root=getRoot()
            if p and root then text=text.." | "..math.floor((root.Position-p).Magnitude).." studs" end
        end
        highlight(EggVisuals,obj,text,color)
        local visual=EggVisuals[obj]
        if visual then
            local h=visual[1]
            if h and h.Parent then h.FillColor=color;h.OutlineColor=color end
            local billboard=visual[2]
            local label=billboard and billboard:FindFirstChildWhichIsA("TextLabel")
            if label then label.Text=text;label.TextColor3=color end
        end
    end
    if S.EggsESP then
        local positions={}
        local folder=workspace:FindFirstChild("RenderedEggs")
        if folder then
            for _,egg in ipairs(folder:GetDescendants()) do
                if (egg:IsA("Model") or egg:IsA("BasePart"))
                    and not egg.Parent:IsA("Model") then
                    local name=egg:GetAttribute("Egg") or egg.Name
                    if type(name)=="string" and
                        (EggData[name]~=nil or egg:GetAttribute("Egg")~=nil) then
                        local pos=positionOf(egg)
                        if pos then
                            positions[#positions+1]=pos
                            markEgg(egg,eggRarity(name),name)
                        end
                    end
                end
            end
        end
        -- RenderedEggs e um cache visual: ovos distantes podem estar fora dele.
        -- ActiveEggs contem registros com a posicao mesmo sem modelo renderizado.
        local serverData=RS:FindFirstChild("ServerData")
        local active=(serverData and serverData:FindFirstChild("ActiveEggs"))
            or RS:FindFirstChild("ActiveEggs")
        if active then
            local cycles=collectedCycles()
            for _,record in ipairs(active:GetChildren()) do
                local name=record:GetAttribute("Egg")
                local pos=record:GetAttribute("Position")
                local privateTo=record:GetAttribute("PrivateTo")
                local delayUntil=tonumber(record:GetAttribute("DropEndsAt")) or 0
                if type(name)=="string" and typeof(pos)=="Vector3"
                    and (privateTo==nil or privateTo==LP.UserId)
                    and delayUntil<=workspace:GetServerTimeNow()
                    and not claimed(name,record,cycles) then
                    local rendered=false
                    for _,rp in ipairs(positions) do
                        if (rp-pos).Magnitude<10 then rendered=true;break end
                    end
                    if not rendered then
                        local marker=EggWorldMarkers[record]
                        if not marker or not marker.Parent then
                            marker=Instance.new("Part")
                            marker.Name="CAT_EMPIRE_EGG_ESP_ANCHOR"
                            marker.Size=Vector3.new(.3,.3,.3)
                            marker.Transparency=1
                            marker.Anchored=true
                            marker.CanCollide=false
                            marker.CanTouch=false
                            marker.CanQuery=false
                            marker.Parent=workspace
                            EggWorldMarkers[record]=marker
                        end
                        marker.Position=pos+Vector3.new(0,1,0)
                        markEgg(marker,eggRarity(name),name)
                    end
                end
            end
        end
    end
    for object,visuals in pairs(EggVisuals) do
        if not marked[object] or not object.Parent then
            for _,v in ipairs(visuals) do pcall(function() v:Destroy() end) end
            EggVisuals[object]=nil
        end
    end
    for record,marker in pairs(EggWorldMarkers) do
        if not marked[marker] or not record.Parent then
            pcall(function() marker:Destroy() end)
            EggWorldMarkers[record]=nil
        end
    end

end
local cleanupSettings, cleanupVisual
local function cleanup()
    S.Running=false
    if type(cleanupSettings)=="function" then pcall(cleanupSettings) end
    if type(cleanupVisual)=="function" then pcall(cleanupVisual) end
    S.AutoCollectEggs=false
    EggCycle.Stage="idle"
    S.AutoCollectCandy=false
    CandyCycle.Stage="idle"
    S.AutoFeed=false
    S.AutoPlaceBest=false
    for _,c in ipairs(Links) do pcall(function() c:Disconnect() end) end
    clearVisual(EggVisuals)
    for record, marker in pairs(EggWorldMarkers) do
        pcall(function() marker:Destroy() end)
        EggWorldMarkers[record]=nil
    end
    if Window and Window.Destroy then pcall(function() Window:Destroy() end)
    elseif Fluent.Destroy then pcall(function() Fluent:Destroy() end) end
    Env.__CE_SETTING_PET_CLEANUP=nil
end
Env.__CE_SETTING_PET_CLEANUP=cleanup

Window = Fluent:CreateWindow({
    Title="CAT EMPIRE", SubTitle="Setting up a Pet",
    TabWidth=158, Size=UDim2.fromOffset(765,480),
    Acrylic=false, Animated=false, Theme="Dark",
    MinimizeKey=Enum.KeyCode.RightControl,
    ScreenGuiName="CAT_EMPIRE_SETTING_UP_A_PET_124216119978534",
})
local Tabs={
    Eggs=Window:AddTab({Title="Eggs",Icon="solar/star-bold"}),
    Pets=Window:AddTab({Title="Pets",Icon="solar/paw-bold"}),
    Shop=Window:AddTab({Title="Shop",Icon="solar/bag-bold"}),
    Halloween=Window:AddTab({Title="Halloween",Icon="solar/moon-bold"}),
    Intel=Window:AddTab({Title="Intel",Icon="solar/chart-bold"}),
    Settings=Window:AddTab({Title="Settings",Icon="solar/settings-bold"}),
    Misc=Window:AddTab({Title="Misc",Icon="solar/user-bold"}),
}
local function addToggle(tab,label,key,cb)
    Toggles[key]=tab:AddToggle("SUP_"..key,{
        Title=label,Default=false,Callback=function(enabled)
            S[key]=enabled==true
            if cb then task.spawn(cb) end
        end,
    })
end
local function button(tab,label,callback)
    tab:AddButton({Title=label,Callback=function()
        task.spawn(function()
            local ok,err=pcall(callback)
            if not ok then S.LastError=tostring(err);notify(err) end
        end)
    end})
end
Status=Tabs.Eggs:AddParagraph({Title="Setting up a Pet",Content="Initialized"})
addToggle(Tabs.Eggs,"Auto Collect Eggs","AutoCollectEggs")
Tabs.Eggs:AddDropdown("SUP_PriorityEggs",{
    Title="Priority Eggs",Values={"Rarest","Nearest","Heaviest"},Default="Rarest",
    Callback=function(v) S.EggPriority=v end,
})
Tabs.Eggs:AddDropdown("SUP_MinRarity",{
    Title="Minimum Egg Rarity",Values={"Common","Rare","Epic","Legendary","Mythic","Divine","Secret","Ethereal"},
    Default="Common",Callback=function(v) S.EggMinRarity=v end,
})
addToggle(Tabs.Intel,"Eggs ESP","EggsESP")
addToggle(Tabs.Eggs,"Auto Hatch","AutoHatch")
addToggle(Tabs.Eggs,"Auto Luck Upgrade","AutoLuckUpgrade")

addToggle(Tabs.Pets,"Auto Feed","AutoFeed")
local choices={"Any Available"}
for name in pairs(FoodData) do if type(name)=="string" then choices[#choices+1]=name end end
table.sort(choices)
Tabs.Pets:AddDropdown("SUP_FoodChoice",{
    Title="Feed Food",Values=choices,Default="Any Available",
    Callback=function(v) S.FoodChoice=v end,
})
addToggle(Tabs.Pets,"Auto Place Best","AutoPlaceBest")
button(Tabs.Pets,"Place Best Once",placeBest)
addToggle(Tabs.Pets,"Auto Rebirth","AutoRebirth")

local items,foods=shopLists()
ShopItemDropdown=Tabs.Shop:AddDropdown("SUP_SelectedItems",{
    Title="Auto Buy Items",Values=items,Multi=true,Default={},
    DropdownOutsideWindow=true,Callback=function(v)
        local old=S.SelectedItems
        local updated=normalizeChoice(v)
        S.SelectedItems=updated
        if S.AutoBuyItems then
            task.spawn(function()
                for id in pairs(old) do
                    if not updated[id] then applyNativeAutobuy("items",{[id]=true},false) end
                end
                refreshNativeAutobuy("items")
            end)
        end
    end,
})
addToggle(Tabs.Shop,"Auto Buy Items","AutoBuyItems",function()
    refreshNativeAutobuy("items")
end)
FoodDropdown=Tabs.Shop:AddDropdown("SUP_SelectedFoods",{
    Title="Auto Buy Food",Values=foods,Multi=true,Default={},
    DropdownOutsideWindow=true,Callback=function(v)
        local old=S.SelectedFoods
        local updated=normalizeChoice(v)
        S.SelectedFoods=updated
        if S.AutoBuyFood then
            task.spawn(function()
                for id in pairs(old) do
                    if not updated[id] then applyNativeAutobuy("food",{[id]=true},false) end
                end
                refreshNativeAutobuy("food")
            end)
        end
    end,
})
addToggle(Tabs.Shop,"Auto Buy Food","AutoBuyFood",function()
    refreshNativeAutobuy("food")
end)

addToggle(Tabs.Halloween,"Auto Buy Halloween Eggs","AutoBuyHalloweenEggs")

addToggle(Tabs.Eggs,"Auto Claim Index","AutoClaimIndex")
local configKeys={
    "AutoCollectEggs","EggsESP","AutoHatch","AutoLuckUpgrade","AutoFeed",
    "AutoPlaceBest","AutoRebirth","AutoBuyHalloweenEggs",
    "AutoClaimIndex","AutoBuyItems","AutoBuyFood",
}
local ProfileNames={"Default"}
local SelectedProfile="Default"
local ProfileNameInput=""
local ProfileMeta=S.ConfigFile
local ProfileDatabase={}
if type(readfile)=="function" then
    local ok,data=pcall(function()
        return HttpService:JSONDecode(readfile(ProfileMeta))
    end)
    if ok and type(data)=="table" then
        if type(data.Names)=="table" then ProfileNames=data.Names end
        if type(data.Profiles)=="table" then ProfileDatabase=data.Profiles end
        SelectedProfile=tostring(data.Selected or "Default")
        S.AutoLoadProfiles=data.AutoLoad==true
    end
end
local ProfilesMenu=Tabs.Settings:AddDropdown("SUP_Profiles",{
    Title="Profiles",Values=ProfileNames,Default=SelectedProfile,
    Callback=function(v)
        SelectedProfile=tostring(v or "Default")
    end,
})
Tabs.Settings:AddInput("SUP_ProfileName",{
    Title="New Profile Name",Default="",Placeholder="New profile name",
    Callback=function(v)
        ProfileNameInput=tostring(v or ""):gsub("[^%w_%-]","_"):sub(1,32)
    end,
})
local saveProfile
button(Tabs.Settings,"Create Profiles",function()
    if ProfileNameInput=="" then return end
    for _,v in ipairs(ProfileNames) do
        if v==ProfileNameInput then ProfilesMenu:SetValue(v);return end
    end
    ProfileNames[#ProfileNames+1]=ProfileNameInput
    SelectedProfile=ProfileNameInput
    ProfilesMenu:SetValues(ProfileNames)
    ProfilesMenu:SetValue(ProfileNameInput)
    if saveProfile then saveProfile() end
end)
Toggles.AutoLoadProfiles=Tabs.Settings:AddToggle("SUP_AutoLoadProfiles",{
    Title="Auto Load Profiles",Default=S.AutoLoadProfiles==true,
    Callback=function(v)
        S.AutoLoadProfiles=v==true
        if saveProfile then saveProfile() end
    end,
})
saveProfile=function()
    if type(writefile)~="function" then notify("Executor has no writefile");return end
    local payload={EggPriority=S.EggPriority,EggMinRarity=S.EggMinRarity,
        FoodChoice=S.FoodChoice,SelectedItems=S.SelectedItems,SelectedFoods=S.SelectedFoods,
        EggFilterMode=S.EggFilterMode,SelectedEggs=S.SelectedEggs,
        EggFlightSpeed=S.EggFlightSpeed,EggHoldSeconds=S.EggHoldSeconds,
        WalkSpeed=S.WalkSpeed,JumpPower=S.JumpPower,FlySpeed=S.FlySpeed,MaxFPS=S.MaxFPS}
    for _,key in ipairs(configKeys) do payload[key]=S[key] end
    for _,key in ipairs({"AutoRejoin","AntiAFK","AutoCloseUI","AutoLoadAfterRejoin","BoostFPS"}) do payload[key]=S[key] end
    ProfileDatabase[SelectedProfile]=payload
    local catalog={Names=ProfileNames,Selected=SelectedProfile,AutoLoad=S.AutoLoadProfiles,
        Profiles=ProfileDatabase}
    local ok,err=pcall(writefile,S.ConfigFile,HttpService:JSONEncode(catalog))
    notify(ok and "Profile saved" or tostring(err))
end
button(Tabs.Settings,"Save Profiles",saveProfile)
local function loadProfile()
    if type(readfile)~="function" then notify("Executor has no readfile");return end
    local ok,data=pcall(function() return HttpService:JSONDecode(readfile(S.ConfigFile)) end)
    if not ok or type(data)~="table" then notify("No valid profile");return end
    if type(data.Profiles)=="table" then
        data=data.Profiles[SelectedProfile]
        if type(data)~="table" then notify("Profile does not exist");return end
    end
    if type(data.EggPriority)=="string" then S.EggPriority=data.EggPriority end
    if type(data.EggMinRarity)=="string" then S.EggMinRarity=data.EggMinRarity end
    if type(data.FoodChoice)=="string" then S.FoodChoice=data.FoodChoice end
    if type(data.EggFilterMode)=="string" then S.EggFilterMode=data.EggFilterMode end
    if type(data.SelectedEggs)=="table" then S.SelectedEggs=data.SelectedEggs end
    for _,key in ipairs({"EggFlightSpeed","EggHoldSeconds","WalkSpeed","JumpPower","FlySpeed","MaxFPS"}) do
        if type(data[key])=="number" then S[key]=data[key] end
    end
    if type(data.SelectedItems)=="table" then
        S.SelectedItems=data.SelectedItems
        pcall(function() ShopItemDropdown:SetValue(data.SelectedItems) end)
    end
    if type(data.SelectedFoods)=="table" then
        S.SelectedFoods=data.SelectedFoods
        pcall(function() FoodDropdown:SetValue(data.SelectedFoods) end)
    end
    for _,key in ipairs(configKeys) do
        if type(data[key])=="boolean" and Toggles[key] then
            pcall(function() Toggles[key]:SetValue(data[key]) end)
        end
    end
    for _,key in ipairs({"AutoRejoin","AntiAFK","AutoCloseUI","AutoLoadAfterRejoin","BoostFPS"}) do
        if type(data[key])=="boolean" and Toggles[key] then
            pcall(function() Toggles[key]:SetValue(data[key]) end)
        end
    end
    notify("Profile loaded")
end
button(Tabs.Settings,"Load Selected Profile",loadProfile)
local function notifySettings(message)
    notify(message)
end
local okSettings, settingsBuilder = pcall(function()
    return assert(loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/SettingUpAPet/Settings.lua", true
    )))()
end)
if okSettings and type(settingsBuilder)=="function" then
    local ok, cleanupFn=pcall(settingsBuilder,{
        S=S,Window=Window,Tabs=Tabs,Links=Links,Toggles=Toggles,
        LP=LP,Fluent=Fluent,cleanup=cleanup,
    })
    if ok and type(cleanupFn)=="function" then cleanupSettings=cleanupFn
    else S.LastError="Settings initialization: "..tostring(cleanupFn) end
else
    S.LastError="Settings module unavailable: "..tostring(settingsBuilder)
end

task.delay(3,function()
    if S.Running and S.AutoLoadProfiles then loadProfile() end
end)
local LuminExpansion, EggTransport
do
    local ok, builder=pcall(function()
        local body=game:HttpGet("https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/SettingUpAPet/Expansion.lua",true)
        return assert(loadstring(body))()
    end)
    if ok and type(builder)=="function" then
        local good,result=pcall(builder,{
            State=S,Player=LP,Tabs=Tabs,Links=Links,Game=Game,Toggles=Toggles,
            PetData=PetData,EggData=EggData,Notify=notify,ConfigKeys=configKeys,
            GetRoot=getRoot,GetPlot=getPlot,PetList=ownedPets,ClaimIndex=claimIndex,
            FilterableEggs=eggCandidates,
            EggWantsPriority=function()
                return EggTransport and EggTransport.WantsPriority() or false
            end,
        })
        if good then LuminExpansion=result
        else S.LastError="Expansion initialization: "..tostring(result) end
    else
        S.LastError="Expansion load failed: "..tostring(builder)
    end
end
do
    local ok,builder=pcall(function()
        local body=game:HttpGet("https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/SettingUpAPet/VisualSystem.lua",true)
        return assert(loadstring(body))()
    end)
    if ok and type(builder)=="function" then
        local good,result=pcall(builder,{
            State=S,Player=LP,Tabs=Tabs,Links=Links,ConfigKeys=configKeys,Toggles=Toggles,
            GetRoot=getRoot,Notify=notify,
        })
        if good then cleanupVisual=result
        else S.LastError="VisualSystem initialization: "..tostring(result) end
    else
        S.LastError="VisualSystem load failed: "..tostring(builder)
    end
end
do
    local ok, moduleOrError=pcall(function()
        local body=game:HttpGet("https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/SettingUpAPet/EggTransport.lua",true)
        local chunk,err=loadstring(body)
        assert(chunk,err)
        return chunk()
    end)
    if ok and type(moduleOrError)=="function" then
        local good,result=pcall(moduleOrError,{
            State=S,Player=LP,Links=Links,Game=Game,
            EggCandidates=function()
                local all=eggCandidates()
                return LuminExpansion and LuminExpansion.FilterEggs(all) or all
            end,GetPlot=getPlot,Status=status,
            IsMounted=LuminExpansion and LuminExpansion.IsMounted,
            EnsureMount=LuminExpansion and LuminExpansion.EnsureMount,
        })
        if good then EggTransport=result
        else S.LastError="EggTransport initialization: "..tostring(result) end
    else
        S.LastError="EggTransport load: "..tostring(moduleOrError)
    end
end
local function worker(key,delay,fn)
    task.spawn(function()
        while S.Running do
            if S[key] then
                local ok,err=pcall(fn)
                if not ok then S.LastError=key..": "..tostring(err) end
            end
            task.wait(delay)
        end
    end)
end
task.spawn(function()
    while S.Running do
        local ok,err=pcall(function()
            S.Movement=false
            if EggTransport then
                S.Movement=EggTransport.WantsPriority()
            elseif S.AutoCollectEggs or EggCycle.Stage~="idle" then
                S.Movement=collectEggs()
            end
            if not S.Movement and S.AutoFarmHalloweenEvent then
                S.Movement=enterHalloween()
                if not S.Movement and LP:GetAttribute("InHalloweenZone")==true then
                    S.Movement=collectCandy()
                end
            end
        end)
        if not ok then S.LastError="movement: "..tostring(err) end
        task.wait(.8)
    end
end)
worker("AutoHatch",3,hatchReady)
worker("AutoLuckUpgrade",14,luckUpgrade)
worker("AutoFeed",3,feedPets)
worker("AutoPlaceBest",30,placeBest)
worker("AutoRebirth",10,rebirth)
worker("AutoBuyHalloweenEggs",3,buyHalloween)
worker("AutoClaimIndex",5,claimIndex)
task.spawn(function()
    while S.Running do
        pcall(refreshESP)
        if Status then
            pcall(function()
                Status:SetTitle("Setting up a Pet")
                Status:SetDesc(S.LastAction .. (S.LastError ~= "" and (" | " .. S.LastError) or ""))
            end)
        end
        task.wait(2)
    end
end)
notify("Setting up a Pet loaded | 16 features ready for validation")
