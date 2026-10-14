if game.PlaceId ~= 114326934417838 and game.GameId ~= 114326934417838 then return end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer
local Env = (getgenv and getgenv()) or _G
if type(Env.__CE_BREAK_EGG_CLEANUP) == "function" then pcall(Env.__CE_BREAK_EGG_CLEANUP) end
local source = Env.__CE_F_91A7
assert(type(source) == "string" and #source > 0, "CAT EMPIRE: execute Loader/Loader.lua")
local Fluent = assert(loadstring(source))()
local Shared = RS:FindFirstChild("Shared") or RS:WaitForChild("Shared", 12)
assert(Shared, "Shared modules unavailable")
local playerScripts = LP:FindFirstChild("PlayerScripts") or LP:WaitForChild("PlayerScripts", 12)
local client = playerScripts and (playerScripts:FindFirstChild("Client") or playerScripts:WaitForChild("Client", 12))
local Controllers = client and (client:FindFirstChild("Controllers") or client:WaitForChild("Controllers", 12))
local function loadModule(parent, name)
    local inst = parent and parent:FindFirstChild(name)
    if not inst or not inst:IsA("ModuleScript") then return nil end
    local ok, obj = pcall(require, inst)
    return ok and obj or nil
end
local configs, controllers = {}, {}
for _, name in ipairs({
    "EggTargeting","EggConfig","EggRewards","EggTypeConfig","PickaxeConfig",
    "PlotUpgradeConfig","TreadmillUpgradeConfig","TrailsConfig","ZonesConfig","ZoneHitboxLookup","HellEventConfig",
    "HellEssenceConfig","HellBossConfig","BatConfig","SpeedConfig"
}) do configs[name] = loadModule(Shared, name) end
for _, name in ipairs({
    "PickaxeController","BatController","AutoSwingController","OwnBase",
    "AnimalToolController","PetsInventoryController","HellBossController"
}) do controllers[name] = loadModule(Controllers, name) end
local S = {
    Running = true, AutoFarmEggs = false, AutoUpgradeTreadmill = false,
    AutoUpgradePlot = false, AutoPlaceBest = false, AutoTrainTreadmill = false,
    AutoBuyTrails = false, AutoBuyPickaxe = false, AutoHellEvent = false,
    SelectedRarities = {}, SelectedTrails = {}, SelectedPickaxes = {},
    TravelMode = "Fast", EggPriority = "Rarest", LastAction = "Ready",
    LastError = "", Step = "Idle", HellStep = "Idle", AutoRejoin = false,
    AntiAFK = false, AutoCloseUI = false, AutoLoadAfterRejoin = false,
    BoostFPS = false, AutoLoadProfiles = false, Moving = nil,
    ConfigFile = "CAT_EMPIRE_BREAK_EGG_114326934417838.json",
}
local Links, Toggles = {}, {}
local Window, Status, HellStatus
local lastRequests = {}
local function notify(message)
    pcall(function() Fluent:Notify({Title="CAT EMPIRE",Content=tostring(message),Duration=4}) end)
end
local function status(message)
    S.LastAction = tostring(message)
end
local function errorState(where, err)
    S.LastError = tostring(where)..": "..tostring(err)
    warn("[CAT EMPIRE Break Egg] "..S.LastError)
end
local function remote(name, ...)
    local obj = RS:FindFirstChild(name)
    if not obj then return false, "Remote missing: "..name end
    local args = table.pack(...)
    local ok, result = pcall(function()
        if obj:IsA("RemoteEvent") then
            obj:FireServer(table.unpack(args, 1, args.n))
            return true
        end
        if obj:IsA("RemoteFunction") then
            return obj:InvokeServer(table.unpack(args, 1, args.n))
        end
        error("Unsupported remote type")
    end)
    if not ok then errorState(name,result) end
    return ok, result
end
local function throttle(key, seconds)
    local now = os.clock()
    if (lastRequests[key] or 0) > now then return false end
    lastRequests[key] = now + seconds
    return true
end
local function root()
    local character = LP.Character
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    local part = character and character:FindFirstChild("HumanoidRootPart")
    if hum and part and hum.Health > 0 then return part, hum end
    return nil, nil
end
local function position(inst)
    if not inst or not inst.Parent then return nil end
    if inst:IsA("Attachment") then return inst.WorldPosition end
    if inst:IsA("BasePart") then return inst.Position end
    if inst:IsA("Model") then return inst:GetPivot().Position end
    if inst:IsA("ProximityPrompt") then return position(inst.Parent) end
    return nil
end
local function ownPlot()
    local ctrl = controllers.OwnBase
    if ctrl and type(ctrl.Get) == "function" then
        local ok, plot = pcall(ctrl.Get)
        if ok and typeof(plot) == "Instance" and plot.Parent then return plot end
    end
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:GetAttribute("OwnerUserId") == LP.UserId then return plot end
    end
end
local function inHell()
    local cfg = configs.HellEventConfig or {}
    return LP:GetAttribute(cfg.PlayerAttribute or "InHell") == true
end
local function priorityOwner()
    local hellConfig = configs.HellEventConfig or {}
    if S.AutoHellEvent and (inHell() or workspace:GetAttribute(hellConfig.JoinableAttribute or "HellJoinable") == true) then
        return "Hell"
    end
    if S.AutoFarmEggs then return "Farm" end
    if S.AutoTrainTreadmill then return "Train" end
    return nil
end
local function canMove(owner)
    return priorityOwner() == owner and (S.Moving == nil or S.Moving == owner)
end
local function move(owner, destination, offset, forceFast)
    local part, hum = root()
    if not part or typeof(destination) ~= "Vector3" or not canMove(owner) then return false end
    if LP:GetAttribute("Jailed") == true then return false end
    local goal = destination + Vector3.new(0,offset or 3,0)
    if (goal - part.Position).Magnitude < 3.5 then return true end
    S.Moving = owner
    local ok = pcall(function()
        if forceFast or S.TravelMode == "Fast" then
            part.CFrame = CFrame.new(goal)
        else
            hum:MoveTo(goal)
        end
    end)
    S.Moving = nil
    return ok and (part.Position - goal).Magnitude < 10
end
local function equip(name)
    local character = LP.Character
    local backpack = LP:FindFirstChildOfClass("Backpack")
    local part, hum = root()
    if not part then return nil end
    local tool = character and character:FindFirstChild(name)
    if tool and tool:IsA("Tool") then return tool end
    tool = backpack and backpack:FindFirstChild(name)
    if tool and tool:IsA("Tool") then
        pcall(function() hum:EquipTool(tool) end)
        return tool
    end
    return nil
end
local function selected(result)
    local out = {}
    if type(result) == "table" then
        for k,v in pairs(result) do
            if type(k) == "string" and v == true then out[k] = true
            elseif type(v) == "string" then out[v] = true end
        end
    end
    return out
end
local function worker(key, delay, action)
    task.spawn(function()
        while S.Running do
            if S[key] then
                local ok, err = pcall(action)
                if not ok then errorState(key,err) end
            end
            task.wait(delay)
        end
    end)
end
local function loadFeature(name)
    local versions = {
        Farm = "7fb4d321de54b54f0a78b91b0919a519f23a31b4",
        Progress = "d1bcee52c907d7fa27a4e15e77b1904fb808e3fb",
        Hell = "c441b8e19b082fb7fd38c0131a73d21ea96e08ec",
        Settings = "88256a0873c6e7d1a7e20a51ee2ffaf2c4fbe867",
    }
    local revision = versions[name] or "main"
    local url = "https://raw.githubusercontent.com/DanoninCat/DanoninScript/"..revision.."/BreakAndStealAnEgg/"..name..".lua"
    local ok, fn = pcall(function()
        local text = game:HttpGet(url, true)
        return assert(loadstring(text))()
    end)
    if not ok or type(fn) ~= "function" then errorState(name,fn); return nil end
    return fn
end
local featureCleanups = {}
local function cleanup()
    if not S.Running then return end
    S.Running = false
    for _, fn in ipairs(featureCleanups) do pcall(fn) end
    for _, connection in ipairs(Links) do pcall(function() connection:Disconnect() end) end
    if Window then pcall(function() Window:Destroy() end) end
    Env.__CE_BREAK_EGG_CLEANUP = nil
end
Env.__CE_BREAK_EGG_CLEANUP = cleanup

Window = Fluent:CreateWindow({
    Title = "CAT EMPIRE", SubTitle = "Break and Steal an Egg",
    TabWidth = 158, Size = UDim2.fromOffset(765,480),
    Acrylic = false, Animated = false, Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
    ScreenGuiName = "CAT_EMPIRE_BREAK_EGG_114326934417838",
})
local Tabs = {
    Farm=Window:AddTab({Title="Egg Farm",Icon="solar/star-bold"}),
    Pets=Window:AddTab({Title="Pets",Icon="solar/paw-bold"}),
    Progress=Window:AddTab({Title="Progress",Icon="solar/chart-bold"}),
    Shop=Window:AddTab({Title="Shop",Icon="solar/bag-bold"}),
    Hell=Window:AddTab({Title="Hell Event",Icon="solar/fire-bold"}),
    Settings=Window:AddTab({Title="Settings",Icon="solar/settings-bold"}),
    Misc=Window:AddTab({Title="Misc",Icon="solar/user-bold"}),
}
local function toggle(tab,key,title)
    Toggles[key]=tab:AddToggle("BREAK_"..key,{
        Title=title,Default=false,
        Callback=function(value) S[key] = value == true end,
    })
end
Status = Tabs.Farm:AddParagraph({Title="Break and Steal an Egg",Content="Initializing"})
HellStatus = Tabs.Hell:AddParagraph({Title="Hell Event",Content="Waiting"})
toggle(Tabs.Farm,"AutoFarmEggs","Auto Farm Eggs")
local rarities={"Common","Uncommon","Rare","Epic","Legendary","Mythic","Divine","Cosmic","Secret","Celestial","Inferno","Void","Omega","Unknown"}
Tabs.Farm:AddDropdown("BREAK_EggRarities",{
    Title="Egg Rarities",Values=rarities,Multi=true,Default={},
    DropdownOutsideWindow=true,
    Callback=function(value) S.SelectedRarities=selected(value) end,
})
Tabs.Farm:AddDropdown("BREAK_EggPriority",{
    Title="Target Priority",Values={"Rarest","Nearest"},Default="Rarest",
    Callback=function(value) S.EggPriority=value end,
})
Tabs.Farm:AddDropdown("BREAK_TravelMode",{
    Title="Travel Mode",Values={"Fast","Walk"},Default="Fast",
    Callback=function(value) S.TravelMode=value end,
})
toggle(Tabs.Pets,"AutoPlaceBest","Auto Place Best Pet")
toggle(Tabs.Progress,"AutoUpgradeTreadmill","Auto Upgrade Treadmill")
toggle(Tabs.Progress,"AutoUpgradePlot","Auto Upgrade Plot (Pen)")
toggle(Tabs.Progress,"AutoTrainTreadmill","Auto Train Treadmill")
toggle(Tabs.Shop,"AutoBuyTrails","Auto Buy Trails")
toggle(Tabs.Shop,"AutoBuyPickaxe","Auto Buy Pickaxe")
toggle(Tabs.Hell,"AutoHellEvent","Auto Hell Event")
local ctx = {
    S=S, Player=LP, RS=RS, CS=CS, Shared=Shared,
    Config=configs, Controllers=controllers, Tabs=Tabs, Toggles=Toggles,
    Window=Window, Fluent=Fluent, Links=Links, HttpService=HttpService,
    Root=root, Position=position, PriorityOwner=priorityOwner,
    Plot=ownPlot, Move=move, CanMove=canMove, InHell=inHell, Remote=remote,
    Throttle=throttle, Equip=equip, Status=status, Notify=notify,
    Error=errorState, Worker=worker, Cleanup=cleanup, Selected=selected,
}
for _, name in ipairs({"Farm","Progress","Hell","Settings"}) do
    local init = loadFeature(name)
    if init then
        local ok, result = pcall(init, ctx)
        if not ok then errorState(name,result)
        elseif type(result)=="function" then featureCleanups[#featureCleanups+1]=result end
    end
end
task.spawn(function()
    while S.Running do
        pcall(function()
            Status:SetTitle("Break and Steal an Egg")
            Status:SetDesc(S.Step.." | "..S.LastAction..(S.LastError ~= "" and (" | "..S.LastError) or ""))
            local cfg = configs.HellEssenceConfig or {}
            local goal = workspace:GetAttribute(cfg.GoalAttribute or "HellEssenceGoal") or cfg.GoalBase or 1000
            local amount = workspace:GetAttribute(cfg.EssenceAttribute or "HellEssence") or 0
            HellStatus:SetDesc(S.HellStep.." | Essence: "..tostring(amount).."/"..tostring(goal))
        end)
        task.wait(1.2)
    end
end)
notify("CAT EMPIRE loaded: validate each function in-game")
