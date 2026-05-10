-- ============================================================
--  DANONIN HUB | Loader
--  github.com/DanoninCat/DanoninScript
-- ============================================================

local BASE = "https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Games/"

local Games = {
    [18923620224]    = BASE .. "AnimeWarriors3.lua",
    [75995379831247] = BASE .. "DigAndGrow.lua",
}

local script = Games[game.PlaceId]
if not script then return end

loadstring(game:HttpGet(script, true))()
