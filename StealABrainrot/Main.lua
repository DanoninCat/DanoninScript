-- CAT EMPIRE — Steal A Brainrot (place 99881468171809)
-- Built from decompiled client dump; every remote call below is copied from
-- the game's own LocalScripts/Modules (evidence analysis/remote_calls.json).
if game.PlaceId ~= 99881468171809 then
    return
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer
local Env = (getgenv and getgenv()) or _G
if type(Env.__CE_STEAL_BRAINROT_CLEANUP) == "function" then pcall(Env.__CE_STEAL_BRAINROT_CLEANUP) end

local source = Env.__CE_F_91A7
assert(type(source) == "string" and #source > 0, "CAT EMPIRE: execute Loader/Loader.lua")
local Fluent = assert(loadstring(source))()

-- ---------------------------------------------------------------- helpers
local Links, Toggles = {}, {}
local lastRequests = {}
local S
local Status

local function notify(message)
    pcall(function() Fluent:Notify({Title = "CAT EMPIRE", Content = tostring(message), Duration = 4}) end)
end
local function status(message)
    if S then S.LastAction = tostring(message) end
end
local function errorState(where, err)
    if S then S.LastError = tostring(where) .. ": " .. tostring(err) end
    warn("[CAT EMPIRE StealBrainrot] " .. tostring(where) .. ": " .. tostring(err))
end
local function throttle(key, seconds)
    local now = os.clock()
    if (lastRequests[key] or 0) > now then return false end
    lastRequests[key] = now + seconds
    return true
end
local function selected(result)
    local out = {}
    if type(result) == "table" then
        for k, v in pairs(result) do
            if type(k) == "string" and v == true then out[k] = true
            elseif type(v) == "string" then out[v] = true end
        end
    end
    return out
end
local function hrp()
    local character = LP.Character
    return character and character:FindFirstChild("HumanoidRootPart"), character and character:FindFirstChildOfClass("Humanoid")
end

-- shared game modules (replicated, safe to require server-agnostic)
local function requireModule(name)
    local inst = RS:FindFirstChild("Modules")
    inst = inst and inst:FindFirstChild(name)
    if inst and inst:IsA("ModuleScript") then
        local ok, obj = pcall(require, inst)
        if ok then return obj end
        errorState("requireModule " .. name, obj)
    end
    return nil
end
local BrainrotData = requireModule("BrainrotData")
local SellConfig = requireModule("SellConfig")
local CodesConfig = requireModule("CodesConfig")
local HalloweenConfig = requireModule("HalloweenConfig")
local WheelConfig = requireModule("WheelConfig")
local PlaytimeRewardsConfig = requireModule("PlaytimeRewardsConfig")
local VolcanoConfig = requireModule("VolcanoConfig")
local BossCaseConfig = requireModule("BossCaseConfig")
local InventoryConfig = requireModule("InventoryConfig")
local HalloweenState = RS:FindFirstChild("Modules") and requireModule("HalloweenState") or nil

-- remote access
local Remotes = RS:WaitForChild("Remotes", 30)
local function R(group, name)
    if typeof(Remotes) ~= "Instance" then return nil end
    local g = Remotes:FindFirstChild(group)
    if not g then
        g = Remotes:WaitForChild(group, 20)
        if not g then errorState("Remotes", "missing group " .. group) return nil end
    end
    local r = g:FindFirstChild(name)
    if not r then r = g:WaitForChild(name, 20) end
    return r
end

local function fire(group, name, ...)
    local r = R(group, name)
    if r and r:IsA("RemoteEvent") then
        local args = table.pack(...)
        local ok, err = pcall(function() r:FireServer(table.unpack(args, 1, args.n)) end)
        if not ok then errorState(group .. "." .. name, err) return false end
        return true
    end
    return false
end
local function invoke(group, name, ...)
    local r = R(group, name)
    if r and r:IsA("RemoteFunction") then
        local args = table.pack(...)
        local ok, res = pcall(function() return r:InvokeServer(table.unpack(args, 1, args.n)) end)
        if not ok then errorState(group .. "." .. name, res) return nil end
        return res
    end
    return nil
end

local function worker(key, delay, action)
    task.spawn(function()
        while S.Running do
            local ok, err = pcall(function()
                if S[key] then action() end
            end)
            if not ok then errorState(key, err) end
            task.wait(delay)
        end
    end)
end

-- ---------------------------------------------------------------- state
S = {
    Running = true,
    AutoCollectCash = false, CollectInterval = 0.35,
    AutoSell = false, SelectedSellRarities = {}, SellAllInventoryToggle = false,
    AutoPlaceBest = false, PlaceBestInterval = 10,
    AutoUpgrade = false,
    AutoDaily = false, AutoPlaytime = false, AutoOfflineCash = false,
    AutoFreeReward = false, AutoFreeBrainrot = false, AutoRedeemCodes = false,
    AutoWheel = false, WheelFast = false, WheelDelay = 1.2,
    AutoTrickOrTreat = false, AutoCandy = false, CandyRadius = 9,
    AutoHalloweenRebirth = false,
    AutoLuckyOni = false, AutoLuckyBlock = false, LuckyBlockBundle = 1,
    AutoDeclineTrades = false,
    HalloweenTravelTarget = "island",
    LastAction = "Ready", LastError = "",
    -- supplied by the shared settings module
    AutoRejoin = false, AntiAFK = false, AutoCloseUI = false,
    AutoLoadAfterRejoin = false, BoostFPS = false, AutoLoadProfiles = false,
    ConfigFile = "CAT_EMPIRE_STEAL_BRAINROT_99881468171809.json",
}

--------------------------------------------------------------- FARM — auto collect cash
local function activeBases()
    return workspace:FindFirstChild("ActiveBases")
end
local function mySlots()
    local bases = activeBases()
    if not bases then return {} end
    local out = {}
    local mine = bases:FindFirstChild(tostring(LP.UserId)) or bases
    for _, model in ipairs(mine:GetDescendants()) do
        if model:IsA("Model")
            and model:GetAttribute("SlotKey")
            and model:GetAttribute("OwnerUserId") == LP.UserId
        then
            local button = model:FindFirstChild("CashButton", true)
            if button and button:IsA("BasePart") then
                out[#out + 1] = model:GetAttribute("SlotKey")
            end
        end
    end
    return out
end
local function collectCashOnce()
    for _, key in ipairs(mySlots()) do
        fire("Bases", "CollectCash", key)
        task.wait(0.05)
    end
end
task.spawn(function()
    while S.Running do
        task.wait(math.max(0.15, S.CollectInterval or 0.35))
        if S.AutoCollectCash then pcall(collectCashOnce) end
    end
end)

--------------------------------------------------------------- FARM — auto sell
local RarityOrder = {"Common", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Godly", "Divine", "OG",
    "Celestial", "Ancient", "Trascendent", "Eternal", "Omega", "Abyssal", "Astral",
    "Exclusive", "Event", "Volcano", "Halloween"}

local function collectBrainrotTools()
    local out = {}
    local containers = {LP:FindFirstChildOfClass("Backpack"), LP.Character}
    for _, container in ipairs(containers) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and tool:GetAttribute("IsBrainrot") == true and type(tool:GetAttribute("Uid")) == "string" then
                    out[#out + 1] = tool
                end
            end
        end
    end
    return out
end
local function toolRarity(tool)
    local id = tool:GetAttribute("BrainrotId")
    local data = id and BrainrotData and BrainrotData.Get and BrainrotData.Get(id) or nil
    return data and data.Rarity or tostring(tool:GetAttribute("Rarity") or "Common")
end
local function sellTool(tool)
    if throttle("sell", 0.4) then
        fire("Sell", "SellBrainrot", tool:GetAttribute("Uid"))
    end
end
local function selectedRarityKey()
    local set = selected(S.SelectedSellRarities)
    if next(set) == nil then return nil end
    return set
end
local function inventoryCount()
    if InventoryConfig and InventoryConfig.Count then
        local ok, n = pcall(InventoryConfig.Count, LP)
        if ok and type(n) == "number" then return n end
    end
    return #collectBrainrotTools()
end
local function sellOnce()
    local allow = selectedRarityKey()
    if not allow then return end
    for _, tool in ipairs(collectBrainrotTools()) do
        if S.Running and allow[toolRarity(tool)] then
            sellTool(tool)
            task.wait(0.45)
        end
    end
end
worker("AutoSell", 2, sellOnce)

--------------------------------------------------------------- FARM — auto place best / upgrade
worker("AutoPlaceBest", 3, function()
    if throttle("placebest", math.max(2, S.PlaceBestInterval or 10)) then
        fire("Bases", "PlaceBest")
    end
end)
local function placedSlots()
    local bases = activeBases()
    if not bases then return {} end
    local out = {}
    for _, model in ipairs(bases:GetDescendants()) do
        if model:IsA("Model")
            and model:GetAttribute("SlotKey")
            and model:GetAttribute("OwnerUserId") == LP.UserId
        then
            out[#out + 1] = model:GetAttribute("SlotKey")
        end
    end
    return out
end
worker("AutoUpgrade", 2.5, function()
    for _, key in ipairs(placedSlots()) do
        fire("Bases", "UpgradeBrainrot", key)
        task.wait(0.35)
    end
end)

-- Inventory full auto sell (uses game soft cap 400 via InventoryConfig)
task.spawn(function()
    while S.Running do
        if S.AutoSell and S.SellAllInventoryToggle then
            pcall(function()
                local count = inventoryCount()
                local cap = (InventoryConfig and InventoryConfig.SoftCap) or 400
                if count >= cap * 0.95 then
                    fire("Sell", "SellAll")
                end
            end)
        end
        task.wait(5)
    end
end)

--------------------------------------------------------------- REWARDS — daily / playtime / offline / free
worker("AutoDaily", 30, function()
    local state = invoke("Daily", "GetDailyState")
    if type(state) == "table" then
        local unlockAt = tonumber(state.unlockAt) or 0
        local day = tonumber(state.day) or 1
        if unlockAt <= os.time() then
            fire("Daily", "ClaimDaily", day)
        end
    end
end)
worker("AutoPlaytime", 30, function()
    if not PlaytimeRewardsConfig then return end
    local state = invoke("Playtime", "GetPlaytimeState")
    if type(state) ~= "table" then return end
    local seconds = tonumber(state.seconds) or 0
    local rewards = PlaytimeRewardsConfig.Rewards
    if type(rewards) ~= "table" then return end
    for i, item in ipairs(rewards) do
        local at = tonumber(item.at) or math.huge
        local claimed = true
        if PlaytimeRewardsConfig.IsClaimed then
            local ok, res = pcall(PlaytimeRewardsConfig.IsClaimed, state.claimed, i)
            claimed = ok and res or false
        end
        if not claimed and seconds >= at then
            fire("Playtime", "ClaimPlaytime", i)
            task.wait(1)
        end
    end
end)
task.spawn(function()
    local ready = R("UI", "OfflineCashReady")
    if ready then
        ready.OnClientEvent:Connect(function()
            if S.Running and S.AutoOfflineCash then
                fire("UI", "ClaimOfflineCash")
            end
        end)
    end
end)
worker("AutoFreeReward", 60, function()
    fire("UI", "FreeReward", "claim")
end)
worker("AutoFreeBrainrot", 10, function()
    if LP:GetAttribute("FreeBrainrotClaimed") ~= true then
        if throttle("freebrainrot", 5) then
            fire("Shop", "ClaimFreeBrainrot")
        end
    end
end)
worker("AutoRedeemCodes", 300, function()
    local codes = CodesConfig and CodesConfig.Codes or {}
    for code in pairs(codes) do
        task.spawn(function()
            local res = invoke("Shop", "RedeemCode", code)
            if type(res) == "table" and res.ok == false then
                status("code " .. tostring(code) .. ": already used or invalid")
            end
        end)
    end
end)

--------------------------------------------------------------- EVENTS — wheel
local wheelBusy = false
task.spawn(function()
    local result = R("Wheel", "SpinResult")
    if result then
        result.OnClientEvent:Connect(function()
            task.delay(0.8, function() wheelBusy = false end)
        end)
    end
end)
worker("AutoWheel", 2, function()
    if wheelBusy then return end
    local state = invoke("Wheel", "GetWheelState")
    if type(state) == "table" and state.ready and (tonumber(state.spins) or 0) > 0 and state.spinning ~= true then
        fire("Wheel", "RequestSpin", S.WheelFast == true)
        wheelBusy = true
        task.delay(8, function() wheelBusy = false end)
    end
end)

--------------------------------------------------------------- EVENTS — halloween
local function halloweenActive()
    if HalloweenState and HalloweenState.IsOn then
        local ok, res = pcall(HalloweenState.IsOn)
        if ok then return res end
    end
    return false
end
local function halloweenTravel()
    fire("Halloween", "Travel", S.HalloweenTravelTarget == "lobby" and "lobby" or "island")
end
worker("AutoTrickOrTreat", 20, function()
    if not halloweenActive() then return end
    local island = workspace:FindFirstChild("HalloweenIsland")
    if not island then return end
    for _, model in ipairs(island:GetDescendants()) do
        if model:IsA("Model") then
            local key = model:GetAttribute("HouseKey") or model.Name
            local touch = model:FindFirstChild("TouchPart", true)
            if touch and throttle("tot:" .. key, 305) then
                fire("Halloween", "TrickOrTreat", key)
            end
            task.wait(0.1)
        end
    end
end)
task.spawn(function()
    local candies = R("Halloween", "Candies")
    if not candies then return end
    candies.OnClientEvent:Connect(function(op, payload)
        if not (S.Running and S.AutoCandy) or typeof(payload) ~= "table" then return end
        if op == "add" then
            local part = hrp()
            for _, tuple in ipairs(payload) do
                local id, position = tuple[1], tuple[2]
                if id ~= nil and typeof(position) == "Vector3" and part then
                    if (position - part.Position).Magnitude <= (tonumber(S.CandyRadius) or 9) + 1 then
                        fire("Halloween", "Collect", id)
                    end
                end
            end
        end
    end)
end)
worker("AutoHalloweenRebirth", 30, function()
    if not halloweenActive() or not HalloweenConfig then return end
    local candy = tonumber(LP:GetAttribute("CandyCorn")) or 0
    local rebirths = tonumber(LP:GetAttribute(HalloweenConfig.RebirthKey or "HalloweenRebirths")) or 0
    local cost = nil
    if HalloweenConfig.RebirthCost then
        cost = tonumber(HalloweenConfig.RebirthCost(rebirths))
    else
        cost = tonumber(HalloweenConfig.FirstCost or 230) or 230
    end
    if cost and candy >= cost * 1.05 then
        fire("Halloween", "Rebirth")
    end
end)
worker("AutoLuckyBlock", 60, function()
    if not halloweenActive() then return end
    local bundle = math.clamp(math.floor(tonumber(S.LuckyBlockBundle) or 1), 1, 3)
    fire("Halloween", "BuyLuckyBlock", bundle)
end)
worker("AutoLuckyOni", 8, function()
    local res = invoke("LuckyOni", "Roll")
    if type(res) == "table" and res.reels then
        status("LuckyOni: " .. tostring(res.outcome or "spin") .. " | waiting cinematic")
        task.wait(5.2)
        fire("LuckyOni", "Done")
    end
end)

--------------------------------------------------------------- TELEPORT
local function teleportTo(target)
    if throttle("tp:" .. target, 0.5) then
        fire("UI", "TopTeleport", target)
        status("teleport: " .. target)
    end
end

--------------------------------------------------------------- TRADE protection
task.spawn(function()
    while S.Running do
        if S.AutoDeclineTrades then
            pcall(function()
                local hud = LP:FindFirstChildOfClass("PlayerGui")
                hud = hud and hud:FindFirstChild("HUD")
                local frame = hud and hud:FindFirstChild("TradeFrame")
                local noti = frame and frame:FindFirstChild("TradeNoti")
                if noti and noti.Visible and throttle("tradedecline", 2) then
                    fire("Trade", "RespondInvite", false)
                    status("trade invite declined")
                end
            end)
        end
        task.wait(1)
    end
end)

-- ---------------------------------------------------------------- UI
local Window = Fluent:CreateWindow({
    Title = "CAT EMPIRE", SubTitle = "Steal A Brainrot",
    TabWidth = 158, Size = UDim2.fromOffset(765, 480),
    Acrylic = false, Animated = false, Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
    ScreenGuiName = "CAT_EMPIRE_STEAL_BRAINROT_99881468171809",
})
local Tabs = {
    Farm = Window:AddTab({Title = "Farm", Icon = "solar/home-bold"}),
    Rewards = Window:AddTab({Title = "Rewards", Icon = "solar/gift-bold"}),
    Events = Window:AddTab({Title = "Events", Icon = "solar/moon-bold"}),
    Teleport = Window:AddTab({Title = "Teleport", Icon = "solar/bolt-bold"}),
    Items = Window:AddTab({Title = "Items", Icon = "solar/bag-bold"}),
    Trade = Window:AddTab({Title = "Trade", Icon = "solar/text-circle-bold"}),
    Settings = Window:AddTab({Title = "Settings", Icon = "solar/settings-bold"}),
    Misc = Window:AddTab({Title = "Misc", Icon = "solar/user-bold"}),
}
local function toggle(tab, key, title, callback)
    Toggles[key] = tab:AddToggle("SB_" .. key, {
        Title = title, Default = false,
        Callback = function(value)
            S[key] = value == true
            if callback then pcall(callback, S[key]) end
        end,
    })
end

-- FARM tab
Status = Tabs.Farm:AddParagraph({Title = "Steal A Brainrot", Content = "Initializing"})
toggle(Tabs.Farm, "AutoCollectCash", "Auto Collect Cash")
Tabs.Farm:AddSlider("SB_CollectInterval", {
    Title = "Collect Interval (s)", Default = 0.35, Min = 0.15, Max = 3, Rounding = 2,
    Callback = function(value) S.CollectInterval = math.max(0.15, tonumber(value) or 0.35) end,
})
toggle(Tabs.Farm, "AutoSell", "Auto Sell Selected Rarities")
Tabs.Farm:AddDropdown("SB_SellRarities", {
    Title = "Sell Rarities", Values = RarityOrder, Multi = true, Default = {},
    DropdownOutsideWindow = true,
    Callback = function(value) S.SelectedSellRarities = value end,
})
toggle(Tabs.Farm, "SellAllInventoryToggle", "SellAll When Inventory Full (>95% cap)")
Tabs.Farm:AddButton({Title = "Sell All Now (danger)", Callback = function() fire("Sell", "SellAll") end})
toggle(Tabs.Farm, "AutoPlaceBest", "Auto Place Best")
Tabs.Farm:AddSlider("SB_PlaceBestInterval", {
    Title = "Place Best Interval (s)", Default = 10, Min = 3, Max = 60, Rounding = 0,
    Callback = function(value) S.PlaceBestInterval = math.max(3, tonumber(value) or 10) end,
})
toggle(Tabs.Farm, "AutoUpgrade", "Auto Upgrade Placed Brainrots (experimental)")

-- REWARDS tab
Tabs.Rewards:AddSection("Auto Claim")
toggle(Tabs.Rewards, "AutoDaily", "Auto Daily Rewards")
toggle(Tabs.Rewards, "AutoPlaytime", "Auto Playtime Rewards")
toggle(Tabs.Rewards, "AutoOfflineCash", "Auto Offline Cash")
toggle(Tabs.Rewards, "AutoFreeReward", "Auto Free Reward (timer box)")
toggle(Tabs.Rewards, "AutoFreeBrainrot", "Auto Free Brainrot")
Tabs.Rewards:AddSection("Codes")
toggle(Tabs.Rewards, "AutoRedeemCodes", "Auto Redeem All Known Codes")
Tabs.Rewards:AddButton({Title = "Redeem Codes Now", Callback = function()
    local codes = CodesConfig and CodesConfig.Codes or {}
    local done = 0
    for code in pairs(codes) do
        task.spawn(function()
            pcall(function() invoke("Shop", "RedeemCode", code) end)
            done = done + 1
        end)
    end
    notify("Redeem attempts queued: " .. tostring(done))
end})

-- EVENTS tab
Tabs.Events:AddSection("Wheel")
toggle(Tabs.Events, "AutoWheel", "Auto Wheel Spin")
Tabs.Events:AddToggle("SB_WheelFast", {
    Title = "Fast Spin", Default = false,
    Callback = function(value) S.WheelFast = value == true end,
})
Tabs.Events:AddSection("Halloween")
toggle(Tabs.Events, "AutoTrickOrTreat", "Auto Trick Or Treat")
toggle(Tabs.Events, "AutoCandy", "Auto Candy Collect (nearby)")
Tabs.Events:AddSlider("SB_CandyRadius", {
    Title = "Candy Radius (server max 9)", Default = 9, Min = 2, Max = 12, Rounding = 0,
    Callback = function(value) S.CandyRadius = math.clamp(tonumber(value) or 9, 2, 16) end,
})
toggle(Tabs.Events, "AutoHalloweenRebirth", "Auto Halloween Rebirth")
toggle(Tabs.Events, "AutoLuckyBlock", "Auto Buy Halloween Lucky Block (daily stock)")
Tabs.Events:AddDropdown("SB_LuckyBundle", {
    Title = "Lucky Block Bundle", Values = {1, 5, 10}, Default = 1,
    Callback = function(value) S.LuckyBlockBundle = tonumber(value) or 1 end,
})
toggle(Tabs.Events, "AutoLuckyOni", "Auto Lucky Oni Rolls")
Tabs.Events:AddSection("Volcano (manual)")
Tabs.Events:AddDropdown("SB_VolcanoBundle", {
    Title = "Volcano Meteor Bundle", Values = {1, 5, 10}, Default = 1,
    Callback = function(value) S._volcanoBundle = tonumber(value) or 1 end,
})
Tabs.Events:AddButton({Title = "Buy Meteor Blocks", Callback = function()
    fire("Volcano", "BuyBlocks", math.clamp(S._volcanoBundle or 1, 1, 3))
end})
Tabs.Events:AddButton({Title = "Buy Volcano Totem (65k)", Callback = function() fire("Volcano", "BuyTotem") end})
Tabs.Events:AddButton({Title = "Buy Cerberus (200k)", Callback = function() fire("Volcano", "BuyBrainrot") end})
Tabs.Events:AddButton({Title = "Buy Lava Skin (120k)", Callback = function() fire("Volcano", "BuySkin") end})

-- TELEPORT tab
Tabs.Teleport:AddSection("Top Bar Points")
Tabs.Teleport:AddButton({Title = "Teleport Jump Zone", Callback = function() teleportTo("Jump") end})
Tabs.Teleport:AddButton({Title = "Teleport My Base", Callback = function() teleportTo("Base") end})
Tabs.Teleport:AddButton({Title = "Teleport Buy Area", Callback = function() teleportTo("Buy") end})
Tabs.Teleport:AddSection("Halloween Island")
Tabs.Events:AddDropdown("SB_HalloweenTravel", {
    Title = "Travel Target", Values = {"island", "lobby"}, Default = "island",
    Callback = function(value) S.HalloweenTravelTarget = tostring(value) end,
})
Tabs.Teleport:AddButton({Title = "Travel Halloween", Callback = function() halloweenTravel() end})

-- ITEMS tab
local potionIds = {}
local potionList = {}
do
    local cfg = requireModule("PotionConfig")
    if cfg then
        for id in pairs(cfg) do
            if type(id) == "string" then potionIds[#potionIds + 1] = id end
        end
        table.sort(potionIds)
        potionList = potionIds
        for _, meta in ipairs(cfg) do
            if type(meta) == "table" and type(meta.id) == "string" then
                table.insert(potionList, meta.id)
            end
        end
    end
    if #potionList == 0 then potionList = {"LuckPotion", "TrainPotion", "HalloweenCashPotion"} end
    local seen, unique = {}, {}
    for _, id in ipairs(potionList) do
        if not seen[id] then seen[id] = true unique[#unique + 1] = id end
    end
    potionList = unique
end
Tabs.Items:AddSection("Potions")
Tabs.Items:AddDropdown("SB_PotionId", {
    Title = "Potion", Values = potionList, Default = potionList[1], DropdownOutsideWindow = true,
    Callback = function(value) S._potionId = tostring(value) end,
})
Tabs.Items:AddButton({Title = "Drink Potion", Callback = function()
    if S._potionId then fire("Potions", "DrinkPotion", S._potionId) end
end})
Tabs.Items:AddSection("Boss Cases")
local caseId = nil
if BossCaseConfig and BossCaseConfig.Id then
    caseId = tostring(BossCaseConfig.Id)
    Tabs.Items:AddButton({Title = "Open 1 Boss Case", Callback = function()
        fire("Cases", "Open", caseId, 1)
    end})
    Tabs.Items:AddButton({Title = "Open All Boss Cases", Callback = function()
        local owned = {}
        for _, container in ipairs({LP:FindFirstChildOfClass("Backpack"), LP.Character}) do
            if container then
                for _, tool in ipairs(container:GetChildren()) do
                    if tool:IsA("Tool") and tool:GetAttribute("caseId") ~= nil then
                        owned[tool] = true
                    end
                end
            end
        end
        for _ in pairs(owned) do
            fire("Cases", "Open", caseId, 1)
            task.wait(1.1)
        end
        status("cases opened: " .. tostring(next(owned) ~= nil and #owned or 0))
    end})
end

-- TRADE tab
toggle(Tabs.Trade, "AutoDeclineTrades", "Auto Decline Incoming Trades")
Tabs.Trade:AddParagraph({
    Title = "Protection",
    Content = "Incoming trade invites are refused instantly. Manual trading stays untouched.",
})

-- ---------------------------------------------------------------- settings module
local function loadSetting(name)
    local url = "https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/StealABrainrot/" .. name .. ".lua"
    local ok, fn = pcall(function()
        local text = game:HttpGet(url, true)
        return assert(loadstring(text))()
    end)
    if not ok or type(fn) ~= "function" then errorState(name, fn) return nil end
    return fn
end
local featureCleanups = {}
local function cleanup()
    if not S.Running then return end
    S.Running = false
    for _, fn in ipairs(featureCleanups) do pcall(fn) end
    for _, connection in ipairs(Links) do pcall(function() connection:Disconnect() end) end
    pcall(function() Window:Destroy() end)
    Env.__CE_STEAL_BRAINROT_CLEANUP = nil
end
Env.__CE_STEAL_BRAINROT_CLEANUP = cleanup

local settingsInit = loadSetting("Settings")
if settingsInit then
    local ctx = {
        S = S, Player = LP, RS = RS, Tabs = Tabs, Toggles = Toggles,
        Window = Window, Fluent = Fluent, Links = Links, HttpService = HttpService,
        Status = status, Notify = notify, Error = errorState, Cleanup = cleanup,
        GuiName = "CAT_EMPIRE_STEAL_BRAINROT_99881468171809",
        ExtraProfileKeys = {"SelectedSellRarities", "HalloweenTravelTarget", "LuckyBlockBundle", "CandyRadius",
            "CollectInterval", "PlaceBestInterval", "WheelDelay"},
    }
    local ok, result = pcall(settingsInit, ctx)
    if not ok then errorState("Settings", result)
    elseif type(result) == "function" then featureCleanups[#featureCleanups + 1] = result end
end

-- status loop
task.spawn(function()
    while S.Running do
        pcall(function()
            Status:SetTitle("Steal A Brainrot")
            Status:SetDesc(S.LastAction .. (S.LastError ~= "" and (" | " .. S.LastError) or ""))
        end)
        task.wait(1.2)
    end
end)

status("loaded")
notify("CAT EMPIRE loaded: Steal A Brainrot")
