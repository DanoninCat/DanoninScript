local TARGET = 105596644794991
local BASE = "https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/"
local currentPlace = game.PlaceId
local universe = game.GameId
if currentPlace ~= TARGET and universe ~= TARGET then
    return loadstring(game:HttpGet(BASE .. "Loader/Legacy.lua", true))()
end
local env = (getgenv and getgenv()) or _G
env.__CE_RE105_BOOT_STAGE = "Starting"
env.__CE_RE105_BOOT_ERROR = nil

local function module(path, stage)
    env.__CE_RE105_BOOT_STAGE = stage
    local ok, source = pcall(function()
        return game:HttpGet(BASE .. path, true)
    end)
    if not ok then
        error(stage .. ": HTTP failure: " .. tostring(source), 0)
    end
    if type(source) ~= "string" or #source == 0 then
        error(stage .. ": empty file: " .. path, 0)
    end
    local chunk, syntaxError = loadstring(source)
    if not chunk then
        error(stage .. ": invalid script: " .. tostring(syntaxError), 0)
    end
    return chunk()
end

local ok, result = pcall(function()
    local fluentSource = module("Loader/FluentPayload.lua", "Loading UI")
    if type(fluentSource) ~= "string" or #fluentSource == 0 then
        error("UI module did not return source", 0)
    end
    env.__CE_F_91A7 = fluentSource
    return module("UntitledDefense105/Main.lua", "Loading CAT EMPIRE")
end)
env.__CE_F_91A7 = nil
if not ok then
    local diagnostic = "[CAT EMPIRE RE Adventures] " .. tostring(result)
    env.__CE_RE105_BOOT_ERROR = diagnostic
    warn(diagnostic)
    error(diagnostic, 0)
end
env.__CE_RE105_BOOT_STAGE = "Loaded"
return result
