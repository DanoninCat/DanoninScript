-- ============================================================
-- ADICIONE ISSO NO SEU SCRIPT, APÓS A CRIAÇÃO DAS TABS
-- ============================================================

local Tabs = Window:AddTab({ Title = "Exploits", Icon = "crosshair" })

-- Referência aos Remotes do jogo
local rf = RS:WaitForChild("RemotesFolder", 5)

-- Função segura pra chamar remotes
local function fireRemote(name, ...)
    local remote = rf and rf:FindFirstChild(name)
    if remote then
        pcall(function() remote:FireServer(...) end)
    end
end

-- ============================================================
-- SECTION: REWARDS
-- ============================================================
Tabs.Exploits:AddSection("Rewards / Quests")

Tabs.Exploits:AddButton({
    Title = "Claim All Rewards x50",
    Callback = function()
        for i = 1, 50 do
            task.spawn(function()
                fireRemote("ClaimDailyReward")
                fireRemote("ClaimTimeReward")
                fireRemote("ClaimAllRewards")
                fireRemote("AutoClaimRewards")
            end)
            task.wait(0.01)
        end
        Fluent:Notify({ Title = "Rewards", Content = "50x enviado!", Duration = 2 })
    end,
})

Tabs.Exploits:AddButton({
    Title = "Complete All Quests x50",
    Callback = function()
        for i = 1, 50 do
            task.spawn(function()
                fireRemote("CompleteAllQuests")
                fireRemote("CompleteIndexQuests")
                fireRemote("ClaimAllQuestObjectives")
                fireRemote("ClaimQuestObjective")
                fireRemote("ClaimAchievement")
                fireRemote("ClaimAllAchievements")
                fireRemote("AutoAchievement")
            end)
            task.wait(0.01)
        end
        Fluent:Notify({ Title = "Quests", Content = "50x enviado!", Duration = 2 })
    end,
})

-- ============================================================
-- SECTION: UPGRADES
-- ============================================================
Tabs.Exploits:AddSection("Upgrades")

Tabs.Exploits:AddButton({
    Title = "Spam Upgrades x50",
    Callback = function()
        for i = 1, 50 do
            task.spawn(function()
                fireRemote("AutoUpgradeStats")
                fireRemote("UpgradeStat")
                fireRemote("UpgradeLevels")
                fireRemote("UpgradeProgression")
                fireRemote("ProgressionAuto")
                fireRemote("AutoAvatarLevel")
                fireRemote("MaxAvatarLevel")
                fireRemote("RankUp")
            end)
            task.wait(0.01)
        end
        Fluent:Notify({ Title = "Upgrades", Content = "50x enviado!", Duration = 2 })
    end,
})

-- ============================================================
-- SECTION: PETS / SWORDS / GACHA
-- ============================================================
Tabs.Exploits:AddSection("Pets / Swords / Gacha")

Tabs.Exploits:AddButton({
    Title = "Fuse Swords Spam x30",
    Callback = function()
        for i = 1, 30 do
            task.spawn(function()
                fireRemote("FuseSwords")
            end)
            task.wait(0.05)
        end
        Fluent:Notify({ Title = "Fuse", Content = "30x enviado!", Duration = 2 })
    end,
})

Tabs.Exploits:AddButton({
    Title = "Auto Roll Gacha x50",
    Callback = function()
        for i = 1, 50 do
            task.spawn(function()
                fireRemote("AutoRollGacha")
                fireRemote("AnimationGacha")
            end)
            task.wait(0.05)
        end
        Fluent:Notify({ Title = "Gacha", Content = "50x enviado!", Duration = 2 })
    end,
})

Tabs.Exploits:AddButton({
    Title = "Equip Best All",
    Callback = function()
        fireRemote("EquipBestAll")
        fireRemote("EquipeBestGachas")
        fireRemote("EquipBestAura")
        Fluent:Notify({ Title = "Equip", Content = "Melhores equipados!", Duration = 2 })
    end,
})

-- ============================================================
-- SECTION: PRODUTOS
-- ============================================================
Tabs.Exploits:AddSection("Produtos / Códigos")

Tabs.Exploits:AddButton({
    Title = "Buy Free Products x20",
    Callback = function()
        for i = 1, 20 do
            task.spawn(function()
                fireRemote("BuyFreeProduct")
                fireRemote("BuyProduct")
            end)
            task.wait(0.1)
        end
        Fluent:Notify({ Title = "Shop", Content = "20x enviado!", Duration = 2 })
    end,
})

Tabs.Exploits:AddButton({
    Title = "Claim Code (vazio)",
    Callback = function()
        for i = 1, 10 do
            task.spawn(function()
                fireRemote("ClaimCode", "")
            end)
            task.wait(0.05)
        end
        Fluent:Notify({ Title = "Code", Content = "10x enviado!", Duration = 2 })
    end,
})

-- ============================================================
-- SECTION: POTIONS
-- ============================================================
Tabs.Exploits:AddSection("Potions")

Tabs.Exploits:AddButton({
    Title = "Use All Potions x10",
    Callback = function()
        for i = 1, 10 do
            task.spawn(function()
                fireRemote("UsePotions")
                fireRemote("TogglePotion")
            end)
            task.wait(0.05)
        end
        Fluent:Notify({ Title = "Potions", Content = "10x enviado!", Duration = 2 })
    end,
})

-- ============================================================
-- SECTION: MISC
-- ============================================================
Tabs.Exploits:AddSection("Misc")

Tabs.Exploits:AddButton({
    Title = "Reset Stats",
    Callback = function()
        fireRemote("ResetStats")
        Fluent:Notify({ Title = "Reset", Content = "Stats resetados!", Duration = 2 })
    end,
})

Tabs.Exploits:AddButton({
    Title = "Unlock World",
    Callback = function()
        fireRemote("UnlockWorld")
        Fluent:Notify({ Title = "World", Content = "Mundo desbloqueado!", Duration = 2 })
    end,
})

-- ============================================================
-- SECTION: NUKE ALL (TUDO DE UMA VEZ)
-- ============================================================
Tabs.Exploits:AddSection("☠️ NUKE ALL")

Tabs.Exploits:AddButton({
    Title = "EXECUTAR TUDO (100x)",
    Callback = function()
        Fluent:Notify({ Title = "NUKE", Content = "Executando todos os exploits...", Duration = 3 })
        for i = 1, 100 do
            task.spawn(function()
                -- Rewards
                fireRemote("ClaimDailyReward")
                fireRemote("ClaimTimeReward")
                fireRemote("ClaimAllRewards")
                fireRemote("AutoClaimRewards")
                -- Quests
                fireRemote("CompleteAllQuests")
                fireRemote("CompleteIndexQuests")
                fireRemote("ClaimAllQuestObjectives")
                fireRemote("ClaimQuestObjective")
                fireRemote("ClaimAchievement")
                fireRemote("ClaimAllAchievements")
                -- Upgrades
                fireRemote("AutoUpgradeStats")
                fireRemote("UpgradeStat")
                fireRemote("AutoAvatarLevel")
                fireRemote("MaxAvatarLevel")
                fireRemote("UpgradeProgression")
                fireRemote("ProgressionAuto")
                -- Gacha/Fuse
                fireRemote("AutoRollGacha")
                fireRemote("AnimationGacha")
                fireRemote("FuseSwords")
                -- Products
                fireRemote("BuyFreeProduct")
                fireRemote("BuyProduct")
                fireRemote("ClaimCode")
                -- Potions
                fireRemote("UsePotions")
            end)
            task.wait(0.01)
        end
        Fluent:Notify({ Title = "NUKE", Content = "✅ TUDO executado!", Duration = 4 })
    end,
})
