-- ============================================================
--  DANONIN HUB | Loader v2
--  github.com/DanoninCat/DanoninScript
-- ============================================================

local BASE = "https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Games/"

local Games = {
    [18923620224]    = BASE .. "AnimeWarriors3.lua",
    [75995379831247] = BASE .. "DigAndGrow.lua",
}

local pid = tonumber(game.PlaceId) or 0
local url = Games[pid]

if not url then
    warn("[Loader] PlaceId=" .. tostring(pid) .. " nao mapeado.")
    warn("[Loader] Scripts disponiveis:")
    warn("  Dig & Grow:       " .. BASE .. "DigAndGrow.lua")
    warn("  Anime Warriors 3: " .. BASE .. "AnimeWarriors3.lua")
    return
end

warn("[Loader] Carregando PlaceId=" .. tostring(pid))
local ok, err = pcall(function()
    loadstring(game:HttpGet(url, true))()
end)

if not ok then
    warn("[Loader] Erro: " .. tostring(err))
end
