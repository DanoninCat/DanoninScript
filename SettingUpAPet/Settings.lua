return function(ctx)
    local S, Window, Tabs, Links, Toggles = ctx.S, ctx.Window, ctx.Tabs, ctx.Links, ctx.Toggles
    local LP, Fluent = ctx.LP, ctx.Fluent
    local UIS = game:GetService("UserInputService")
    local GuiService = game:GetService("GuiService")
    local TeleportService = game:GetService("TeleportService")
    local VirtualUser = game:GetService("VirtualUser")
    local rootName = "CAT_EMPIRE_SETTING_UP_A_PET_124216119978534"
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
    local previous = pg:FindFirstChild("CAT_EMPIRE_OPEN_UI")
    if previous then previous:Destroy() end
    opener=Instance.new("ScreenGui")
    opener.Name="CAT_EMPIRE_OPEN_UI"
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
    local function restore()
        for instance, entry in pairs(snapshots) do
            pcall(function() instance[entry[1]]=entry[2] end)
            snapshots[instance]=nil
        end
    end
    local function boost(on)
        restore()
        if not on then return end
        task.spawn(function()
            local objects=workspace:GetDescendants()
            local n=0
            for _,inst in ipairs(objects) do
                if not S.Running or not S.BoostFPS then return end
                local prop,newVal
                if inst:IsA("ParticleEmitter") or inst:IsA("Beam")
                    or inst:IsA("Trail") or inst:IsA("Fire")
                    or inst:IsA("Smoke") then
                    prop,newVal="Enabled",false
                elseif S.RemoveTextures and (inst:IsA("Texture") or inst:IsA("Decal")) then
                    prop,newVal="Transparency",1
                end
                if prop then
                    local ok,previous=pcall(function() return inst[prop] end)
                    if ok then
                        snapshots[inst]={prop,previous}
                        pcall(function() inst[prop]=newVal end)
                    end
                end
                n=n+1
                if n%120==0 then task.wait() end
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
    toggle("BoostFPS","Boost FPS",boost)
    toggle("RemoveTextures","Remove Textures (Boost FPS)",function()
        if S.BoostFPS then boost(true) end
    end)
    Tabs.Settings:AddButton({Title="Close UI",Callback=function() visible(false) end})
    Tabs.Settings:AddButton({Title="Unload Script",Callback=function() ctx.cleanup() end})
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
    local Players=game:GetService("Players")
    local HttpService=game:GetService("HttpService")
    local function button(tab,title,fn)
        tab:AddButton({Title=title,Callback=function()
            task.spawn(function() pcall(fn) end)
        end})
    end
local userCard=Tabs.Misc:AddParagraph({Title="Player",Content="Loading"})
local gameCard=Tabs.Misc:AddParagraph({Title="Game",Content="Loading"})
local discordCard=Tabs.Misc:AddParagraph({Title="Discord",Content="Invite not configured"})
local discordInvite=""
local function attachImage(card,asset)
    if type(card)~="table" then return end
    local parent=card.Frame or card.Root or card.Container
    if typeof(parent)~="Instance" or not parent:IsA("GuiObject") then return end
    local image=parent:FindFirstChild("CAT_EMPIRE_PHOTO")
    if not image then
        image=Instance.new("ImageLabel")
        image.Name="CAT_EMPIRE_PHOTO"
        image.AnchorPoint=Vector2.new(1,.5)
        image.Position=UDim2.new(1,-8,.5,0)
        image.Size=UDim2.fromOffset(46,46)
        image.BackgroundTransparency=1
        image.ZIndex=parent.ZIndex+1
        image.Parent=parent
    end
    image.Image=asset
end
local function refreshMisc()
    local avatar=""
    pcall(function()
        avatar=Players:GetUserThumbnailAsync(LP.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size150x150)
    end)
    pcall(function()
        userCard:SetDesc("@"..LP.Name.."  |  "..LP.DisplayName.."  |  ID: "..LP.UserId)
        gameCard:SetDesc(game.Name.."  |  Place ID: "..game.PlaceId.."  |  Game ID: "..game.GameId)
    end)
    attachImage(userCard,avatar)
    attachImage(gameCard,"rbxthumb://type=GameIcon&id="..game.GameId.."&w=150&h=150")
end
Tabs.Misc:AddInput("SUP_DiscordInvite",{
    Title="Discord Invite Code",Default="",Placeholder="Invite code",
    Callback=function(v) discordInvite=tostring(v or ""):match("([%w_%-]+)$") or "" end,
})
button(Tabs.Misc,"Refresh Discord",function()
    if discordInvite=="" then
        discordCard:SetDesc("Enter your Discord invitation code")
        return
    end
    local ok,response=pcall(function()
        return HttpService:JSONDecode(game:HttpGet(
            "https://discord.com/api/v10/invites/"..discordInvite.."?with_counts=true",true))
    end)
    if not ok or type(response)~="table" or type(response.guild)~="table" then
        discordCard:SetDesc("Live Discord data unavailable")
        return
    end
    local guild=response.guild
    discordCard:SetDesc(tostring(guild.name or "Discord")..
        " | Members: "..tostring(response.approximate_member_count or "?")..
        " | Online: "..tostring(response.approximate_presence_count or "?"))
    if guild.id and guild.icon then
        attachImage(discordCard,"https://cdn.discordapp.com/icons/"..
            tostring(guild.id).."/"..tostring(guild.icon)..".png")
    end
end)
task.spawn(function()
    while S.Running do pcall(refreshMisc);task.wait(120) end
end)


    return function()
        stopped=true
        restore()
        if opener then pcall(function() opener:Destroy() end) end
    end
end