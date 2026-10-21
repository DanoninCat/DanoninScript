# CAT EMPIRE — regras permanentes para scripts

- Todo script, janela, identidade visual, namespace e novo módulo deve utilizar a marca **CAT EMPIRE**. Não introduzir marcas alternativas.
- Preservar a interface personalizada do projeto, carregada exclusivamente de `Loader/FluentPayload.lua` (a mesma biblioteca extraída em `CAT_EMPIRE_INTERFACE`). Não trocar por outra UI.
- Todos os jogos novos devem ser integrados pelo loader principal `Loader/Loader.lua`, mantendo a URL pública `https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Loader/Loader.lua`.
- Cada rota no loader deve preparar `env.__CE_F_91A7` com o payload da interface antes de executar o módulo do jogo.
- Manter as abas `SETTINGS` e `MISC`, com os recursos padronizados do projeto, incluindo Auto Rejoin, Anti AFK, Themes, Profiles, Auto Load Profiles, Auto Close UI, Auto Load After Rejoin e Boost FPS.
- `MISC` deve manter avatar e informações do usuário, informações e imagem do jogo e, quando disponíveis, campos sociais.
- Não colocar descrições nas opções da interface.
- ESP e Chams devem começar em vermelho (`#FF0000`), com seletores independentes para alteração da cor.
- Verificar o funcionamento antes de declarar uma função como operacional; mecanismos dependentes de validação do servidor devem ser indicados como não confirmados até teste.
- Manter a implementação no repositório DanoninScript e preservar as demais rotas no loader.

- Em MISC, obter sempre o nome real do jogo automaticamente pela API do Roblox, usando `MarketplaceService:GetProductInfo(game.PlaceId).Name` com `pcall` e fallback para `game.Name`. Nunca inventar ou fixar manualmente o nome do jogo.
- Para a imagem do jogo, usar o universo atual (`game.GameId`) e a fonte nativa de miniaturas do Roblox quando disponível.
- Distribuição preferida: somente scripts efetivamente concluídos e integrados, empacotados no loader principal ofuscado; evitar pastas de módulos dispersos após consolidação. Preservar o caminho público `Loader/Loader.lua`.
