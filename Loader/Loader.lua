-- ============================================================
--  CAT EMPIRE | LOADER | Desenvolvido por Danonin
--  Detecta o jogo e carrega o script correto
-- ============================================================

local GAMES = {
    -- Anime Warriors 3 (PlaceId — atualizar se necessário)
    [7457800263] = "https://raw.githubusercontent.com/DanoninCat/DanoninScript/refs/heads/main/Scripts/CatEmpire_v5_22.lua",
}

local DEFAULT = "https://raw.githubusercontent.com/DanoninCat/DanoninScript/refs/heads/main/Scripts/CatEmpire_v5_22.lua"

local url = GAMES[game.PlaceId] or DEFAULT

local ok, err = pcall(function()
    loadstring(game:HttpGet(url, true))()
end)

if not ok then
    warn("[CatEmpire Loader] Erro: " .. tostring(err))
end
