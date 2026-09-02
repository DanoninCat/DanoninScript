-- ============================================================
--  DANONIN HUB | Loader v2.0
--  github.com/DanoninCat/DanoninScript
-- ============================================================

local BASE = "https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Games/"

-- ============================================================
-- [LISTA DE JOGOS SUPORTADOS]
-- ============================================================
local Games = {
    -- Jogos existentes
    [18923620224]    = BASE .. "AnimeWarriors3.lua",
    [75995379831247] = BASE .. "DigAndGrow.lua",
    [94717504417144] = BASE .. "AnimeCapture.lua",
    [6442957604]     = BASE .. "CustomPCTycoon.lua",
    [120851538706364] = BASE .. "MurderDuels.lua",
}

-- ============================================================
-- [VERIFICAÇÃO DO JOGO]
-- ============================================================
local gameId = game.PlaceId
local script = Games[gameId]

if not script then
    warn("[DanoninHub] Jogo nao suportado: " .. tostring(gameId))
    warn("[DanoninHub] PlaceId: " .. tostring(gameId))
    return
end

-- ============================================================
-- [CARREGAMENTO DO SCRIPT]
-- ============================================================
local cacheBuster = "?t=" .. tostring(os.time()) .. tostring(math.random(1000, 9999))
local finalURL = script .. cacheBuster

local ok, err = pcall(function()
    local source = game:HttpGet(finalURL, true)
    if not source or source == "" then
        error("ETAPA HttpGet: conteudo vazio ou nil retornado")
    end

    local fn, compileErr = loadstring(source)
    if not fn then
        error("ETAPA loadstring (erro de compilacao/sintaxe): " .. tostring(compileErr))
    end

    local success, runtimeErr = pcall(fn)
    if not success then
        error("ETAPA execucao (erro em tempo real dentro do script): " .. tostring(runtimeErr))
    end
end)

if not ok then
    warn("[DanoninHub] ERRO: " .. tostring(err))
    warn("[DanoninHub] URL: " .. finalURL)
else
    print("============================================================")
    print("  DANONIN HUB | Carregado com sucesso!")
    print("  Jogo: " .. tostring(gameId))
    print("  Script: " .. script)
    print("============================================================")
end
