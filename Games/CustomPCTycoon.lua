-- ============================================================
--  DANONIN HUB | Custom PC Tycoon
--  ID: 6442957604
-- ============================================================

-- Anti-duplicata
if _G.DanoninCustomPCTycoon then
    pcall(function() _G.DanoninCustomPCTycoon:Destroy() end)
end

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua", true))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua", true))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua", true))()

local Window = Fluent:CreateWindow({
    Title = "Danonin Hub",
    SubTitle = "Custom PC Tycoon",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

_G.DanoninCustomPCTycoon = Window

local Tabs = {
    Misc = Window:AddTab({ Title = "Misc", Icon = "coins" }),
    Economy = Window:AddTab({ Title = "Economy", Icon = "dollar-sign" }),
    PC = Window:AddTab({ Title = "PC", Icon = "cpu" }),
    Desk = Window:AddTab({ Title = "Desk", Icon = "layout-grid" }),
    Items = Window:AddTab({ Title = "Items", Icon = "package" }),
    Fun = Window:AddTab({ Title = "Fun", Icon = "sparkles" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}
local Options = Fluent.Options

local RemoteEvents = game.ReplicatedStorage.Resources.Remotes.RemoteEvents
local LocalPlayer = game.Players.LocalPlayer

-- ============================================================
-- MISC
-- ============================================================

Tabs.Misc:AddSection("Teleporte")

Tabs.Misc:AddButton({
    Title = "Teleportar para Casa",
    Callback = function()
        RemoteEvents.TpPlayer:FireServer("Home")
    end,
})

Tabs.Misc:AddButton({
    Title = "Teleportar para Loja",
    Callback = function()
        RemoteEvents.TpPlayer:FireServer("Store")
    end,
})

Tabs.Misc:AddButton({
    Title = "Teleportar para Loja Avançada",
    Callback = function()
        RemoteEvents.TpPlayer:FireServer("Store2")
    end,
})

Tabs.Misc:AddButton({
    Title = "Teleportar para Next Gen",
    Callback = function()
        RemoteEvents.TpPlayer:FireServer("Store3")
    end,
})

Tabs.Misc:AddButton({
    Title = "Teleportar para Storage",
    Callback = function()
        RemoteEvents.TpPlayer:FireServer("StorageUnit")
    end,
})

Tabs.Misc:AddSection("Códigos")

Tabs.Misc:AddInput("CodeInput", {
    Title = "Código",
    Placeholder = "Digite o código...",
})

Tabs.Misc:AddButton({
    Title = "Resgatar Código",
    Callback = function()
        local code = Options.CodeInput.Value or ""
        if code ~= "" then
            RemoteEvents.Code:FireServer(code)
        end
    end,
})

Tabs.Misc:AddButton({
    Title = "Resgatar Código (fluffy)",
    Callback = function()
        RemoteEvents.Code:FireServer("fluffy")
    end,
})

-- ============================================================
-- ECONOMY
-- ============================================================

Tabs.Economy:AddSection("Comprar Itens (Cash)")

Tabs.Economy:AddInput("BuyItemCash", {
    Title = "Nome do Item (Cash)",
    Placeholder = "Ex: Case, Motherboard...",
})

Tabs.Economy:AddButton({
    Title = "Comprar (Cash)",
    Callback = function()
        local item = Options.BuyItemCash.Value or ""
        if item ~= "" then
            RemoteEvents.BuyItem:FireServer(item, false)
        end
    end,
})

Tabs.Economy:AddSection("Comprar Itens (Gold)")

Tabs.Economy:AddInput("BuyItemGold", {
    Title = "Nome do Item (Gold)",
    Placeholder = "Digite o nome...",
})

Tabs.Economy:AddButton({
    Title = "Comprar (Gold)",
    Callback = function()
        local item = Options.BuyItemGold.Value or ""
        if item ~= "" then
            RemoteEvents.BuyItem:FireServer(item, true)
        end
    end,
})

Tabs.Economy:AddSection("Comprar Itens (Diamond)")

Tabs.Economy:AddInput("BuyItemDiamond", {
    Title = "Nome do Item (Diamond)",
    Placeholder = "Digite o nome...",
})

Tabs.Economy:AddButton({
    Title = "Comprar (Diamond)",
    Callback = function()
        local item = Options.BuyItemDiamond.Value or ""
        if item ~= "" then
            RemoteEvents.BuyItem2:FireServer(item)
        end
    end,
})

Tabs.Economy:AddSection("Comprar Itens (Sunstone)")

Tabs.Economy:AddInput("BuyItemSunstone", {
    Title = "Nome do Item (Sunstone)",
    Placeholder = "Digite o nome...",
})

Tabs.Economy:AddButton({
    Title = "Comprar (Sunstone)",
    Callback = function()
        local item = Options.BuyItemSunstone.Value or ""
        if item ~= "" then
            RemoteEvents.BuyItem4:FireServer(item)
        end
    end,
})

Tabs.Economy:AddSection("Transferência")

Tabs.Economy:AddInput("TransferCashGold", {
    Title = "Quantidade (Cash → Gold)",
    Placeholder = "Digite a quantidade...",
})

Tabs.Economy:AddButton({
    Title = "Transferir Cash → Gold",
    Callback = function()
        local qtd = tonumber(Options.TransferCashGold.Value) or 1
        RemoteEvents.Transfer:FireServer(qtd * 100000)
    end,
})

Tabs.Economy:AddInput("TransferGoldDiamond", {
    Title = "Quantidade (Gold → Diamond)",
    Placeholder = "Digite a quantidade...",
})

Tabs.Economy:AddButton({
    Title = "Transferir Gold → Diamond",
    Callback = function()
        local qtd = tonumber(Options.TransferGoldDiamond.Value) or 1
        RemoteEvents.Transfer2:FireServer(qtd * 1000000000)
    end,
})

Tabs.Economy:AddSection("Sunstone Seller")

Tabs.Economy:AddButton({
    Title = "Vender Sunstone (1)",
    Callback = function()
        RemoteEvents.SunstoneSeller:FireServer("1")
    end,
})

Tabs.Economy:AddButton({
    Title = "Vender Sunstone (2)",
    Callback = function()
        RemoteEvents.SunstoneSeller:FireServer("2")
    end,
})

Tabs.Economy:AddButton({
    Title = "Vender Sunstone (3)",
    Callback = function()
        RemoteEvents.SunstoneSeller:FireServer("3")
    end,
})

Tabs.Economy:AddSection("Reset")

Tabs.Economy:AddButton({
    Title = "Resetar Progresso (CUIDADO)",
    Callback = function()
        RemoteEvents.Reset:FireServer(true)
    end,
})

-- ============================================================
-- PC
-- ============================================================

Tabs.PC:AddSection("Ações do PC")

Tabs.PC:AddInput("PcName", {
    Title = "Nome do PC",
    Placeholder = "Digite o nome do PC...",
})

Tabs.PC:AddButton({
    Title = "Colocar PC no Pódio",
    Callback = function()
        local pcName = Options.PcName.Value or ""
        if pcName ~= "" then
            RemoteEvents.Podium:FireServer(pcName)
        end
    end,
})

Tabs.PC:AddButton({
    Title = "Desmontar PC",
    Callback = function()
        local pcName = Options.PcName.Value or ""
        if pcName ~= "" then
            RemoteEvents.DismantlePC:FireServer(pcName)
        end
    end,
})

Tabs.PC:AddButton({
    Title = "Vender PC",
    Callback = function()
        local pcName = Options.PcName.Value or ""
        if pcName ~= "" then
            RemoteEvents.Sell:FireServer(pcName)
        end
    end,
})

Tabs.PC:AddButton({
    Title = "Abrir PC Builder (Novo)",
    Callback = function()
        RemoteEvents.OpenPcUi:FireServer("New")
    end,
})

Tabs.PC:AddButton({
    Title = "Sair do PC Builder",
    Callback = function()
        RemoteEvents.OpenPcUi:FireServer("Leave")
    end,
})

Tabs.PC:AddButton({
    Title = "Sucatear PC",
    Callback = function()
        RemoteEvents.OpenPcUi:FireServer("Scrap")
    end,
})

-- ============================================================
-- DESK
-- ============================================================

Tabs.Desk:AddSection("Ações da Mesa")

Tabs.Desk:AddButton({
    Title = "Abrir Desk UI",
    Callback = function()
        RemoteEvents.OpenDeskUi:FireServer()
    end,
})

Tabs.Desk:AddSection("Enchant")

Tabs.Desk:AddInput("EnchantPcName", {
    Title = "Nome do PC para Enchant",
    Placeholder = "Digite o nome do PC...",
})

Tabs.Desk:AddButton({
    Title = "Enchant PC",
    Callback = function()
        local pcName = Options.EnchantPcName.Value or ""
        if pcName ~= "" then
            RemoteEvents.EnchantPC:FireServer(pcName)
        end
    end,
})

-- ============================================================
-- ITEMS
-- ============================================================

Tabs.Items:AddSection("Inventário")

Tabs.Items:AddButton({
    Title = "Vender Inventário Inteiro",
    Callback = function()
        RemoteEvents.sellEntireInventory:FireServer()
    end,
})

Tabs.Items:AddSection("Storage Unit")

Tabs.Items:AddButton({
    Title = "Abrir Storage Unit",
    Callback = function()
        local StorageUnit = LocalPlayer.PlayerGui.MainGui.StorageUnit
        StorageUnit.changePage("MainView")
        StorageUnit.loadView("Main")
        StorageUnit.Visible = true
    end,
})

Tabs.Items:AddButton({
    Title = "Fechar Storage Unit",
    Callback = function()
        LocalPlayer.PlayerGui.MainGui.StorageUnit.Visible = false
    end,
})

-- ============================================================
-- FUN
-- ============================================================

Tabs.Fun:AddSection("Presentes")

Tabs.Fun:AddInput("GiftPlayerName", {
    Title = "Nome do Jogador",
    Placeholder = "Para quem dar presente...",
})

Tabs.Fun:AddButton({
    Title = "Dar Presente Premium",
    Callback = function()
        local playerName = Options.GiftPlayerName.Value or ""
        if playerName ~= "" then
            RemoteEvents.targetGiftCheck:FireServer(playerName, "Premium", "15594907")
        end
    end,
})

Tabs.Fun:AddSection("Blacklist")

Tabs.Fun:AddInput("BlacklistPlayerName", {
    Title = "Nome do Jogador (Blacklist)",
    Placeholder = "Digite o nome...",
})

Tabs.Fun:AddButton({
    Title = "Blacklist Jogador",
    Callback = function()
        local playerName = Options.BlacklistPlayerName.Value or ""
        if playerName ~= "" then
            RemoteEvents.blacklistUser:FireServer(playerName, "bl")
        end
    end,
})

Tabs.Fun:AddButton({
    Title = "Unblacklist Jogador",
    Callback = function()
        local playerName = Options.BlacklistPlayerName.Value or ""
        if playerName ~= "" then
            RemoteEvents.blacklistUser:FireServer(playerName, "ubl")
        end
    end,
})

-- ============================================================
-- SETTINGS
-- ============================================================

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("DanoninHub/CustomPCTycoon")
SaveManager:SetFolder("DanoninHub/CustomPCTycoon/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
SaveManager:LoadAutoloadConfig()

Fluent:Notify({
    Title = "Danonin Hub",
    Content = "Custom PC Tycoon carregado!",
    Duration = 4,
})
