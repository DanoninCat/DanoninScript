-- CAT EMPIRE | FPS 104856666707760 | Luau client
-- Static references: Client.Combat.Targets, Client.State.Combat,
-- Shared.Weapons.WeaponInfo, Shared.Net, Camera.RenderPipeline.
-- Silence/replication of shot directions are SERVER-DEPENDENT, not guaranteed.
local PLACE = 104856666707760
if game.PlaceId ~= PLACE and game.GameId ~= PLACE then return end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local LP = Players.LocalPlayer
local Env = (getgenv and getgenv()) or _G
if type(Env.__CE_FPS104_CLEANUP) == "function" then pcall(Env.__CE_FPS104_CLEANUP) end
local payload = Env.__CE_F_91A7
assert(type(payload) == "string" and #payload > 0, "Run CAT EMPIRE Loader/Loader.lua")
local Fluent = assert(loadstring(payload))()
local Links, Toggles, Drawings = {}, {}, {}
local S = {
    Running=true, Aimbot=false, AimbotSafe=false, AimAssist=false, SilentAim=false,
    AimPart="Head", AimActivation="RMB", AimFOV=190, AimSmooth=0.24, SafeSmooth=0.09,
    AssistStrength=0.11, MaxDistance=1800, VisibleOnly=true, StickyTarget=true,
    WeaponProfiles=true, ProfilesByWeapon={}, CurrentWeapon="",
    ESP=true, ESPBox=true, ESPName=true, ESPDistance=true, ESPHealth=true,
    ESPTracers=false, ESPSkeleton=false, ESPShowTeam=false, Chams=false,
    ShowFOV=true, SpinBot=false, SpinSpeed=250,
    SkinWeapon="", SkinId="", PreviewSpin=true,
    AutoRejoin=false, AntiAFK=false, AutoCloseUI=false,
    AutoLoadAfterRejoin=false, AutoLoadProfiles=false, BoostFPS=false,
    ConfigFile="CAT_EMPIRE_FPS104_104856666707760.json",
    LastAction="Starting", LastError="", SilentHookStatus="Not installed",
}
local visuals = {}
local oldAutoRotate, autoRotateHum
local native = {}
local window, viewport, previewCam, worldModel, previewModel
local previewAngle = 0
local lastAim = nil
local lastDraw, lastVisuals, lastWeapon = 0,0,0
local originalSend, hookedSend
local function status(s) S.LastAction=tostring(s) end
local function warnOnce(where, message)
    local m=tostring(where)..": "..tostring(message)
    if S.LastError ~= m then warn("[CAT EMPIRE FPS104] "..m) end
    S.LastError=m
end
local function notify(t)
    pcall(function() Fluent:Notify({Title="CAT EMPIRE",Content=tostring(t),Duration=4}) end)
end
local function safeRequire(root, ...)
    local cursor=root
    for _, key in ipairs({...}) do
        cursor=cursor and cursor:FindFirstChild(key)
    end
    if not (cursor and cursor:IsA("ModuleScript")) then return nil end
    local ok, value=pcall(require,cursor)
    if ok then return value end
    warnOnce("require "..cursor:GetFullName(),value)
    return nil
end
local function initializeNative()
    local client=RS:FindFirstChild("Client")
    local shared=RS:FindFirstChild("Shared")
    native.Targets=safeRequire(client,"Combat","Targets")
    native.Friendly=safeRequire(client,"Combat","isFriendly")
    native.StateCombat=safeRequire(client,"State","Combat")
    native.WeaponInfo=safeRequire(shared,"Weapons","WeaponInfo")
    native.Net=safeRequire(shared,"Net")
    native.RenderPipeline=safeRequire(client,"Camera","RenderPipeline")
end
initializeNative()
local function atomValue(a)
    if type(a)~="function" then return nil end
    local ok,result=pcall(a)
    return ok and result or nil
end
local function rootOf(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
        or model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
end
local function myRoot()
    return rootOf(LP.Character)
end
local function living(model)
    if not (model and model.Parent and model:IsA("Model")) then return false end
    local hum=model:FindFirstChildOfClass("Humanoid")
    return (not hum or hum.Health>0) and rootOf(model)~=nil
end
local function isFriendly(model)
    if model == LP.Character then return true end
    local player=Players:GetPlayerFromCharacter(model)
    if player == LP then return true end
    if native.Friendly then
        local ok, result=pcall(native.Friendly,player,model)
        if ok then return result==true end
    end
    if player then
        local a,b=LP:GetAttribute("Party"),player:GetAttribute("Party")
        if a~=nil and b~=nil and a==b then return true end
        if LP.Team~=nil and player.Team==LP.Team and not LP.Neutral and not player.Neutral then return true end
    end
    return false
end
local function targetModels()
    local unique,output={},{}
    local set=native.Targets and atomValue(native.Targets.set)
    if type(set)=="table" then
        for model,active in pairs(set) do
            if active and typeof(model)=="Instance" and model:IsA("Model") and living(model)
                and model~=LP.Character and not unique[model] then
                unique[model]=true; output[#output+1]=model
            end
        end
    end
    if #output==0 then
        for _,player in ipairs(Players:GetPlayers()) do
            local model=player.Character
            if player~=LP and living(model) and not unique[model] then
                unique[model]=true; output[#output+1]=model
            end
        end
    end
    return output
end
local function aimPart(model)
    if not model then return nil end
    local part=model:FindFirstChild(S.AimPart,true)
    if part and part:IsA("BasePart") then return part end
    for _,key in ipairs({"Head","UpperTorso","Torso","HumanoidRootPart"}) do
        part=model:FindFirstChild(key,true)
        if part and part:IsA("BasePart") then return part end
    end
    return rootOf(model)
end
local function visible(model, part)
    if not S.VisibleOnly then return true end
    local cam=workspace.CurrentCamera
    if not (cam and part) then return false end
    local direction=part.Position-cam.CFrame.Position
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.IgnoreWater=true
    params.FilterDescendantsInstances=LP.Character and {LP.Character} or {}
    local ok, hit=pcall(workspace.Raycast,workspace,cam.CFrame.Position,direction,params)
    if not ok then return false end
    return hit==nil or hit.Instance:IsDescendantOf(model)
end
local function maxFOV()
    local info=native.WeaponInfo
    local entry=info and info.All and info.All[S.CurrentWeapon]
    local preset=S.WeaponProfiles and S.ProfilesByWeapon[S.CurrentWeapon]
    if not preset and entry and S.WeaponProfiles then
        preset=S.ProfilesByWeapon["Class:"..tostring(entry.Class)]
    end
    return (type(preset)=="table" and tonumber(preset.FOV)) or S.AimFOV
end
local function targetFor(fov)
    local cam=workspace.CurrentCamera
    if not cam then return nil end
    local center=cam.ViewportSize/2
    local own=myRoot()
    local best,score=nil,fov or maxFOV()
    for _,model in ipairs(targetModels()) do
        if not isFriendly(model) then
            local part=aimPart(model)
            if part then
                local distance=own and (part.Position-own.Position).Magnitude or 0
                if distance<=S.MaxDistance then
                    local screen,onScreen=cam:WorldToViewportPoint(part.Position)
                    if onScreen and screen.Z>0 then
                        local d=(Vector2.new(screen.X,screen.Y)-center).Magnitude
                        if d<score and visible(model,part) then
                            best={model=model,part=part,position=part.Position,distance=distance}
                            score=d
                        end
                    end
                end
            end
        end
    end
    return best
end
local function aimHeld()
    if UIS:GetFocusedTextBox() or not myRoot() then return false end
    if S.AimActivation=="Always" then return true end
    if S.AimActivation=="LMB" then
        return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    end
    return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
end
local function currentWeapon()
    local info=native.StateCombat and atomValue(native.StateCombat.equippedWeapon)
    return info and info.Id or ""
end
local function smoothFactor(dt, strength)
    return 1-math.exp(-math.max(0.001,strength)*60*math.max(dt,0.001))
end
local function updateAim(dt)
    if not (S.Aimbot or S.AimbotSafe or S.AimAssist) or not aimHeld() then
        lastAim=nil; return
    end
    local cam=workspace.CurrentCamera
    if not cam then return end
    local fov=maxFOV()
    local t=targetFor(fov)
    if S.StickyTarget and lastAim and lastAim.model and living(lastAim.model)
        and not isFriendly(lastAim.model) then
        local p=aimPart(lastAim.model)
        if p then
            local view,onScreen=cam:WorldToViewportPoint(p.Position)
            local d=(Vector2.new(view.X,view.Y)-cam.ViewportSize/2).Magnitude
            if onScreen and d < fov*1.15 and visible(lastAim.model,p) then
                t={model=lastAim.model,part=p,position=p.Position}
            end
        end
    end
    lastAim=t
    if not t then return end
    local direction=t.position-cam.CFrame.Position
    if direction.Magnitude<0.1 then return end
    local desired=CFrame.lookAt(cam.CFrame.Position,t.position)
    local strength= S.Aimbot and S.AimSmooth
        or S.AimbotSafe and S.SafeSmooth or S.AssistStrength
    local alpha=smoothFactor(dt,strength)
    -- Single camera writer; the game's AimAssistApply stage is Camera+4.
    cam.CFrame=cam.CFrame:Lerp(desired,alpha)
end

local function installSilent()
    if hookedSend then return true end
    if type(hookfunction)~="function" then
        S.SilentHookStatus="Executor missing hookfunction"; return false
    end
    local packets=native.Net and native.Net.packets
    local shot=packets and packets.lYnrhNgZ3YIpN0E4
    if not (shot and type(shot.send)=="function") then
        S.SilentHookStatus="RayNet shot packet unavailable"; return false
    end
    local old
    local ok,err=pcall(function()
        old=hookfunction(shot.send,function(data,...)
            if S.Running and S.SilentAim and type(data)=="table" then
                local rays=data.I9ZhIXwGzqsBucMd
                local t=targetFor(maxFOV())
                local config=native.StateCombat and atomValue(native.StateCombat.equippedConfig)
                if t and type(rays)=="table" and not (config and config.Melee) then
                    -- Only change ray direction. Keep source, slot and shot metadata.
                    local modified=table.clone(data)
                    modified.I9ZhIXwGzqsBucMd=table.create(#rays)
                    for i,ray in ipairs(rays) do
                        if typeof(ray)=="Ray" and (t.position-ray.Origin).Magnitude>0.1 then
                            modified.I9ZhIXwGzqsBucMd[i]=Ray.new(ray.Origin,t.position-ray.Origin)
                        else
                            modified.I9ZhIXwGzqsBucMd[i]=ray
                        end
                    end
                    data=modified
                end
            end
            return old(data,...)
        end)
    end)
    if not ok then
        S.SilentHookStatus="Hook rejected: "..tostring(err)
        warnOnce("Silent Aim",err)
        return false
    end
    originalSend=old; hookedSend=true
    S.SilentHookStatus="Shot hook installed; server acceptance unverified"
    return true
end

local drawingOK=type(Drawing)=="table" and type(Drawing.new)=="function"
local function draw(kind)
    if not drawingOK then return nil end
    local ok,obj=pcall(Drawing.new,kind)
    if ok then
        Drawings[#Drawings+1]=obj
        obj.Visible=false
        return obj
    end
end
local fovCircle=draw("Circle")
if fovCircle then
    fovCircle.Thickness=1.4; fovCircle.NumSides=72
    fovCircle.Filled=false; fovCircle.Color=Color3.fromRGB(173,108,255)
end
local folder=Instance.new("Folder")
folder.Name="__CE_FPS104_Highlights"
folder.Parent=workspace
local function record(model)
    local r=visuals[model]
    if r then return r end
    r={draws={},highlights={}}
    for _,key in ipairs({"box","name","distance","health","tracer"}) do
        local kind=(key=="box" and "Square") or (key=="tracer" and "Line") or "Text"
        local obj=draw(kind)
        if obj then
            r.draws[key]=obj
            obj.Color=Color3.fromRGB(226,160,255)
            if key=="box" then obj.Filled=false; obj.Thickness=1.5 end
            if key=="tracer" then obj.Thickness=1.2 end
            if kind=="Text" then obj.Size=13;obj.Center=true;obj.Outline=true end
        end
    end
    for i=1,10 do
        local obj=draw("Line")
        if obj then r.draws["bone"..i]=obj;obj.Thickness=1.4;obj.Color=Color3.fromRGB(240,192,255) end
    end
    visuals[model]=r
    return r
end
local function cleanRecord(r)
    for _,obj in pairs(r.draws) do pcall(function() obj.Visible=false;obj:Remove() end) end
    for _,obj in pairs(r.highlights) do pcall(function() obj:Destroy() end) end
end
local function hideRecord(r)
    for _,obj in pairs(r.draws) do pcall(function() obj.Visible=false end) end
end
local function setHighlight(r,key,adornee)
    local h=r.highlights[key]
    if not (adornee and adornee.Parent) then
        if h then h:Destroy();r.highlights[key]=nil end
        return
    end
    if not h then
        h=Instance.new("Highlight")
        h.Name="CE_Chams"
        h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
        h.FillColor=Color3.fromRGB(144,78,255)
        h.OutlineColor=Color3.fromRGB(255,215,255)
        h.FillTransparency=0.52
        h.OutlineTransparency=0
        h.Parent=folder
        r.highlights[key]=h
    end
    h.Adornee=adornee
end
local function weaponModel(model)
    for _,part in ipairs(model:GetChildren()) do
        if part:IsA("Tool") then return part end
        if part:IsA("Model") and (part.Name:lower():find("weapon") or part.Name:lower():find("gun")) then
            return part
        end
    end
    return nil
end
local bonePairs={
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},
}
local function updateESP()
    local cam=workspace.CurrentCamera
    if not cam then return end
    local models=targetModels()
    local inFrame={}
    local own=myRoot()
    for _,model in ipairs(models) do
        inFrame[model]=true
        local r=record(model)
        local friendly=isFriendly(model)
        local root=rootOf(model)
        local canShow=(S.ESP or S.Chams) and (S.ESPShowTeam or not friendly) and root
        if not canShow then
            hideRecord(r);setHighlight(r,"char",nil);setHighlight(r,"weapon",nil)
        else
            if S.Chams then
                setHighlight(r,"char",model)
                setHighlight(r,"weapon",weaponModel(model))
            else
                setHighlight(r,"char",nil);setHighlight(r,"weapon",nil)
            end
            hideRecord(r)
            if S.ESP and drawingOK then
                local dist=own and (root.Position-own.Position).Magnitude or 0
                if dist<=S.MaxDistance then
                    local boundcf,bounds=model:GetBoundingBox()
                    local top=cam:WorldToViewportPoint(boundcf.Position+Vector3.new(0,bounds.Y/2,0))
                    local bottom=cam:WorldToViewportPoint(boundcf.Position-Vector3.new(0,bounds.Y/2,0))
                    if top.Z>0 and bottom.Z>0 then
                        local height=math.abs(bottom.Y-top.Y)
                        local width=height*math.clamp(bounds.X/math.max(bounds.Y,0.01),0.32,0.85)
                        local mid=(top.X+bottom.X)/2
                        local x=mid-width/2
                        local y=math.min(top.Y,bottom.Y)
                        local function update(key,enabled,action)
                            local obj=r.draws[key]
                            if obj and enabled then action(obj);obj.Visible=true end
                        end
                        update("box",S.ESPBox,function(o)
                            o.Position=Vector2.new(x,y);o.Size=Vector2.new(width,height)
                        end)
                        update("name",S.ESPName,function(o)
                            local player=Players:GetPlayerFromCharacter(model)
                            o.Text=player and player.DisplayName or model.Name
                            o.Position=Vector2.new(mid,y-16)
                        end)
                        update("distance",S.ESPDistance,function(o)
                            o.Text=tostring(math.floor(dist)).." studs"
                            o.Position=Vector2.new(mid,y+height+3)
                        end)
                        update("health",S.ESPHealth,function(o)
                            local humanoid=model:FindFirstChildOfClass("Humanoid")
                            if humanoid then
                                o.Text=math.ceil(humanoid.Health).."/"..math.ceil(humanoid.MaxHealth).." HP"
                                o.Position=Vector2.new(mid,y+height+19)
                            end
                        end)
                        update("tracer",S.ESPTracers,function(o)
                            o.From=Vector2.new(cam.ViewportSize.X/2,cam.ViewportSize.Y)
                            o.To=Vector2.new(mid,y+height)
                        end)
                        if S.ESPSkeleton then
                            for i,pair in ipairs(bonePairs) do
                                local a,b=model:FindFirstChild(pair[1]),model:FindFirstChild(pair[2])
                                local o=r.draws["bone"..i]
                                if o and a and b then
                                    local pa,va=cam:WorldToViewportPoint(a.Position)
                                    local pb,vb=cam:WorldToViewportPoint(b.Position)
                                    if va and vb then
                                        o.From=Vector2.new(pa.X,pa.Y)
                                        o.To=Vector2.new(pb.X,pb.Y)
                                        o.Visible=true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    for model,r in pairs(visuals) do
        if not inFrame[model] or not model.Parent then
            cleanRecord(r); visuals[model]=nil
        end
    end
end

local function updateSpin(dt)
    local root,hum=myRoot(),LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if not S.SpinBot or not root or not hum then
        if autoRotateHum and autoRotateHum.Parent then
            autoRotateHum.AutoRotate=oldAutoRotate~=false
        end
        autoRotateHum=nil; return
    end
    if autoRotateHum~=hum then
        if autoRotateHum and autoRotateHum.Parent then
            autoRotateHum.AutoRotate=oldAutoRotate~=false
        end
        autoRotateHum=hum;oldAutoRotate=hum.AutoRotate
    end
    hum.AutoRotate=false
    root.CFrame=root.CFrame*CFrame.Angles(0,math.rad(S.SpinSpeed)*dt,0)
end
local function readWeaponInfo()
    local list={}
    local all=native.WeaponInfo and native.WeaponInfo.Enabled
    for id,info in pairs(type(all)=="table" and all or {}) do
        if type(id)=="string" and type(info)=="table" then list[#list+1]=id end
    end
    table.sort(list)
    return list
end
local function findUI()
    if window then
        local ui=window.ScreenGui or window.Gui
        if typeof(ui)=="Instance" and ui:IsA("ScreenGui") then return ui end
    end
    for _,parent in ipairs({LP:FindFirstChildOfClass("PlayerGui"),game:GetService("CoreGui")}) do
        if parent then
            local found=parent:FindFirstChild("CAT_EMPIRE_FPS104_104856666707760",true)
            if found and found:IsA("ScreenGui") then return found end
        end
    end
    return nil
end
local function setupPreview()
    if viewport then return true end
    local gui=findUI()
    if not gui then return false end
    local panel=Instance.new("Frame")
    panel.Name="CAT_EMPIRE_SKIN_PREVIEW"
    panel.Size=UDim2.fromOffset(235,255)
    panel.AnchorPoint=Vector2.new(1,0.5)
    panel.Position=UDim2.new(1,-20,0.5,0)
    panel.BackgroundColor3=Color3.fromRGB(20,16,30)
    panel.BorderSizePixel=0
    panel.Parent=gui
    local corner=Instance.new("UICorner")
    corner.CornerRadius=UDim.new(0,10);corner.Parent=panel
    local label=Instance.new("TextLabel")
    label.Size=UDim2.new(1,0,0,28)
    label.BackgroundTransparency=1
    label.TextColor3=Color3.fromRGB(224,199,255)
    label.Font=Enum.Font.GothamBold
    label.TextSize=12;label.Text="3D SKIN PREVIEW";label.Parent=panel
    viewport=Instance.new("ViewportFrame")
    viewport.Name="SkinViewport"
    viewport.Size=UDim2.new(1,-14,1,-40)
    viewport.Position=UDim2.fromOffset(7,30)
    viewport.BackgroundColor3=Color3.fromRGB(12,11,20)
    viewport.BackgroundTransparency=0.05
    viewport.Ambient=Color3.fromRGB(180,155,220)
    viewport.LightColor=Color3.fromRGB(255,225,255)
    viewport.Parent=panel
    previewCam=Instance.new("Camera")
    previewCam.Parent=viewport;viewport.CurrentCamera=previewCam
    worldModel=Instance.new("WorldModel")
    worldModel.Parent=viewport
    return true
end
local function updatePreview()
    if not setupPreview() then return end
    if previewModel then previewModel:Destroy();previewModel=nil end
    local info=native.WeaponInfo and native.WeaponInfo.All[S.SkinWeapon]
    if not info or type(info.getRig)~="function" then return end
    local ok,rig=pcall(info.getRig,S.SkinId~="" and S.SkinId or nil)
    if not ok or typeof(rig)~="Instance" then
        warnOnce("Skin 3D","Rig unavailable for "..S.SkinWeapon)
        return
    end
    local cloneOK,model=pcall(function() return rig:Clone() end)
    if not cloneOK or not model then return end
    if not model:IsA("Model") then
        local wrapper=Instance.new("Model")
        model.Parent=wrapper;model=wrapper
    end
    for _,item in ipairs(model:GetDescendants()) do
        if item:IsA("BasePart") then item.Anchored=true;item.CanCollide=false end
        if item:IsA("Script") or item:IsA("LocalScript") then item:Destroy() end
    end
    model.Parent=worldModel
    local cf,size=model:GetBoundingBox()
    model:PivotTo(CFrame.new(-cf.Position)*model:GetPivot())
    previewModel=model;previewAngle=0
    local radius=math.max(size.X,size.Y,size.Z,2)
    previewCam.CFrame=CFrame.lookAt(Vector3.new(radius*1.5,radius*0.75,radius*1.9),Vector3.zero)
    status("3D preview: "..S.SkinWeapon.." / "..(S.SkinId=="" and "Default" or S.SkinId))
end
local function updatePreviewSpin(dt)
    if previewModel and previewModel.Parent and S.PreviewSpin then
        previewAngle=previewAngle+dt*math.rad(24)
        previewModel:PivotTo(CFrame.Angles(0,previewAngle,0))
    end
end
local function equipSkin()
    if S.SkinWeapon=="" or S.SkinId=="" then notify("Select a weapon and skin");return end
    local packet=native.Net and native.Net.packets and native.Net.packets.equipSkin
    if not (packet and type(packet.send)=="function") then notify("equipSkin packet unavailable");return end
    local ok,err=pcall(packet.send,{weaponId=S.SkinWeapon,skinId=S.SkinId})
    if ok then
        notify("Equip request sent (requires owned skin and server approval)")
    else
        warnOnce("equipSkin",err);notify("Skin equip failed")
    end
end

local okInfo,gameInfo=pcall(MarketplaceService.GetProductInfo,MarketplaceService,game.PlaceId)
local gameTitle=okInfo and gameInfo and gameInfo.Name or "Roblox FPS"
window=Fluent:CreateWindow({
    Title="CAT EMPIRE | "..gameTitle,
    SubTitle="FPS | "..tostring(game.PlaceId),
    TabWidth=150,Size=UDim2.fromOffset(610,460),Acrylic=false,Animated=false,Theme="Dark",
    MinimizeKey=Enum.KeyCode.RightControl,
    ScreenGuiName="CAT_EMPIRE_FPS104_104856666707760",
})
local Tabs={
    Combat=window:AddTab({Title="Combat",Icon="solar/target-bold"}),
    Visuals=window:AddTab({Title="Visuals",Icon="solar/eye-bold"}),
    Weapons=window:AddTab({Title="Weapons",Icon="solar/bolt-bold"}),
    Skins=window:AddTab({Title="Skins",Icon="solar/bag-bold"}),
    Settings=window:AddTab({Title="Settings",Icon="solar/settings-bold"}),
    Misc=window:AddTab({Title="Misc",Icon="solar/user-bold"}),
}
local function toggle(tab,key,name,callback)
    Toggles[key]=tab:AddToggle("FPS104_"..key,{
        Title=name,Default=S[key] or false,
        Callback=function(v)
            S[key]=v==true
            if callback then pcall(callback,S[key]) end
        end,
    })
end
local function slider(tab,key,title,min,max,default,rounding)
    tab:AddSlider("FPS104_"..key,{
        Title=title,Min=min,Max=max,Default=default,Rounding=rounding or 1,
        Callback=function(v) S[key]=tonumber(v) or default end,
    })
end
local function drop(tab,key,title,values)
    return tab:AddDropdown("FPS104_"..key,{
        Title=title,Values=values,Default=S[key]~="" and S[key] or values[1],
        Callback=function(v) S[key]=tostring(v or "") end,
    })
end
local activity=Tabs.Combat:AddParagraph({Title=gameTitle,Content="Initializing FPS systems"})
toggle(Tabs.Combat,"SilentAim","Silent Aim (shot rays; server-dependent)",function(on)
    if on and not installSilent() then
        notify(S.SilentHookStatus)
        pcall(function() Toggles.SilentAim:SetValue(false) end)
    end
end)
toggle(Tabs.Combat,"Aimbot","Aimbot",function(on)
    if on then S.AimbotSafe=false;S.AimAssist=false
        pcall(function() Toggles.AimbotSafe:SetValue(false);Toggles.AimAssist:SetValue(false) end)
    end
end)
toggle(Tabs.Combat,"AimbotSafe","Aimbot Safe (smooth movement)",function(on)
    if on then S.Aimbot=false;S.AimAssist=false
        pcall(function() Toggles.Aimbot:SetValue(false);Toggles.AimAssist:SetValue(false) end)
    end
end)
toggle(Tabs.Combat,"AimAssist","Aim Assist (gradual)",function(on)
    if on then S.Aimbot=false;S.AimbotSafe=false
        pcall(function() Toggles.Aimbot:SetValue(false);Toggles.AimbotSafe:SetValue(false) end)
    end
end)
drop(Tabs.Combat,"AimPart","Target Body Part",{"Head","UpperTorso","Torso","HumanoidRootPart"})
drop(Tabs.Combat,"AimActivation","Aim Activation",{"RMB","LMB","Always"})
slider(Tabs.Combat,"AimFOV","Aim FOV (pixels)",35,600,190,0)
slider(Tabs.Combat,"AimSmooth","Aimbot Smooth",0.02,1,0.24,2)
slider(Tabs.Combat,"SafeSmooth","Safe Smooth",0.01,0.35,0.09,2)
slider(Tabs.Combat,"AssistStrength","Aim Assist Strength",0.01,0.35,0.11,2)
slider(Tabs.Combat,"MaxDistance","Max Range (studs)",100,3500,1800,0)
toggle(Tabs.Combat,"VisibleOnly","Visibility Check")
toggle(Tabs.Combat,"StickyTarget","Sticky Target")
toggle(Tabs.Combat,"ShowFOV","Show FOV Circle")

toggle(Tabs.Visuals,"ESP","ESP Master")
toggle(Tabs.Visuals,"ESPBox","ESP Box")
toggle(Tabs.Visuals,"ESPName","ESP Name")
toggle(Tabs.Visuals,"ESPDistance","ESP Distance")
toggle(Tabs.Visuals,"ESPHealth","ESP Health")
toggle(Tabs.Visuals,"ESPTracers","ESP Tracers")
toggle(Tabs.Visuals,"ESPSkeleton","ESP Skeleton")
toggle(Tabs.Visuals,"ESPShowTeam","Show Friendly Players")
toggle(Tabs.Visuals,"Chams","Chams | Character + Weapon")

local equippedCard=Tabs.Weapons:AddParagraph({Title="Equipped Weapon",Content="Waiting for loadout"})
toggle(Tabs.Weapons,"WeaponProfiles","Aimbot By Weapon")
Tabs.Weapons:AddButton({Title="Save Current Weapon Preset",Callback=function()
    local weapon=currentWeapon()
    if weapon=="" then notify("Equip a weapon first");return end
    S.ProfilesByWeapon[weapon]={FOV=S.AimFOV,Smooth=S.AimSmooth,Safe=S.SafeSmooth,Assist=S.AssistStrength}
    notify("Preset saved: "..weapon)
end})
Tabs.Weapons:AddButton({Title="Save Preset for Weapon Class",Callback=function()
    local info=native.WeaponInfo and native.WeaponInfo.All[currentWeapon()]
    if not info then notify("Weapon unavailable");return end
    S.ProfilesByWeapon["Class:"..tostring(info.Class)]={
        FOV=S.AimFOV,Smooth=S.AimSmooth,Safe=S.SafeSmooth,Assist=S.AssistStrength,
    }
    notify("Class preset saved: "..tostring(info.Class))
end})
slider(Tabs.Weapons,"SpinSpeed","Spin Bot Speed (degrees/s)",60,1600,250,0)
toggle(Tabs.Weapons,"SpinBot","Spin Bot (360 degree rotation)")

local weaponNames=readWeaponInfo()
if #weaponNames==0 then weaponNames={"Unavailable"} end
local skinsDrop
local function reloadSkins()
    local info=native.WeaponInfo and native.WeaponInfo.All[S.SkinWeapon]
    local names={"Default"}
    if info and type(info.Skins)=="table" then
        for skin in pairs(info.Skins) do names[#names+1]=skin end
        table.sort(names)
    end
    S.SkinId=""
    pcall(function() skinsDrop:SetValues(names);skinsDrop:SetValue("Default") end)
    updatePreview()
end
Tabs.Skins:AddDropdown("FPS104_SkinWeapon",{
    Title="Weapon",Values=weaponNames,Default=weaponNames[1],
    Callback=function(v) S.SkinWeapon=tostring(v or "");reloadSkins() end,
})
skinsDrop=Tabs.Skins:AddDropdown("FPS104_SkinId",{
    Title="Skin",Values={"Default"},Default="Default",
    Callback=function(v)
        S.SkinId=(v=="Default") and "" or tostring(v or "")
        updatePreview()
    end,
})
toggle(Tabs.Skins,"PreviewSpin","Rotate 3D Preview")
Tabs.Skins:AddButton({Title="Refresh 3D Preview",Callback=updatePreview})
Tabs.Skins:AddButton({Title="Equip Selected Owned Skin",Callback=equipSkin})
Tabs.Skins:AddParagraph({Title="Skin Sync",Content="3D preview is local. Equip uses the game's equipSkin packet; ownership and replication are verified by the server."})

local function cleanup()
    if not S.Running then return end
    S.Running=false
    for _,link in ipairs(Links) do pcall(function() link:Disconnect() end) end
    pcall(function() RunService:UnbindFromRenderStep("CAT_EMPIRE_FPS104_AIM") end)
    if autoRotateHum and autoRotateHum.Parent then pcall(function() autoRotateHum.AutoRotate=oldAutoRotate~=false end) end
    for model,r in pairs(visuals) do cleanRecord(r);visuals[model]=nil end
    for _,obj in ipairs(Drawings) do pcall(function() obj:Remove() end) end
    pcall(function() folder:Destroy() end)
    pcall(function() if viewport then viewport.Parent:Destroy() end end)
    pcall(function() window:Destroy() end)
    -- Silent hook remains inert after unload if executor has no restorefunction.
    Env.__CE_FPS104_CLEANUP=nil
end
Env.__CE_FPS104_CLEANUP=cleanup

local function loadSettings()
    local url="https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/StealABrainrot/Settings.lua"
    local ok,initializer=pcall(function()
        local source=game:HttpGet(url,true)
        return assert(loadstring(source))()
    end)
    if not ok or type(initializer)~="function" then
        warnOnce("Settings",initializer);return
    end
    local context={
        S=S,Player=LP,RS=RS,Tabs=Tabs,Toggles=Toggles,
        Window=window,Fluent=Fluent,Links=Links,HttpService=HttpService,
        Status=status,Notify=notify,Error=warnOnce,Cleanup=cleanup,
        GuiName="CAT_EMPIRE_FPS104_104856666707760",
        ExtraProfileTables={"ProfilesByWeapon"},
        ExtraProfileStrings={"AimPart","AimActivation","AimFOV","AimSmooth",
            "SafeSmooth","AssistStrength","MaxDistance","SpinSpeed","SkinWeapon","SkinId"},
    }
    local result,fn=pcall(initializer,context)
    if not result then warnOnce("Settings init",fn)
    elseif type(fn)=="function" then Links[#Links+1]={Disconnect=fn} end
end
loadSettings()
S.SkinWeapon=weaponNames[1]~="Unavailable" and weaponNames[1] or ""
task.defer(reloadSkins)
task.delay(1.5,updatePreview)
local function updateWeapon()
    local name=currentWeapon()
    if name~=S.CurrentWeapon then
        S.CurrentWeapon=name
        if name~="" then status("Weapon: "..name) end
    end
    local preset=S.ProfilesByWeapon[name]
    local info=native.WeaponInfo and native.WeaponInfo.All[name]
    if not preset and info then preset=S.ProfilesByWeapon["Class:"..tostring(info.Class)] end
    pcall(function()
        equippedCard:SetDesc((name~="" and name or "None")..
            (info and " | Class: "..tostring(info.Class) or "")..
            (preset and " | Preset active" or " | Global settings"))
    end)
end
local lastUpdate=0
RunService:BindToRenderStep("CAT_EMPIRE_FPS104_AIM",Enum.RenderPriority.Camera.Value+8,function(dt)
    if not S.Running then return end
    local ok,err=pcall(function()
        if fovCircle then
            local cam=workspace.CurrentCamera
            fovCircle.Visible=S.ShowFOV and cam~=nil
            if cam then
                fovCircle.Position=cam.ViewportSize/2
                fovCircle.Radius=maxFOV()
            end
        end
        updateAim(dt)
        updatePreviewSpin(dt)
    end)
    if not ok and os.clock()-lastUpdate>3 then lastUpdate=os.clock();warnOnce("Render",err) end
end)
Links[#Links+1]=RunService.Heartbeat:Connect(function(dt)
    if not S.Running then return end
    local ok,err=pcall(function()
        updateSpin(dt)
        local now=os.clock()
        if now-lastDraw>0.05 then lastDraw=now;updateESP() end
        if now-lastWeapon>0.45 then lastWeapon=now;updateWeapon() end
        if now-lastVisuals>1.2 then
            lastVisuals=now
            activity:SetDesc(S.LastAction.." | Silent: "..S.SilentHookStatus)
        end
    end)
    if not ok then warnOnce("Heartbeat",err) end
end)
if not drawingOK then
    notify("Drawing API unavailable: ESP boxes/lines/FOV disabled. Chams remain usable.")
end
status("CAT EMPIRE FPS initialized")
notify("CAT EMPIRE loaded: "..gameTitle)