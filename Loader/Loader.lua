-- ============================================================
--  DANONIN HUB | Loader
--  github.com/DanoninCat/DanoninScript
-- ============================================================

local BASE = "https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Games/"

local Games = {
    [18923620224]    = BASE .. "AnimeWarriors3.lua",
    [75995379831247] = BASE .. "DigAndGrow.lua",
    -- [PLACEID_NOVO_JOGO] = BASE .. "NovoJogo.lua",  -- substituir pelo PlaceId real
}

local script = Games[game.PlaceId]
if not script then
    warn("[DanoninHub] Jogo nao suportado: " .. tostring(game.PlaceId))
    return
end

loadstring(game:HttpGet(script, true))()
