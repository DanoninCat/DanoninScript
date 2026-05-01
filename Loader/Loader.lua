-- ============================================================
--  CAT EMPIRE | LOADER | Desenvolvido por Danonin
-- ============================================================
local URL = "https://raw.githubusercontent.com/DanoninCat/DanoninScript/refs/heads/main/Scripts/CatEmpire_v5_17.lua"
local ok, err = pcall(function() loadstring(game:HttpGet(URL, true))() end)
if not ok then warn("[CatEmpire] Erro: " .. tostring(err)) end
