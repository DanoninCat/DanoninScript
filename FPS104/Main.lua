-- CAT EMPIRE | FPS 104856666707760 | Luau client
-- Static references: Client.Combat.Targets, Client.State.Combat,
-- Shared.Weapons.WeaponInfo, Shared.Net, Camera.RenderPipeline.
-- Silence/replication of shot directions are SERVER-DEPENDENT, not guaranteed.
local PLACE = 104856666707760
if game.PlaceId ~= PLACE and game.PlaceId ~= 108448382032231 and game.GameId ~= PLACE then return end

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
local Links, Toggles = {}, {}
local S = {
    Running=true, Aimbot=false, AimbotSafe=false, SilentAim=false,
    AimPart="Head", AimActivation="Mouse Right Button", FOVDiameter=380,
    AimSmooth=0.24, SafeSmooth=0.09,
    VisibleOnly=true, StickyTarget=true,
    WeaponProfiles=true, ProfilesByWeapon={}, CurrentWeapon="",
    ESPBox=true, ESPName=true, ESPDistance=true, ESPHealth=true,
    ESPTracers=false, ESPSkeleton=false, ESPShowTeam=false, Chams=false,
    ChamsColor=Color3.fromRGB(144,78,255), ChamsColorHex="904EFF", ShowFOV=true,
    SpinBot=false, SpinSpeed=250, SkinWeapon="", SkinId="", PreviewSpin=true,
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
local lastDraw, lastWeapon = 0,0
local hookedSend
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
    native.ClientState=safeRequire(client,"State")
    native.LoadoutUtils=safeRequire(shared,"Utils","LoadoutUtils")
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
    do
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
local function getWeaponPreset()
    if not S.WeaponProfiles then return nil end
    local entry=native.WeaponInfo and native.WeaponInfo.All[S.CurrentWeapon]
    return S.ProfilesByWeapon[S.CurrentWeapon]
        or (entry and S.ProfilesByWeapon["Class:"..tostring(entry.Class)])
end
local function maxFOV()
    return math.max(15,tonumber(S.FOVDiameter) or 380)*0.5
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
                if distance<=1e8 then
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
    if S.AimActivation=="Always Active" then return true end
    if S.AimActivation=="Mouse Left Button" then
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
    if not (S.Aimbot or S.AimbotSafe) or not aimHeld() then
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
    local preset=getWeaponPreset()
    local strength= S.Aimbot and ((preset and preset.Smooth) or S.AimSmooth)
        or ((preset and preset.Safe) or S.SafeSmooth)
    local alpha=smoothFactor(dt,strength)
    -- Single camera writer after the native camera pipeline.
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
    hookedSend=true
    S.SilentHookStatus="Shot hook installed; server acceptance unverified"
    return true
end

-- ScreenGui visuals: no executor-specific Drawing library is required.
local visualGui=Instance.new("ScreenGui")
visualGui.Name="CAT_EMPIRE_FPS104_VISUALS"
visualGui.IgnoreGuiInset=true
visualGui.ResetOnSpawn=false
visualGui.DisplayOrder=800
visualGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
visualGui.Parent=LP:WaitForChild("PlayerGui")

local espColor=Color3.fromRGB(231,174,255)
local chamsFolder=Instance.new("Folder")
chamsFolder.Name="__CE_FPS104_Highlights"
chamsFolder.Parent=workspace
local function visualLine(parent,thickness,color)
    local line=Instance.new("Frame")
    line.Name="ESPLine"
    line.BorderSizePixel=0
    line.BackgroundColor3=color or espColor
    line.Size=UDim2.fromOffset(1,thickness or 2)
    line.AnchorPoint=Vector2.new(0.5,0.5)
    line.Active=false
    line.Visible=false
    line.ZIndex=12
    line.Parent=parent
    return line
end
local function placeLine(frame,startPos,endPos)
    local delta=endPos-startPos
    local length=delta.Magnitude
    if length<0.1 then frame.Visible=false;return end
    frame.Position=UDim2.fromOffset((startPos.X+endPos.X)/2,(startPos.Y+endPos.Y)/2)
    frame.Size=UDim2.fromOffset(length,2)
    frame.Rotation=math.deg(math.atan2(delta.Y,delta.X))
    frame.Visible=true
end
local function textLabel()
    local label=Instance.new("TextLabel")
    label.Name="ESPText"
    label.AnchorPoint=Vector2.new(0.5,0)
    label.BackgroundTransparency=1
    label.TextColor3=espColor
    label.TextStrokeTransparency=0.2
    label.TextStrokeColor3=Color3.new(0,0,0)
    label.TextSize=13
    label.Font=Enum.Font.GothamBold
    label.Size=UDim2.fromOffset(195,17)
    label.Active=false
    label.Visible=false
    label.ZIndex=13
    label.Parent=visualGui
    return label
end
local fovSegments={}
for i=1,72 do
    local line=visualLine(visualGui,2,Color3.fromRGB(174,111,255))
    line.Name="FOV"
    fovSegments[i]=line
end
local function updateFOV()
    local cam=workspace.CurrentCamera
    local show=S.Running and S.ShowFOV and cam~=nil
    local center=show and cam.ViewportSize/2 or Vector2.zero
    local radius=maxFOV()
    for i,line in ipairs(fovSegments) do
        if show then
            local a=(i-1)*2*math.pi/#fovSegments
            local b=i*2*math.pi/#fovSegments
            local p=center+Vector2.new(math.cos(a)*radius,math.sin(a)*radius)
            local q=center+Vector2.new(math.cos(b)*radius,math.sin(b)*radius)
            placeLine(line,p,q)
        else
            line.Visible=false
        end
    end
end

local function record(model)
    local previous=visuals[model]
    if previous then return previous end
    local r={highlights={},lines={},labels={}}
    for i=1,4 do r.lines[i]=visualLine(visualGui) end
    r.lines.tracer=visualLine(visualGui)
    for i=1,10 do
        r.lines["bone"..i]=visualLine(visualGui,2,Color3.fromRGB(255,201,255))
    end
    for _,key in ipairs({"name","distance","health"}) do r.labels[key]=textLabel() end
    visuals[model]=r
    return r
end
local function hideRecord(r)
    for _,part in pairs(r.lines) do part.Visible=false end
    for _,part in pairs(r.labels) do part.Visible=false end
end
local function cleanRecord(r)
    for _,part in pairs(r.lines) do part:Destroy() end
    for _,part in pairs(r.labels) do part:Destroy() end
    for _,part in pairs(r.highlights) do pcall(function() part:Destroy() end) end
end
local function setHighlight(r,key,adornee)
    local h=r.highlights[key]
    if not (S.Chams and adornee and adornee.Parent) then
        if h then h:Destroy();r.highlights[key]=nil end
        return
    end
    if not h then
        h=Instance.new("Highlight")
        h.Name="CE_Chams"
        h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
        h.FillTransparency=0.52
        h.OutlineTransparency=0
        h.Parent=chamsFolder
        r.highlights[key]=h
    end
    h.FillColor=S.ChamsColor
    h.OutlineColor=S.ChamsColor
    h.Adornee=adornee
end
local function weaponModel(model)
    for _,child in ipairs(model:GetChildren()) do
        if child:IsA("Tool") then
            return child:FindFirstChildWhichIsA("Model",true)
                or child:FindFirstChildWhichIsA("BasePart",true)
        end
        if child:IsA("Model") and (child.Name:lower():find("weapon") or child.Name:lower():find("gun")) then
            return child
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
local r6Bones={
    {"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"},
    {"Torso","Left Leg"},{"Torso","Right Leg"},
}
local function getBounds(model,cam)
    local cf,size=model:GetBoundingBox()
    local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
    local valid=0
    for x=-1,1,2 do
        for y=-1,1,2 do
            for z=-1,1,2 do
                local point=cf:PointToWorldSpace(Vector3.new(size.X*x/2,size.Y*y/2,size.Z*z/2))
                local screen=cam:WorldToViewportPoint(point)
                if screen.Z>0.05 then
                    minX=math.min(minX,screen.X)
                    minY=math.min(minY,screen.Y)
                    maxX=math.max(maxX,screen.X)
                    maxY=math.max(maxY,screen.Y)
                    valid=valid+1
                end
            end
        end
    end
    if valid<4 or maxX<0 or maxY<0
        or minX>cam.ViewportSize.X or minY>cam.ViewportSize.Y then return nil end
    return minX,minY,maxX,maxY
end
local function anyESP()
    return S.ESPBox or S.ESPName or S.ESPDistance or S.ESPHealth
        or S.ESPTracers or S.ESPSkeleton
end
local function updateESP()
    local cam=workspace.CurrentCamera
    if not cam then return end
    local seen={}
    local center=Vector2.new(cam.ViewportSize.X/2,cam.ViewportSize.Y)
    local own=myRoot()
    local hex=type(S.ChamsColorHex)=="string" and S.ChamsColorHex:gsub("#","") or ""
    if #hex==6 and S._lastChamsHex~=hex then
        local n=tonumber(hex,16)
        if n then
            S.ChamsColor=Color3.fromRGB(
                math.floor(n/65536)%256,math.floor(n/256)%256,n%256)
            S._lastChamsHex=hex
        end
    end
    for _,model in ipairs(targetModels()) do
        seen[model]=true
        local r=record(model)
        hideRecord(r)
        local root=rootOf(model)
        local allowed=root and living(model) and (S.ESPShowTeam or not isFriendly(model))
        setHighlight(r,"character",allowed and model or nil)
        setHighlight(r,"weapon",allowed and weaponModel(model) or nil)
        if allowed and anyESP() then
            local ok,x1,y1,x2,y2=pcall(getBounds,model,cam)
            if ok and x1 then
                local mid=(x1+x2)/2
                local width=math.clamp(x2-x1,2,cam.ViewportSize.X*2)
                local height=math.clamp(y2-y1,2,cam.ViewportSize.Y*2)
                local left=mid-width/2
                local right=mid+width/2
                local top=y1
                local bottom=y1+height
                if S.ESPBox then
                    placeLine(r.lines[1],Vector2.new(left,top),Vector2.new(right,top))
                    placeLine(r.lines[2],Vector2.new(right,top),Vector2.new(right,bottom))
                    placeLine(r.lines[3],Vector2.new(right,bottom),Vector2.new(left,bottom))
                    placeLine(r.lines[4],Vector2.new(left,bottom),Vector2.new(left,top))
                end
                if S.ESPName then
                    local player=Players:GetPlayerFromCharacter(model)
                    local name=r.labels.name
                    name.Text=player and player.DisplayName or model.Name
                    name.Position=UDim2.fromOffset(mid,top-19)
                    name.Visible=true
                end
                if S.ESPDistance then
                    local dist=own and (root.Position-own.Position).Magnitude or 0
                    local label=r.labels.distance
                    label.Text=tostring(math.floor(dist)).." studs"
                    label.Position=UDim2.fromOffset(mid,bottom+3)
                    label.Visible=true
                end
                if S.ESPHealth then
                    local hum=model:FindFirstChildOfClass("Humanoid")
                    if hum then
                        local label=r.labels.health
                        label.Text=math.ceil(hum.Health).."/"..math.ceil(hum.MaxHealth).." HP"
                        label.Position=UDim2.fromOffset(mid,bottom+20)
                        label.Visible=true
                    end
                end
                if S.ESPTracers then
                    placeLine(r.lines.tracer,center,Vector2.new(mid,bottom))
                end
                if S.ESPSkeleton then
                    local bones=model:FindFirstChild("UpperTorso") and bonePairs or r6Bones
                    for i,pair in ipairs(bones) do
                        local first=model:FindFirstChild(pair[1],true)
                        local second=model:FindFirstChild(pair[2],true)
                        if first and second and first:IsA("BasePart") and second:IsA("BasePart") then
                            local a=cam:WorldToViewportPoint(first.Position)
                            local b=cam:WorldToViewportPoint(second.Position)
                            if a.Z>0 and b.Z>0 then
                                placeLine(r.lines["bone"..i],Vector2.new(a.X,a.Y),Vector2.new(b.X,b.Y))
                            end
                        end
                    end
                end
            end
        end
    end
    for model,r in pairs(visuals) do
        if not seen[model] or not model.Parent then
            cleanRecord(r);visuals[model]=nil
        end
    end
end

local function updateSpin(dt)
    local root,hum=myRoot(),LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if not S.SpinBot or not root or not hum then
        if autoRotateHum and autoRotateHum.Parent then
            autoRotateHum.AutoRotate=oldAutoRotate
        end
        autoRotateHum=nil; return
    end
    if autoRotateHum~=hum then
        if autoRotateHum and autoRotateHum.Parent then
            autoRotateHum.AutoRotate=oldAutoRotate
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
local function findSkinContent()
    local gui=findUI()
    if not gui then return nil end
    local anchors={
        ["Refresh 3D Preview"]=true,["Equip Selected Skin"]=true,
        ["Equip Selected Weapon"]=true,["Rotate 3D Preview"]=true,
    }
    for _,item in ipairs(gui:GetDescendants()) do
        if (item:IsA("TextLabel") or item:IsA("TextButton"))
            and anchors[item.Text] then
            local p=item.Parent
            while p and p~=gui do
                if p:IsA("ScrollingFrame") then return p end
                p=p.Parent
            end
        end
    end
    return nil
end
local function setupPreview()
    if viewport and viewport.Parent then return true end
    local content=findSkinContent()
    if not content then return false end
    local panel=Instance.new("Frame")
    panel.Name="CAT_EMPIRE_SKIN_PREVIEW"
    panel.LayoutOrder=9990
    panel.Size=UDim2.new(1,-12,0,238)
    panel.BackgroundColor3=Color3.fromRGB(20,16,30)
    panel.BorderSizePixel=0
    panel.ClipsDescendants=true
    panel.Parent=content
    local corner=Instance.new("UICorner")
    corner.CornerRadius=UDim.new(0,10)
    corner.Parent=panel
    viewport=Instance.new("ViewportFrame")
    viewport.Name="SkinViewport"
    viewport.Size=UDim2.new(1,-12,1,-12)
    viewport.Position=UDim2.fromOffset(6,6)
    viewport.BackgroundColor3=Color3.fromRGB(12,11,20)
    viewport.BackgroundTransparency=0
    viewport.Ambient=Color3.fromRGB(180,155,220)
    viewport.LightColor=Color3.fromRGB(255,225,255)
    viewport.Parent=panel
    previewCam=Instance.new("Camera")
    previewCam.Parent=viewport
    viewport.CurrentCamera=previewCam
    worldModel=Instance.new("WorldModel")
    worldModel.Parent=viewport
    -- The viewport is a genuine descendant of the Skins tab's scrolling content.
    -- Extend canvas for UI libraries that do not use AutomaticCanvasSize.
    pcall(function()
        if content.AutomaticCanvasSize==Enum.AutomaticSize.None then
            local layout=content:FindFirstChildWhichIsA("UIListLayout")
            if layout then
                local wanted=layout.AbsoluteContentSize.Y+255
                content.CanvasSize=UDim2.new(0,0,0,math.max(content.CanvasSize.Y.Offset,wanted))
            end
        end
    end)
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

local gameTitle="Roblox FPS"
for _=1,3 do
    local okInfo,gameInfo=pcall(MarketplaceService.GetProductInfo,MarketplaceService,game.PlaceId)
    if okInfo and gameInfo and type(gameInfo.Name)=="string" and #gameInfo.Name>0 then
        gameTitle=gameInfo.Name
        break
    end
    task.wait(0.25)
end
window=Fluent:CreateWindow({
    Title="CAT EMPIRE",
    SubTitle=gameTitle,
    TabWidth=150,Size=UDim2.fromOffset(610,460),Acrylic=false,Animated=false,Theme="Dark",
    MinimizeKey=Enum.KeyCode.RightControl,
    ScreenGuiName="CAT_EMPIRE_FPS104_104856666707760",
})
local Tabs={
    Combat=window:AddTab({Title="Combat",Icon="solar/target-bold"}),
    Visuals=window:AddTab({Title="Visuals",Icon="solar/eye-bold"}),
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
toggle(Tabs.Combat,"SilentAim","Silent Aim",function(on)
    if on and not installSilent() then
        notify(S.SilentHookStatus)
        pcall(function() Toggles.SilentAim:SetValue(false) end)
    end
end)
toggle(Tabs.Combat,"Aimbot","Aimbot",function(on)
    if on then
        S.AimbotSafe=false
        pcall(function() Toggles.AimbotSafe:SetValue(false) end)
    end
end)
toggle(Tabs.Combat,"AimbotSafe","Aimbot Safe",function(on)
    if on then
        S.Aimbot=false
        pcall(function() Toggles.Aimbot:SetValue(false) end)
    end
end)
drop(Tabs.Combat,"AimPart","Target Body Part",{"Head","UpperTorso","Torso","HumanoidRootPart"})
drop(Tabs.Combat,"AimActivation","Aim Activation",{"Mouse Right Button","Mouse Left Button","Always Active"})
slider(Tabs.Combat,"FOVDiameter","FOV Circle Diameter",70,1200,380,0)
slider(Tabs.Combat,"AimSmooth","Aimbot Smooth",0.02,1,0.24,2)
slider(Tabs.Combat,"SafeSmooth","Safe Smooth",0.01,0.35,0.09,2)
toggle(Tabs.Combat,"VisibleOnly","Visibility Check")
toggle(Tabs.Combat,"StickyTarget","Sticky Target")
toggle(Tabs.Combat,"ShowFOV","Show FOV Circle")

toggle(Tabs.Visuals,"ESPBox","ESP Box")
toggle(Tabs.Visuals,"ESPName","ESP Name")
toggle(Tabs.Visuals,"ESPDistance","ESP Distance")
toggle(Tabs.Visuals,"ESPHealth","ESP Health")
toggle(Tabs.Visuals,"ESPTracers","ESP Lines")
toggle(Tabs.Visuals,"ESPSkeleton","ESP Skeleton")
toggle(Tabs.Visuals,"ESPShowTeam","Show Friendly Players")
toggle(Tabs.Visuals,"Chams","Chams")
local palette={
    Purple=Color3.fromRGB(144,78,255),
    Pink=Color3.fromRGB(255,105,180),
    Red=Color3.fromRGB(255,72,88),
    Orange=Color3.fromRGB(255,153,62),
    Yellow=Color3.fromRGB(255,225,96),
    Green=Color3.fromRGB(81,232,135),
    Blue=Color3.fromRGB(84,153,255),
    Cyan=Color3.fromRGB(67,230,234),
    White=Color3.fromRGB(255,255,255),
}
local hasPicker=pcall(function()
    Tabs.Visuals:AddColorpicker("FPS104_ChamsPalette",{
        Title="Chams Color",Default=S.ChamsColor,
        Callback=function(color)
            if typeof(color)=="Color3" then
                S.ChamsColor=color
                local r=math.round(color.R*255)
                local g=math.round(color.G*255)
                local b=math.round(color.B*255)
                S.ChamsColorHex=string.format("%02X%02X%02X",r,g,b)
            end
        end,
    })
end)
if not hasPicker then
    Tabs.Visuals:AddDropdown("FPS104_ChamsPalette",{
        Title="Chams Color",Values={"Purple","Pink","Red","Orange","Yellow","Green","Blue","Cyan","White"},
        Default="Purple",
        Callback=function(value)
            if palette[value] then
                S.ChamsColor=palette[value]
                local c=palette[value]
                S.ChamsColorHex=string.format("%02X%02X%02X",
                    math.round(c.R*255),math.round(c.G*255),math.round(c.B*255))
            end
        end,
    })
end

toggle(Tabs.Combat,"WeaponProfiles","Aimbot By Weapon")
Tabs.Combat:AddButton({Title="Save Weapon Aim Settings",Callback=function()
    local weapon=currentWeapon()
    if weapon=="" then notify("Equip a weapon first");return end
    S.ProfilesByWeapon[weapon]={Smooth=S.AimSmooth,Safe=S.SafeSmooth}
    notify("Saved: "..weapon)
end})
slider(Tabs.Combat,"SpinSpeed","Spin Bot Speed",60,1600,250,0)
toggle(Tabs.Combat,"SpinBot","Spin Bot")
local function equipSelectedWeapon()
    local selected=S.SkinWeapon
    if selected=="" or not (native.WeaponInfo and native.WeaponInfo.All[selected]) then
        notify("Select a weapon")
        return
    end
    local packet=native.Net and native.Net.packets and native.Net.packets.equipWeapon
    if not packet or type(packet.send)~="function" then
        notify("Equip unavailable")
        return
    end
    local state=native.ClientState
    local saved=state and state.Save and state.Save.Loadout
    if saved and native.LoadoutUtils and type(native.LoadoutUtils.canEquipWeapon)=="function" then
        local current={
            Primary=atomValue(saved.Primary),
            Secondary=atomValue(saved.Secondary),
            Melee=atomValue(saved.Melee),
        }
        if current.Primary and current.Secondary and current.Melee then
            local ok,allow,reason=pcall(native.LoadoutUtils.canEquipWeapon,current,selected)
            if ok and allow==false then
                notify("Cannot equip: "..tostring(reason or "restricted"))
                return
            end
        end
    end
    local ok,err=pcall(packet.send,{weaponId=selected})
    if not ok then warnOnce("Equip Weapon",err);notify("Equip failed");return end
    -- Do not report success merely because a client request was sent.
    task.delay(1.5,function()
        if not S.Running then return end
        local info=native.WeaponInfo.All[selected]
        local slot=info and info.BaseConfig and info.BaseConfig.General and info.BaseConfig.General.Slot
        local currentSlot=slot and saved and saved[slot]
        local equipped=atomValue(currentSlot)
        if equipped==selected then
            notify("Equipped: "..selected)
        else
            notify("Equip requested; verify ownership in loadout")
        end
    end)
end
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
local weaponPicker=Tabs.Skins:AddDropdown("FPS104_SkinWeapon",{
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
Tabs.Skins:AddButton({Title="Equip Selected Skin",Callback=equipSkin})
Tabs.Skins:AddButton({Title="Equip Selected Weapon",Callback=equipSelectedWeapon})

local function cleanup()
    if not S.Running then return end
    S.Running=false
    for _,link in ipairs(Links) do pcall(function() link:Disconnect() end) end
    pcall(function() RunService:UnbindFromRenderStep("CAT_EMPIRE_FPS104_AIM") end)
    if autoRotateHum and autoRotateHum.Parent then pcall(function() autoRotateHum.AutoRotate=oldAutoRotate end) end
    for model,r in pairs(visuals) do cleanRecord(r);visuals[model]=nil end
    pcall(function() visualGui:Destroy() end)
    pcall(function() chamsFolder:Destroy() end)
    pcall(function() if viewport then viewport.Parent:Destroy() end end)
    pcall(function() window:Destroy() end)
    -- Silent hook remains inert after unload if executor has no restorefunction.
    Env.__CE_FPS104_CLEANUP=nil
end
Env.__CE_FPS104_CLEANUP=cleanup

local function loadSettings()
    local url="https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/FPS104/Settings.lua"
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
        ExtraProfileStrings={"AimPart","AimActivation","FOVDiameter","AimSmooth",
            "SafeSmooth","SpinSpeed","SkinWeapon","SkinId","ChamsColorHex"},
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
    if name~=S.CurrentWeapon then S.CurrentWeapon=name end
    if weaponNames[1]=="Unavailable" then
        initializeNative()
        local loaded=readWeaponInfo()
        if #loaded>0 then
            weaponNames=loaded
            S.SkinWeapon=loaded[1]
            pcall(function()
                weaponPicker:SetValues(loaded)
                weaponPicker:SetValue(loaded[1])
            end)
            task.defer(reloadSkins)
        end
    end
end
local lastUpdate=0
RunService:BindToRenderStep("CAT_EMPIRE_FPS104_AIM",Enum.RenderPriority.Camera.Value+8,function(dt)
    if not S.Running then return end
    local ok,err=pcall(function()
        updateFOV()
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
    end)
    if not ok then warnOnce("Heartbeat",err) end
end)
status("CAT EMPIRE FPS initialized")
notify("CAT EMPIRE loaded: "..gameTitle)