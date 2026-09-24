-- Re Adventures - Targeted Trait Snapshot Dumper
-- Run once BEFORE a manual trait reroll and once AFTER it.
-- This intentionally avoids scanning the whole game so it finishes quickly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
assert(player, "LocalPlayer unavailable")

local env = (getgenv and getgenv()) or _G
local writefileFn = rawget(env, "writefile") or rawget(_G, "writefile")
local makefolderFn = rawget(env, "makefolder") or rawget(_G, "makefolder")
local isfolderFn = rawget(env, "isfolder") or rawget(_G, "isfolder")
local setclipboardFn = rawget(env, "setclipboard") or rawget(_G, "setclipboard")

local function fullName(instance)
    if not instance then return nil end
    local ok, value = pcall(function() return instance:GetFullName() end)
    return ok and value or tostring(instance)
end

local function safeAttributes(instance)
    local ok, attrs = pcall(function() return instance:GetAttributes() end)
    return ok and attrs or {}
end

local function describe(instance)
    local out = {
        name = instance.Name,
        class = instance.ClassName,
        path = fullName(instance),
        attributes = safeAttributes(instance),
    }

    if instance:IsA("ValueBase") then
        local ok, value = pcall(function() return instance.Value end)
        if ok then
            if typeof(value) == "Instance" then
                out.value = fullName(value)
            else
                out.value = tostring(value)
            end
        end
    end

    if instance:IsA("ObjectValue") then
        out.objectValue = fullName(instance.Value)
        if instance.Value then
            out.objectAttributes = safeAttributes(instance.Value)
        end
    end

    if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
        out.text = instance.Text
    end

    if instance:IsA("GuiObject") then
        out.visible = instance.Visible
    elseif instance:IsA("ScreenGui") then
        out.enabled = instance.Enabled
    end

    if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
        out.image = instance.Image
    end

    return out
end

local function collectTree(root, maxItems)
    local result = {}
    if not root then return result end

    table.insert(result, describe(root))

    local count = 1
    for _, instance in ipairs(root:GetDescendants()) do
        count += 1
        if count > (maxItems or 5000) then
            table.insert(result, {
                truncated = true,
                limit = maxItems or 5000,
                root = fullName(root),
            })
            break
        end
        table.insert(result, describe(instance))
    end

    return result
end

local function collectRemotes()
    local result = {}

    for _, instance in ipairs(ReplicatedStorage:GetDescendants()) do
        if instance:IsA("RemoteFunction") or instance:IsA("RemoteEvent") then
            table.insert(result, describe(instance))
        end
    end

    table.sort(result, function(a, b)
        return tostring(a.path) < tostring(b.path)
    end)

    return result
end

local function collectTraitNamedObjects(root, maxItems)
    local result = {}
    if not root then return result end

    local count = 0
    for _, instance in ipairs(root:GetDescendants()) do
        local name = instance.Name:lower()
        local path = fullName(instance):lower()

        if name:find("trait", 1, true)
            or name:find("reroll", 1, true)
            or path:find("trait", 1, true)
            or path:find("reroll", 1, true)
        then
            count += 1
            if count > (maxItems or 3000) then
                table.insert(result, {
                    truncated = true,
                    limit = maxItems or 3000,
                    root = fullName(root),
                })
                break
            end

            table.insert(result, describe(instance))
        end
    end

    return result
end

local playerGui = player:FindFirstChildOfClass("PlayerGui")
local traitGui = playerGui and playerGui:FindFirstChild("TraitReroll")
local character = player.Character
local petsFolder = character and character:FindFirstChild("_pets_folder")

-- In this game the character can be parented directly under Workspace with
-- its _pets_folder replicated beneath it.
if not petsFolder then
    local worldCharacter = Workspace:FindFirstChild(player.Name)
    petsFolder = worldCharacter and worldCharacter:FindFirstChild("_pets_folder")
end

local snapshot = {
    metadata = {
        generatedAt = os.time(),
        placeId = game.PlaceId,
        gameId = game.GameId,
        jobId = game.JobId,
        playerName = player.Name,
        playerUserId = player.UserId,
    },

    player = {
        attributes = safeAttributes(player),
    },

    traitGui = collectTree(traitGui, 5000),
    remotes = collectRemotes(),
    replicatedTraitObjects = collectTraitNamedObjects(ReplicatedStorage, 3000),
    workspaceTraitObjects = collectTraitNamedObjects(Workspace, 3000),
    pets = collectTree(petsFolder, 3000),
}

local ok, encoded = pcall(HttpService.JSONEncode, HttpService, snapshot)
assert(ok, "JSONEncode failed: " .. tostring(encoded))

local folder = "CatEmpire"
local diagnostics = folder .. "/Diagnostics"

if type(makefolderFn) == "function" then
    if type(isfolderFn) ~= "function" or not isfolderFn(folder) then
        pcall(makefolderFn, folder)
    end
    if type(isfolderFn) ~= "function" or not isfolderFn(diagnostics) then
        pcall(makefolderFn, diagnostics)
    end
end

local stamp = os.date("%Y%m%d_%H%M%S")
local path = diagnostics .. "/trait_snapshot_" .. stamp .. ".json"

if type(writefileFn) == "function" then
    local saved, err = pcall(writefileFn, path, encoded)
    if saved then
        print("[TraitSnapshot] Saved:", path)
    else
        warn("[TraitSnapshot] writefile failed:", err)
        path = nil
    end
elseif type(setclipboardFn) == "function" then
    pcall(setclipboardFn, encoded)
    print("[TraitSnapshot] writefile unavailable; JSON copied to clipboard.")
else
    warn("[TraitSnapshot] No writefile/setclipboard support; printing JSON.")
    print(encoded)
end

print("[TraitSnapshot] Trait GUI objects:", #snapshot.traitGui)
print("[TraitSnapshot] Replicated remotes:", #snapshot.remotes)
print("[TraitSnapshot] Replicated trait objects:", #snapshot.replicatedTraitObjects)
print("[TraitSnapshot] Workspace trait objects:", #snapshot.workspaceTraitObjects)
print("[TraitSnapshot] Pet objects:", #snapshot.pets)

return {
    path = path,
    snapshot = snapshot,
}
