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
warn("[Loader] URL: " .. url)

local ok, result = pcall(function()
    local src = game:HttpGet(url, true)
    loadstring(src)()
end)

if not ok then
    warn("[Loader] Falhou: " .. tostring(result))
    if tostring(result):find("404") or tostring(result):find("HTTP") then
        warn("[Loader] Arquivo nao encontrado no GitHub!")
        warn("[Loader] Faca upload do DigAndGrow.lua em:")
        warn("[Loader] " .. url)
        warn("[Loader] Ou execute o DigAndGrow_v1_8.lua direto no executor.")
    end
end
