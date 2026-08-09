-- ============================================================
--  DANONIN HUB | Loader
--  github.com/DanoninCat/DanoninScript
-- ============================================================

local BASE = "https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Games/"

local Games = {
    [18923620224]    = BASE .. "AnimeWarriors3.lua",
    [75995379831247] = BASE .. "DigAndGrow.lua",
    -- [PLACEID_ANIME_CAPTURE] = BASE .. "AnimeCapture.lua",  -- substituir pelo PlaceId real
}

local script = Games[game.PlaceId]
if not script then
    warn("[DanoninHub] Jogo nao suportado: " .. tostring(game.PlaceId))
    return
end

-- FIX: cache-busting — raw.githubusercontent.com fica atrás de CDN (Fastly)
-- que guarda cache por alguns minutos após um upload novo.
-- Adicionar um parâmetro único a cada execução força buscar a versão mais recente.
local cacheBuster = "?t=" .. tostring(os.time()) .. tostring(math.random(1000, 9999))
local finalURL = script .. cacheBuster

local ok, err = pcall(function()
    loadstring(game:HttpGet(finalURL, true))()
end)

if not ok then
    warn("[DanoninHub] Erro ao carregar: " .. tostring(err))
    warn("[DanoninHub] URL tentada: " .. finalURL)
end
