local TARGET = 105596644794991
local BASE = "https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/"
local env = (getgenv and getgenv()) or _G
env.__CE_RE105_BOOT_STAGE = "Router"
env.__CE_RE105_BOOT_ERROR = nil
env.__CE_RE105_FEATURES_ERROR = nil
env.__CE_RE105_PLACE_ID = game.PlaceId
env.__CE_RE105_UNIVERSE_ID = game.GameId

local function matchesREAdventures105()
    if game.PlaceId == TARGET or game.GameId == TARGET then
        return true, "Target ID"
    end
    -- Some RE Adventures lobbies and match instances use different PlaceIds.
    -- Recognize only this game's exact client modules and remote contract.
    local storage = game:GetService("ReplicatedStorage")
    local remotes = storage:FindFirstChild("Remotes")
    if not remotes then
        remotes = storage:WaitForChild("Remotes", 5)
    end
    if not remotes then
        return false, "Remotes missing"
    end
    for _, name in ipairs({
        "InventoryRequest", "InventoryResult", "TraitRerollRequest",
        "TraitRerollResult", "HalloweenShop"
    }) do
        if not remotes:FindFirstChild(name) then
            return false, "Missing " .. name
        end
    end
    for _, name in ipairs({"TraitData", "UnitData", "ItemData", "HalloweenData"}) do
        if not storage:FindFirstChild(name) then
            return false, "Missing " .. name
        end
    end
    return true, "Client fingerprint"
end

local function loadModule(path, stage)
    env.__CE_RE105_BOOT_STAGE = stage
    local ok, body = pcall(function()
        return game:HttpGet(BASE .. path, true)
    end)
    if not ok then
        error(stage .. ": HTTP failure: " .. tostring(body), 0)
    end
    if type(body) ~= "string" or #body == 0 then
        error(stage .. ": empty file: " .. path, 0)
    end
    local chunk, syntaxError = loadstring(body)
    if not chunk then
        error(stage .. ": invalid Lua: " .. tostring(syntaxError), 0)
    end
    return chunk()
end

local ok, result = pcall(function()
    local isTarget, reason = matchesREAdventures105()
    env.__CE_RE105_ROUTE = reason
    if not isTarget then
        env.__CE_RE105_BOOT_STAGE = "Legacy - different game"
        return loadModule("Loader/Legacy.lua", "Loading another CAT EMPIRE game")
    end
    env.__CE_RE105_BOOT_STAGE = "Loading UI"
    local fluentSource = loadModule("Loader/FluentPayload.lua", "Loading UI")
    if type(fluentSource) ~= "string" or #fluentSource == 0 then
        error("UI module returned an invalid source", 0)
    end
    env.__CE_F_91A7 = fluentSource
    return loadModule("UntitledDefense105/Main.lua", "Loading RE Adventures")
end)
env.__CE_F_91A7 = nil
if not ok then
    local diagnostic = "[CAT EMPIRE] " .. tostring(result)
    env.__CE_RE105_BOOT_ERROR = diagnostic
    env.__CE_RE105_BOOT_STAGE = "Error"
    warn(diagnostic)
    error(diagnostic, 0)
end
if env.__CE_RE105_BOOT_STAGE ~= "Loading another CAT EMPIRE game" then
    env.__CE_RE105_BOOT_STAGE = "Loaded"
end
return result
