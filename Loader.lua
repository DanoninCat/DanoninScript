-- ============================================================
--  CAT EMPIRE | LOADER
--  Desenvolvido por Danonin
--  Troque SEU_USER pelo seu usuario do GitHub
-- ============================================================

local URL = "https://raw.githubusercontent.com/SEU_USER/CatEmpire/main/Scripts/CatEmpire_v5_0.lua"

local ok, err = pcall(function()
    loadstring(game:HttpGet(URL, true))()
end)

if not ok then
    warn("[CatEmpire] Erro ao carregar: " .. tostring(err))
end
