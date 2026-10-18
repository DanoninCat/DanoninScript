-- CAT EMPIRE — Settings/Misc module for Steal A Brainrot
-- Copied from CAT_EMPIRE_INTERFACE/UI/Settings_Misc.lua (Zyon's original),
-- extended ONLY in the profile whitelist so the new game keys persist.
return function(ctx)
    local S, Window, Tabs, Links, Toggles = ctx.S, ctx.Window, ctx.Tabs, ctx.Links, ctx.Toggles
    local LP, Fluent = ctx.Player, ctx.Fluent
    local notify = ctx.Notify or function(message) pcall(function() Fluent:Notify({Title="CAT EMPIRE",Content=tostring(message),Duration=4}) end) end
    local UIS = game:GetService("UserInputService")
    local GuiService = game:GetService("GuiService")
    local TeleportService = game:GetService("TeleportService")
    local VirtualUser = game:GetService("VirtualUser")
    local rootName = ctx.GuiName or "CAT_EMPIRE_INTERFACE_TEMPLATE"
    local ownedRoot, opener
    local closed, stopped = false, false
    local snapshots = {}
    local function rootGui()
        if ownedRoot and ownedRoot.Parent then return ownedRoot end
        local direct=Window and (Window.ScreenGui or Window.Gui)
        if typeof(direct)=="Instance" and direct:IsA("ScreenGui") then
            ownedRoot=direct
            return direct
        end
        local parents = {LP:FindFirstChildOfClass("PlayerGui"), game:GetService("CoreGui")}
        for _,parent in ipairs(parents) do
            local gui = parent and parent:FindFirstChild(rootName, true)
            if gui and gui:IsA("ScreenGui") then ownedRoot=gui;return gui end
        end
        local ok,uiParent=pcall(function()
            return type(gethui)=="function" and gethui() or nil
        end)
        if ok and uiParent then
            local found=uiParent:FindFirstChild(rootName,true)
            if found and found:IsA("ScreenGui") then ownedRoot=found;return found end
        end
        return nil
    end
    local function visible(enabled)
        local gui = rootGui()
        if gui then
            gui.Enabled = enabled
            closed = not enabled
            if opener then opener.Enabled = closed end
        end
    end
    local pg = LP:WaitForChild("PlayerGui")
    local previous = pg:FindFirstChild("CAT_EMPIRE_INTERFACE_OPEN_UI")
    if previous then previous:Destroy() end
    opener=Instance.new("ScreenGui")
    opener.Name="CAT_EMPIRE_INTERFACE_OPEN_UI"
    opener.ResetOnSpawn=false
    opener.DisplayOrder=999
    opener.Enabled=false
    opener.Parent=pg
    local reopen=Instance.new("TextButton")
    reopen.Name="ReopenButton"
    reopen.Size=UDim2.fromOffset(76,32)
    reopen.Position=UDim2.fromOffset(10,55)
    reopen.BackgroundColor3=Color3.fromRGB(45,40,61)
    reopen.TextColor3=Color3.new(1,1,1)
    reopen.Text="OPEN UI"
    reopen.Font=Enum.Font.GothamBold
    reopen.TextSize=11
    reopen.Parent=opener
    local corner=Instance.new("UICorner")
    corner.CornerRadius=UDim.new(0,8)
    corner.Parent=reopen
    Links[#Links+1]=reopen.Activated:Connect(function() visible(true) end)
    Links[#Links+1]=UIS.InputBegan:Connect(function(input)
        if input.KeyCode==Enum.KeyCode.RightControl and closed then visible(true) end
    end)
    local hooked = setmetatable({},{__mode="k"})
    task.spawn(function()
        while S.Running and not stopped do
            local gui=rootGui()
            if gui then
                for _,child in ipairs(gui:GetDescendants()) do
                    if child:IsA("GuiButton") and not hooked[child] then
                        local n=child.Name:lower()
                        if n=="close" or n=="closebutton" then
                            hooked[child]=true
                            Links[#Links+1]=child.Activated:Connect(function()
                                task.defer(function()
                                    if S.Running and not stopped then visible(false) end
                                end)
                            end)
                        end
                    end
                end
            end
            task.wait(1)
        end
    end)
    local function toggle(key,label,callback)
        Toggles[key]=Tabs.Settings:AddToggle("SUP_"..key,{
            Title=label,Default=false,
            Callback=function(v)
                S[key]=v==true
                if callback then callback(v==true) end
            end,
        })
    end
    local boostConnection, boostGeneration = nil, 0
    local parkedAppearances = {}
    local function saveProperty(inst, prop, newValue)
        local ok, previous = pcall(function() return inst[prop] end)
        if not ok or previous == newValue then return end
        local entry = snapshots[inst]
        if not entry then entry = {}; snapshots[inst] = entry end
        if entry[prop] == nil then entry[prop] = previous end
        pcall(function() inst[prop] = newValue end)
    end
    local function restore()
        boostGeneration = boostGeneration + 1
        if boostConnection then boostConnection:Disconnect(); boostConnection = nil end
        for appearance, originalParent in pairs(parkedAppearances) do
            if originalParent and originalParent.Parent then
                pcall(function() appearance.Parent = originalParent end)
            end
            parkedAppearances[appearance] = nil
        end
        for inst, entry in pairs(snapshots) do
            if inst and inst.Parent then
                for prop, previous in pairs(entry) do
                    pcall(function() inst[prop] = previous end)
                end
            end
            snapshots[inst] = nil
        end
    end
    local function simplify(inst)
        if inst:IsA("Texture") or inst:IsA("Decal") then
            saveProperty(inst, "Transparency", 1)
        elseif inst:IsA("MeshPart") then
            saveProperty(inst, "TextureID", "")
        elseif inst:IsA("SpecialMesh") then
            saveProperty(inst, "TextureId", "")
        elseif inst:IsA("SurfaceAppearance") then
            if inst.Parent and not parkedAppearances[inst] then
                parkedAppearances[inst] = inst.Parent
                pcall(function() inst.Parent = nil end)
            end
        end
        if inst:IsA("BasePart") then
            saveProperty(inst, "Material", Enum.Material.SmoothPlastic)
            saveProperty(inst, "MaterialVariant", "")
            saveProperty(inst, "Reflectance", 0)
            saveProperty(inst, "CastShadow", false)
        elseif inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail")
            or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
            saveProperty(inst, "Enabled", false)
        end
    end
    local function boost(on)
        restore()
        if not on then return end
        local generation = boostGeneration
        boostConnection = workspace.DescendantAdded:Connect(function(inst)
            if S.Running and S.BoostFPS and boostGeneration == generation then
                simplify(inst)
            end
        end)
        task.spawn(function()
            local objects = workspace:GetDescendants()
            for i, inst in ipairs(objects) do
                if not S.Running or not S.BoostFPS or boostGeneration ~= generation then return end
                simplify(inst)
                if i % 120 == 0 then task.wait() end
            end
        end)
    end
    toggle("AutoRejoin","Auto Rejoin")
    toggle("AntiAFK","Anti AFK")
    Tabs.Settings:AddDropdown("SUP_Theme",{
        Title="Themes",Values=Fluent.Themes,Default="Dark",
        Callback=function(theme) pcall(function() Fluent:SetTheme(theme) end) end,
    })
    toggle("AutoCloseUI","Auto Close UI",function(on)
        if on then task.delay(0.8,function()
            if S.Running and S.AutoCloseUI then visible(false) end
        end) end
    end)
    toggle("AutoLoadAfterRejoin","Auto Load After Rejoin")
    toggle("AutoLoadProfiles","Auto Load Profiles")
    toggle("BoostFPS","Boost FPS",boost)
    Tabs.Settings:AddButton({Title="Unload Script",Callback=function() ctx.Cleanup() end})
    Links[#Links+1]=LP.Idled:Connect(function()
        if S.AntiAFK then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.zero)
            end)
        end
    end)
    local reconnecting=false
    Links[#Links+1]=GuiService.ErrorMessageChanged:Connect(function(text)
        local message=tostring(text):lower()
        if S.AutoRejoin and not reconnecting
            and (message:find("disconnect") or message:find("lost connection")
            or message:find("error code: 277")) then
            reconnecting=true
            task.delay(2,function()
                if not S.Running then return end
                pcall(function()
                    local queue=queue_on_teleport or (syn and syn.queue_on_teleport)
                    if S.AutoLoadAfterRejoin and type(queue)=="function" then
                        queue([[loadstring(game:HttpGet("https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Loader/Loader.lua",true))()]])
                    end
                    TeleportService:Teleport(game.PlaceId,LP)
                end)
                reconnecting=false
            end)
        end
    end)
    local Players = game:GetService("Players")
    local MarketplaceService = game:GetService("MarketplaceService")
    local function gameIcon()
        local fallback = "rbxthumb://type=GameIcon&id="..tostring(game.GameId).."&w=420&h=420"
        local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, game.PlaceId)
        if ok and type(info)=="table" then
            local assetId=tonumber(info.IconImageAssetId)
            if assetId and assetId>0 then return "rbxassetid://"..tostring(assetId) end
        end
        return fallback
    end
    local accountSection=Tabs.Misc:AddSection("Account", "solar/user-bold")
    local userCard=accountSection:AddParagraph({Title="Player",Content="Loading account"})
    task.spawn(function()
        local content,ready
        for attempt=1,12 do
            if stopped or not S.Running then return end
            local ok,img,isReady=pcall(function()
                return Players:GetUserThumbnailAsync(LP.UserId,
                    Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size420x420)
            end)
            if ok and isReady and type(img)=="string" and img~="" then
                content,ready=img,true
                break
            end
            task.wait(1)
        end
        if stopped or not S.Running then return end
        if not ready then
            pcall(function() userCard:SetDesc("Avatar still unavailable; player data shown below") end)
            return
        end
        pcall(function()
            accountSection:AddSocial({
                Username=LP.Name,DisplayName=LP.DisplayName,Platform="Roblox",Avatar=content,
            })
        end)
    end)
    local gameSection=Tabs.Misc:AddSection("Game", "solar/gamepad-bold")
    gameSection:AddImage({Image=gameIcon(),AspectRatio="4:1",Radius=10})
    local gameCard=gameSection:AddParagraph({Title="Game",Content="Loading game"})
    local community=Tabs.Misc:AddSection("Community","solar/chat-round-bold")
    community:AddDiscord({InviteCode="yykVnTjd2Y"})
    local gameTitle="Retrieving official game name..."
    pcall(function()
        local info=MarketplaceService:GetProductInfo(game.PlaceId)
        if info and type(info.Name)=="string" and info.Name~="" then gameTitle=info.Name end
    end)
    local function refreshMisc()
        pcall(function()
            userCard:SetDesc("@"..LP.Name.." | "..LP.DisplayName.." | ID: "..LP.UserId)
            gameCard:SetDesc(gameTitle.." | Place ID: "..game.PlaceId.." | Universe ID: "..game.GameId)
        end)
    end
    task.spawn(function()
        while S.Running and not stopped do
            pcall(refreshMisc)
            task.wait(120)
        end
    end)


    local HttpService=game:GetService("HttpService")
    local profiles={"Default"}
    local selected="Default"
    local draftName=""
    -- keys added by this game module (must persist in profiles)
    local TABLE_KEYS = ctx.ExtraProfileTables or {"SelectedSellRarities"}
    local STRING_KEYS = ctx.ExtraProfileStrings or {"HalloweenTravelTarget","LuckyBlockBundle","_potionId","_volcanoBundle"}
    local function readCatalog()
        if type(readfile)~="function" then return nil end
        local ok, raw=pcall(readfile,S.ConfigFile)
        if not ok then return nil end
        local valid,catalog=pcall(HttpService.JSONDecode,HttpService,raw)
        return valid and type(catalog)=="table" and catalog or nil
    end
    local catalog=readCatalog() or {Profiles={},Names={"Default"},Selected="Default"}
    if type(catalog.Names)=="table" then profiles=catalog.Names end
    selected=tostring(catalog.Selected or "Default")
    local profileList=Tabs.Settings:AddDropdown("INTERFACE_Profiles",{
        Title="Profiles",Values=profiles,Default=selected,
        Callback=function(name) selected=tostring(name or "Default") end,
    })
    Tabs.Settings:AddInput("INTERFACE_ProfileName",{
        Title="Profile Name",Default="",Placeholder="New profile name",
        Callback=function(name) draftName=tostring(name or "") end,
    })
    Tabs.Settings:AddButton({Title="Create Profiles",Callback=function()
        local name=draftName:match("^%s*(.-)%s*$")
        if name=="" or #name>40 then notify("Enter a valid profile name");return end
        for _,v in ipairs(profiles) do
            if v==name then selected=name;pcall(function() profileList:SetValue(name) end);return end
        end
        profiles[#profiles+1]=name
        selected=name
        pcall(function() profileList:SetValues(profiles);profileList:SetValue(name) end)
        notify("Profile created: "..name)
    end})
    local function saveProfile()
        if type(writefile)~="function" then notify("Executor has no writefile");return end
        catalog.Profiles=catalog.Profiles or {}
        local data={}
        for key,v in pairs(S) do
            if type(v)=="boolean" or type(v)=="number" or type(v)=="string" then
                if key~="Running" and key~="LastError" and key~="LastAction" and key~="Step" and key~="HellStep" then
                    data[key]=v
                end
            elseif type(v)=="table" then
                for _,allowed in ipairs(TABLE_KEYS) do
                    if key==allowed then data[key]=v end
                end
            end
        end
        catalog.Profiles[selected]=data
        catalog.Names=profiles
        catalog.Selected=selected
        catalog.AutoLoad=S.AutoLoadProfiles==true
        local ok,err=pcall(writefile,S.ConfigFile,HttpService:JSONEncode(catalog))
        notify(ok and "Profile saved" or tostring(err))
    end
    local function loadProfile()
        catalog=readCatalog() or catalog
        local data=type(catalog.Profiles)=="table" and catalog.Profiles[selected]
        if type(data)~="table" then return false end
        for key,v in pairs(data) do
            if Toggles[key] and type(v)=="boolean" then
                pcall(function() Toggles[key]:SetValue(v) end)
            elseif type(v)=="table" then
                for _,allowed in ipairs(TABLE_KEYS) do
                    if key==allowed then S[key]=v end
                end
            elseif type(v)=="string" or type(v)=="number" then
                if key=="TravelMode" or key=="EggPriority" then
                    S[key]=v
                else
                    for _,allowed in ipairs(STRING_KEYS) do
                        if key==allowed then S[key]=v end
                    end
                end
            end
        end
        notify("Profile loaded: "..selected)
        return true
    end
    Tabs.Settings:AddButton({Title="Save Profiles",Callback=saveProfile})
    Tabs.Settings:AddButton({Title="Load Selected Profile",Callback=loadProfile})
    task.delay(3,function()
        if S.Running and (S.AutoLoadProfiles or catalog.AutoLoad==true) then loadProfile() end
    end)
    return function()
        stopped=true
        restore()
        if opener then pcall(function() opener:Destroy() end) end
    end
end
