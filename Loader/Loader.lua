-- ============================================================
--  CAT EMPIRE | LOADER
--  Desenvolvido por Danonin
-- ============================================================

local URL = "https://raw.githubusercontent.com/DanoninCat/DanoninScript/refs/heads/main/Scripts/CatEmpire_v5.2_0.lua"

local ok, err = pcall(function()
    loadstring(game:HttpGet(URL, true))()
end)

if not ok then
    warn("[CatEmpire] Erro ao carregar: " .. tostring(err))
end
