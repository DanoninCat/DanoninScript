return function(ctx)
local S, Tabs, Remotes, LocalPlayer, Players = ctx.State, ctx.Tabs, ctx.Remotes, ctx.LocalPlayer, ctx.Players
local Fluent, Window, Env = ctx.Fluent, ctx.Window, ctx.Env
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local MatchConfig = require(RS:WaitForChild("MatchConfig"))
local PlacementConfig = require(RS:WaitForChild("PlacementConfig"))
local PlaceRequest = Remotes:FindFirstChild("PlaceRequest")
local MatchAction = Remotes:FindFirstChild("MatchAction")
local StatRerollRequest = Remotes:FindFirstChild("StatRerollRequest")
local StatRerollResult = Remotes:FindFirstChild("StatRerollResult")
local MatchState = Remotes:FindFirstChild("MatchState")
local LuckPotion = Remotes:FindFirstChild("LuckPotion")
local RedeemCode = Remotes:FindFirstChild("RedeemCode")
local Links, UI = {}, {}
local ProfilesFolder = "CAT_EMPIRE_RE_ADVENTURES_105"
local ActiveFolder = ProfilesFolder .. "/profiles"
local IndexFile = ProfilesFolder .. "/index.json"
local PLACE_FOLDER_NAME = PlacementConfig.PLACED_FOLDER or "PlacedUnits"
local Runtime = {activeKey="", round=0, placed={}, busy={}, last={}, match={}, macroStart=0, mouseMode=nil,
    selectedMarker=nil, macroRecording=false, macroPlaying=false, lastResult="", hookReady=false,
    recordedPositions={}, lastStatus="", redraw=0}
local Config = {
    sections={}, webhook={enabled=false,url=""}, macros={}, macroName="Default", profileName="Default",
    autoLoad=false, autoCloseUI=false, stat={enabled=false,unitId="",stat="All"},
    luck=false, codes=false, codeDone={}, lastName="Default"
}
local Sections = {"Story Mode","Raids","Infinite Castle","Portals"}
local Prefixes = {["Story Mode"]="Story",Raids="Raids",["Infinite Castle"]="Castle",Portals="Portals"}
local ModeLookup = {story="Story Mode",raid="Raids",raids="Raids",castle="Infinite Castle",
    infinity="Infinite Castle",infinite="Infinite Castle",portal="Portals",portals="Portals"}
local function notify(message)
    pcall(function() Fluent:Notify({Title="CAT EMPIRE",Content=tostring(message),Duration=5}) end)
end
local function listen(signal,callback)
    if signal then local connection=signal:Connect(callback); Links[#Links+1]=connection; return connection end
end
local function toText(s) return tostring(s or "") end
local function safeName(value)
    local s=toText(value):gsub("[^%w_%-%s]",""):sub(1,40):gsub("^%s+",""):gsub("%s+$","")
    return s~="" and s or "Default"
end
local function copyPlain(value,depth)
    if depth>10 then return nil end
    local typ=type(value)
    if typ=="string" or typ=="number" or typ=="boolean" then return value end
    if typ~="table" then return nil end
    local r={}
    for k,v in pairs(value) do
        if type(k)=="string" or type(k)=="number" then
            local x=copyPlain(v,depth+1)
            if x~=nil then r[k]=x end
        end
    end
    return r
end
local function filesystem()
    local write=Env.writefile or writefile
    local read=Env.readfile or readfile
    local exists=Env.isfile or isfile
    local dir=Env.makefolder or makefolder
    return write,read,exists,dir
end
local function writeJSON(path,data)
    local write,_,_,dir=filesystem()
    if type(write)~="function" then return false,"executor does not support writefile" end
    if type(dir)=="function" then
        pcall(dir,ProfilesFolder)
        pcall(dir,ActiveFolder)
    end
    local ok,err=pcall(function() write(path,HttpService:JSONEncode(data)) end)
    return ok,err
end
local function readJSON(path)
    local _,read,exists=filesystem()
    if type(read)~="function" then return nil end
    if type(exists)=="function" then
        local ok,result=pcall(exists,path)
        if not ok or not result then return nil end
    end
    local ok,result=pcall(function() return HttpService:JSONDecode(read(path)) end)
    return ok and type(result)=="table" and result or nil
end
local function profilePath(name)
    return ActiveFolder .. "/" .. safeName(name):gsub("%s+","_") .. ".json"
end
local function newSection(name)
    local t=Config.sections[name] or {}
    t.maps=t.maps or {}
    for _,key in ipairs({"autoPlace","autoUpgrade","autoReplay","autoWaveSkip","autoVoteStart"}) do
        if type(t[key])~="boolean" then t[key]=false end
    end
    t.slot=tonumber(t.slot) or 1
    t.selectedMarker=tonumber(t.selectedMarker) or 1
    t.capture=false
    Config.sections[name]=t
    return t
end
for _,section in ipairs(Sections) do newSection(section) end
local function unitNameForSlot(slot)
    for _,unit in ipairs(S.Units or {}) do
        local id=tonumber(unit.slot or unit.equipSlot or unit.equippedSlot)
        if id==slot then
            local original=toText(unit.name or "Unit")
            local ok,definition=pcall(ctx.UnitData.unitByName,original)
            return ok and type(definition)=="table" and toText(definition.displayName or definition.name or original) or original
        end
    end
    return "Slot " .. tostring(slot)
end
local function vecToTable(v)
    return {x=math.floor(v.X*1000+0.5)/1000,y=math.floor(v.Y*1000+0.5)/1000,z=math.floor(v.Z*1000+0.5)/1000}
end
local function tableToVec(t)
    if type(t)~="table" then return nil end
    local x,y,z=tonumber(t.x),tonumber(t.y),tonumber(t.z)
    if x and y and z then return Vector3.new(x,y,z) end
end
local function attr(instance,key)
    if not instance then return nil end
    local ok,v=pcall(function()return instance:GetAttribute(key) end)
    return ok and v or nil
end
local function mapKey()
    local map=workspace:FindFirstChild("map")
    local m=Runtime.match or {}
    local keys={
        m.levelId,m.LevelId,m.stageId,m.StageId,m.mapId,m.MapId,
        attr(LocalPlayer,"MatchLevelId"),attr(LocalPlayer,"CurrentMapId"),
        attr(map,"LevelId"),attr(map,"MapId"),attr(map,"StageId"),
        map and map.Name
    }
    for i=1,12 do
        local value=keys[i]
        if value~=nil and toText(value)~="" then return toText(value) end
    end
    return "current-map"
end
local function modeForMatch()
    local m=Runtime.match or {}
    local values={
        m.mode,m.Mode,m.matchType,m.MatchType,m.gameMode,m.GameMode,m.raidKey,
        attr(LocalPlayer,"MatchMode"),attr(LocalPlayer,"GameMode"),attr(workspace,"MatchMode")
    }
    for i=1,9 do
        local raw=values[i]
        local text=toText(raw):lower()
        for word,section in pairs(ModeLookup) do
            if text:find(word,1,true) then return section end
        end
    end
    return "Story Mode"
end
local function isInMatch() return attr(LocalPlayer,"MatchJoined")==true end
local function sectionMap(section)
    local config=newSection(section)
    local key=mapKey()
    config.maps[key]=config.maps[key] or {}
    return config.maps[key],key
end
local markerFolder=Instance.new("Folder")
markerFolder.Name="CE_RE105_PositionMarkers"
markerFolder.Parent=workspace
local function clearMarkers()
    markerFolder:ClearAllChildren()
end
local function drawMarker(marker,index)
    local position=tableToVec(marker.position)
    if not position then return end
    local origin=Instance.new("Folder")
    origin.Name="Mark_"..index
    origin.Parent=markerFolder
    for _,angle in ipairs({45,-45}) do
        local p=Instance.new("Part")
        p.Name="X"
        p.Size=Vector3.new(2.6,0.1,0.20)
        p.Anchored=true
        p.CanCollide=false
        p.CanTouch=false
        p.CanQuery=false
        p.CastShadow=false
        p.Material=Enum.Material.Neon
        p.Color=Color3.fromRGB(178,106,255)
        p.CFrame=CFrame.new(position+Vector3.new(0,0.1,0))*CFrame.Angles(0,math.rad(angle),0)
        p.Parent=origin
    end
    local anchor=Instance.new("Part")
    anchor.Name="Label"
    anchor.Size=Vector3.new(0.1,0.1,0.1)
    anchor.Anchored=true
    anchor.Transparency=1
    anchor.CanCollide=false
    anchor.CanQuery=false
    anchor.Position=position+Vector3.new(0,0.45,0)
    anchor.Parent=origin
    local board=Instance.new("BillboardGui")
    board.Name="UnitName"
    board.Size=UDim2.fromOffset(170,37)
    board.StudsOffsetWorldSpace=Vector3.new(0,1.4,0)
    board.AlwaysOnTop=true
    board.Adornee=anchor
    board.Parent=anchor
    local label=Instance.new("TextLabel")
    label.Size=UDim2.fromScale(1,1)
    label.BackgroundTransparency=1
    label.TextColor3=Color3.fromRGB(238,227,255)
    label.TextStrokeTransparency=0.2
    label.TextScaled=true
    label.Font=Enum.Font.GothamBold
    label.Text=toText(marker.unitName)
    label.Parent=board
end
local function redrawMarkers()
    clearMarkers()
    local name=modeForMatch()
    local config=newSection(name)
    if not (config.autoPlace or config.capture) then return end
    local map=sectionMap(name)
    for i,marker in ipairs(map) do drawMarker(marker,i) end
end
local function selectMarkerLabels(section)
    local map=sectionMap(section)
    local labels={}
    for i,m in ipairs(map) do
        labels[#labels+1]=tostring(i).." • "..toText(m.unitName).." (Slot "..toText(m.slot)..")"
    end
    return labels
end
local MarkerSelectors={}
local function refreshMarkerLists()
    for section,drop in pairs(MarkerSelectors) do
        if drop and drop.SetValues then
            local names=selectMarkerLabels(section)
            pcall(function() drop:SetValues(names) end)
        end
    end
end
local function findPlaced()
    return workspace:FindFirstChild(PLACE_FOLDER_NAME)
end
local function ownUnit(model)
    local owner=attr(model,"OwnerUserId") or attr(model,"UserId")
    if owner~=nil then return tonumber(owner)==LocalPlayer.UserId end
    local ownerPlayer=attr(model,"Owner")
    if ownerPlayer~=nil then
        return toText(ownerPlayer)==LocalPlayer.Name or tonumber(ownerPlayer)==LocalPlayer.UserId
    end
    return true
end
local function modelPosition(unit)
    if unit:IsA("Model") then
        local ok,pivot=pcall(function()return unit:GetPivot().Position end)
        if ok then return pivot end
    elseif unit:IsA("BasePart") then return unit.Position end
    return nil
end
local function findPlacedNear(pos,range)
    local folder=findPlaced()
    if not folder then return nil end
    for _,model in ipairs(folder:GetChildren()) do
        if ownUnit(model) then
            local p=modelPosition(model)
            if p and (p-pos).Magnitude <= (range or 2.5) then return model end
        end
    end
end
local function modelPlaceId(model)
    return model and (attr(model,"PlaceId") or attr(model,"CopyId")) or nil
end
local function setLast(key) Runtime.last[key]=os.clock() end
local function cooldown(key,seconds)
    return (os.clock()-(Runtime.last[key] or -math.huge)) >= seconds
end
local function send(endpoint,...)
    if not endpoint then return false end
    local args=table.pack(...)
    local ok=pcall(function() endpoint:FireServer(table.unpack(args,1,args.n)) end)
    return ok
end
local function activeSection(section)
    return S.Running and isInMatch() and modeForMatch()==section and not Runtime.macroPlaying
end
local function processSection(section)
    local cfg=newSection(section)
    if not activeSection(section) then return end
    local map,key=sectionMap(section)
    local roundKey=section..":"..key..":"..toText(Runtime.round)
    if cfg.autoPlace and PlaceRequest and not Runtime.busy.place and cooldown("place",1) then
        for index,marker in ipairs(map) do
            local pos=tableToVec(marker.position)
            local recordKey=roundKey..":"..tostring(index)
            if pos and not Runtime.placed[recordKey] then
                local unit=findPlacedNear(pos,2.5)
                if unit then
                    Runtime.placed[recordKey]=true
                else
                    Runtime.busy.place=true
                    setLast("place")
                    local ok=send(PlaceRequest,{slot=tonumber(marker.slot) or 1,position=pos,yaw=tonumber(marker.yaw) or 0})
                    Runtime.busy.place=false
                    if ok then
                        -- Confirm from the replicated placed-unit model before advancing to next marker.
                        task.delay(1,function()
                            if not S.Running then return end
                            if findPlacedNear(pos,2.5) then Runtime.placed[recordKey]=true end
                        end)
                    end
                    break
                end
            end
        end
    end
    if cfg.autoUpgrade and MatchAction and not Runtime.busy.upgrade and cooldown("upgrade",0.55) then
        local folder=findPlaced()
        if folder then
            for _,model in ipairs(folder:GetChildren()) do
                if ownUnit(model) then
                    local lvl=tonumber(attr(model,MatchConfig.UPGRADE_ATTRIBUTE or "UpgradeLevel")) or 0
                    local id=modelPlaceId(model)
                    if id and lvl < (tonumber(MatchConfig.MAX_UPGRADE) or 5) then
                        local tag="u_"..toText(id)..":"..lvl
                        if cooldown(tag,2.2) then
                            setLast(tag)
                            setLast("upgrade")
                            Runtime.busy.upgrade=true
                            send(MatchAction,"upgrade",id)
                            Runtime.busy.upgrade=false
                            break
                        end
                    end
                end
            end
        end
    end
    local m=Runtime.match
    local st=m and m.state
    local phase=MatchConfig.STATE or {}
    local wave=tostring(m.wave or m.Wave or attr(LocalPlayer,"Wave") or "unknown")
    if cfg.autoVoteStart and st==phase.LOBBY and cooldown("start:"..roundKey,7) then
        setLast("start:"..roundKey)
        send(MatchAction,"voteStart",true,nil)
    end
    if cfg.autoWaveSkip and (st==phase.PREP or st==phase.WAVE) and cooldown("skip:"..roundKey..":"..wave,6) then
        setLast("skip:"..roundKey..":"..wave)
        send(MatchAction,"voteSkip",true,nil)
    end
    if cfg.autoReplay and (st==phase.VICTORY or st==phase.DEFEAT) and cooldown("replay:"..roundKey,15) then
        setLast("replay:"..roundKey)
        send(MatchAction,"replay",nil,nil)
    end
end
local function currentSectionForCapture()
    local name=modeForMatch()
    local cfg=newSection(name)
    if cfg.capture then return name,cfg end
end
local function groundPosition(screen)
    local camera=workspace.CurrentCamera
    if not camera then return nil end
    local ray=camera:ViewportPointToRay(screen.X,screen.Y)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    local exclusions={markerFolder}
    if LocalPlayer.Character then exclusions[#exclusions+1]=LocalPlayer.Character end
    params.FilterDescendantsInstances=exclusions
    local hit=workspace:Raycast(ray.Origin,ray.Direction*1500,params)
    if not hit then return nil end
    local target=hit.Instance
    local valid=CollectionService:HasTag(target,PlacementConfig.GROUND_TAG or "PlaceableGround")
    local parent=target.Parent
    while parent and parent~=workspace and not valid do
        valid=CollectionService:HasTag(parent,PlacementConfig.GROUND_TAG or "PlaceableGround")
        parent=parent.Parent
    end
    if not valid then
        local map=workspace:FindFirstChild("map")
        valid=map~=nil and target:IsDescendantOf(map) and math.abs(hit.Normal.Y)>0.65
    end
    if not valid then return nil end
    if CollectionService:HasTag(target,PlacementConfig.BLOCKED_TAG or "NoPlace") then return nil end
    return hit.Position
end
listen(UIS.InputBegan,function(input,processed)
    if processed or not isInMatch() then return end
    if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
    local section,cfg=currentSectionForCapture()
    if not section then return end
    local position=groundPosition(input.Position)
    if not position then return end
    local map=sectionMap(section)
    local slot=tonumber(cfg.slot) or 1
    local marker={slot=slot,unitName=unitNameForSlot(slot),position=vecToTable(position),yaw=0}
    map[#map+1]=marker
    cfg.selectedMarker=#map
    redrawMarkers()
    refreshMarkerLists()
    notify("Position saved: "..marker.unitName)
end)
local function setControl(key,ctrl)
    UI[key]=ctrl
    return ctrl
end
local function toggle(tab,id,title,initial,callback)
    return setControl(id,tab:AddToggle(id,{Title=title,Default=initial,Callback=callback}))
end
local function dropdown(tab,id,title,values,initial,callback,multi)
    return setControl(id,tab:AddDropdown(id,{
        Title=title,Values=values,Default=initial,Multi=multi or false,DropdownOutsideWindow=true,Callback=callback
    }))
end
local function input(tab,id,title,value,callback)
    return setControl(id,tab:AddInput(id,{Title=title,Default=toText(value),Numeric=false,Finished=true,Callback=callback}))
end
local function addSectionUI(tab,name)
    local cfg=newSection(name)
    local prefix=Prefixes[name]
    tab:AddSection(name)
    toggle(tab,prefix.."_Place","Auto Place Units",false,function(v) cfg.autoPlace=v==true;redrawMarkers() end)
    toggle(tab,prefix.."_Upgrade","Auto Upgrade Units",false,function(v) cfg.autoUpgrade=v==true end)
    toggle(tab,prefix.."_Replay","Auto Replay",false,function(v) cfg.autoReplay=v==true end)
    toggle(tab,prefix.."_Skip","Auto Wave Skip",false,function(v) cfg.autoWaveSkip=v==true end)
    toggle(tab,prefix.."_Vote","Auto Vote Start",false,function(v) cfg.autoVoteStart=v==true end)
    local slots={}
    for i=1,6 do slots[#slots+1]=tostring(i) end
    dropdown(tab,prefix.."_Slot","Unit Slot",slots,tostring(cfg.slot),function(v)
        cfg.slot=tonumber(v) or 1
    end)
    toggle(tab,prefix.."_SetUnitPosition","Set Unit Position",false,function(v)
        for _,n in ipairs(Sections) do
            if n~=name then Config.sections[n].capture=false end
        end
        cfg.capture=v==true
        redrawMarkers()
    end)
    MarkerSelectors[name]=dropdown(tab,prefix.."_Markers","Saved Positions",{},nil,function(v)
        local index=tonumber(toText(v):match("^(%d+)"))
        if index then cfg.selectedMarker=index end
    end)
    tab:AddButton({Title="Remove Position",Callback=function()
        local map=sectionMap(name)
        local index=tonumber(cfg.selectedMarker)
        if index and map[index] then
            table.remove(map,index)
            cfg.selectedMarker=math.min(index,#map)
            redrawMarkers()
            refreshMarkerLists()
        end
    end})
    tab:AddButton({Title="Update Position",Callback=function()
        local map=sectionMap(name)
        local index=tonumber(cfg.selectedMarker)
        if not (index and map[index]) then notify("Select a saved position") return end
        local point=groundPosition(UIS:GetMouseLocation())
        if not point then notify("Point to valid ground, then press Update Position") return end
        map[index].position=vecToTable(point)
        redrawMarkers()
    end})
end
addSectionUI(Tabs.Story,"Story Mode")
addSectionUI(Tabs.Modes,"Raids")
addSectionUI(Tabs.Modes,"Infinite Castle")
addSectionUI(Tabs.Modes,"Portals")
local statResultPending=false
local statLastId=nil
local statNext=0
local statResultAt=0
local statFailure=0
local StatList={"All","Attack","Range","Cooldown"}
local StatChoices={}
local function updateStatUnits()
    local values={}
    table.clear(StatChoices)
    for _,unit in ipairs(S.Units or {}) do
        if unit.id~=nil then
            local label=toText(unit.name or "Unit").." ("..toText(unit.id)..")"
            values[#values+1]=label
            StatChoices[label]=toText(unit.id)
        end
    end
    table.sort(values)
    if UI.StatUnit and UI.StatUnit.SetValues then pcall(function()UI.StatUnit:SetValues(values)end)end
end
Tabs.Lobby:AddSection("Stat Rerolls")
dropdown(Tabs.Lobby,"StatUnit","Unit",{},nil,function(v)
    Config.stat.unitId=StatChoices[toText(v)] or ""
end)
dropdown(Tabs.Lobby,"StatType","Stat",StatList,"All",function(v)Config.stat.stat=toText(v)end)
toggle(Tabs.Lobby,"StatEnabled","Auto Stat Rerolls",false,function(v)
    Config.stat.enabled=v==true
end)
if StatRerollResult and StatRerollResult.OnClientEvent then
    listen(StatRerollResult.OnClientEvent,function(result)
        statResultPending=false
        statResultAt=os.clock()
        if type(result)=="table" and result.success==false then
            statFailure=statFailure+1
            statNext=os.clock()+math.min(30,2^math.min(statFailure,5))
        else statFailure=0 end
    end)
end
task.spawn(function()
    while S.Running do
        if Config.stat.enabled and not isInMatch() and StatRerollRequest and os.clock()>=statNext then
            local unit=Config.stat.unitId
            if unit~="" then
                if statResultPending and os.clock()-statResultAt>8 then
                    statResultPending=false
                    statNext=os.clock()+6
                end
                if not statResultPending then
                    statResultPending=true
                    statResultAt=os.clock()
                    local stat=Config.stat.stat~="All" and Config.stat.stat or nil
                    if not send(StatRerollRequest,{id=unit,stat=stat}) then statResultPending=false end
                    statNext=os.clock()+1.2
                end
            end
        end
        task.wait(0.35)
    end
end)
local function isValidWebhook(url)
    return type(url)=="string" and #url<400
        and url:match("^https://(discord%.com)/api/webhooks/%d+/[%w_-]+$")
end
Tabs.Webhook:AddSection("Webhook")
toggle(Tabs.Webhook,"WebhookEnabled","Enable Webhook",false,function(v)
    if v and not isValidWebhook(Config.webhook.url) then
        notify("Enter a valid Discord Webhook URL first")
        Config.webhook.enabled=false
        if UI.WebhookEnabled and UI.WebhookEnabled.SetValue then
            task.defer(function()pcall(function()UI.WebhookEnabled:SetValue(false)end)end)
        end
        return
    end
    Config.webhook.enabled=v==true
end)
input(Tabs.Webhook,"WebhookURL","Webhook URL","",function(v)
    Config.webhook.url=toText(v)
end)
local webhookQueue={}
local sendingWebhook=false
local function enqueueWebhook(message)
    if not Config.webhook.enabled or not isValidWebhook(Config.webhook.url) then return end
    webhookQueue[#webhookQueue+1]={content="[CAT EMPIRE | RE Adventures] "..toText(message):sub(1,1600)}
end
task.spawn(function()
    while S.Running do
        if not sendingWebhook and #webhookQueue>0 then
            local body=table.remove(webhookQueue,1)
            if Config.webhook.enabled and isValidWebhook(Config.webhook.url) then
                sendingWebhook=true
                task.spawn(function()
                    local requestFn=Env.request or Env.http_request or (Env.syn and Env.syn.request)
                    if type(requestFn)=="function" then
                        pcall(requestFn,{Url=Config.webhook.url,Method="POST",
                            Headers={["Content-Type"]="application/json"},
                            Body=HttpService:JSONEncode(body)})
                    end
                    sendingWebhook=false
                end)
            end
        end
        task.wait(0.8)
    end
end)
local function recordAction(action)
    if not Runtime.macroRecording or Runtime.macroPlaying then return end
    local name=safeName(Config.macroName)
    local macro=Config.macros[name]
    if not macro then return end
    action.time=math.max(0,os.clock()-Runtime.macroStart)
    action._idx=#macro.actions+1
    macro.actions[#macro.actions+1]=action
end
local function currentPlaceIndex(placeId)
    local folder=findPlaced()
    if not folder then return nil end
    for _,unit in ipairs(folder:GetChildren()) do
        if toText(modelPlaceId(unit))==toText(placeId) then
            local pos=modelPosition(unit)
            if not pos then return nil end
            local name=safeName(Config.macroName)
            local macro=Config.macros[name]
            if not macro then return nil end
            local best,dist=nil,math.huge
            for i,a in ipairs(macro.actions) do
                if a.kind=="place" and a.position then
                    local v=tableToVec(a.position)
                    if v then
                        local d=(pos-v).Magnitude
                        if d<dist then best=i;dist=d end
                    end
                end
            end
            if dist<=3 then return best end
        end
    end
end
local function hookRecord(remote,...)
    local arguments=table.pack(...)
    if remote==PlaceRequest and type(arguments[1])=="table" then
        local a=arguments[1]
        if a.position then
            recordAction({kind="place",slot=tonumber(a.slot) or 1,position=vecToTable(a.position),
                yaw=tonumber(a.yaw) or 0})
        end
    elseif remote==MatchAction and arguments[1]=="upgrade" then
        local index=currentPlaceIndex(arguments[2])
        if index then recordAction({kind="upgrade",ref=index}) end
    end
end
if type(Env.hookmetamethod or hookmetamethod)=="function"
    and type(Env.getnamecallmethod or getnamecallmethod)=="function"
    and type(Env.newcclosure or newcclosure)=="function"
    and type(Env.checkcaller or checkcaller)=="function" then
    if not Env.__CE105_MACRO_HOOK then
        local realHook=Env.hookmetamethod or hookmetamethod
        local realMethod=Env.getnamecallmethod or getnamecallmethod
        local realCclosure=Env.newcclosure or newcclosure
        local realCheck=Env.checkcaller or checkcaller
        local original
        local ok=pcall(function()
            original=realHook(game,"__namecall",realCclosure(function(self,...)
                local capture=Env.__CE105_MACRO_RECORD
                if capture and not realCheck() and realMethod()=="FireServer" then
                    pcall(capture,self,...)
                end
                return original(self,...)
            end))
        end)
        if ok then Env.__CE105_MACRO_HOOK=true end
    end
    if Env.__CE105_MACRO_HOOK then
        Env.__CE105_MACRO_RECORD=hookRecord
        Runtime.hookReady=true
    end
end
local function createMacro()
    local name=safeName(Config.macroName)
    Config.macros[name]={map=mapKey(),mode=modeForMatch(),actions={}}
    notify("Macro profile created: "..name)
end
local function startRecord()
    local name=safeName(Config.macroName)
    if not Config.macros[name] then createMacro() end
    local macro=Config.macros[name]
    macro.map=mapKey()
    macro.mode=modeForMatch()
    macro.actions={}
    Runtime.macroStart=os.clock()
    Runtime.macroRecording=true
end
local function stopRecord() Runtime.macroRecording=false end
local function replayMacro()
    local macro=Config.macros[safeName(Config.macroName)]
    if not macro or type(macro.actions)~="table" or #macro.actions==0 then return end
    if not isInMatch() or macro.mode~=modeForMatch() or macro.map~=mapKey() then return end
    Runtime.macroPlaying=true
    local started=os.clock()
    local placements={}
    for _,action in ipairs(macro.actions) do
        if not (S.Running and Runtime.macroPlaying and isInMatch()) then break end
        while S.Running and Runtime.macroPlaying and os.clock()-started < (tonumber(action.time) or 0) do
            task.wait(0.05)
        end
        if action.kind=="place" and PlaceRequest then
            local pos=tableToVec(action.position)
            if pos then
                send(PlaceRequest,{slot=action.slot,position=pos,yaw=action.yaw or 0})
                local placed
                for i=1,18 do
                    task.wait(0.2)
                    placed=findPlacedNear(pos,2.5)
                    if placed then break end
                end
                placements[action._idx]=placed and modelPlaceId(placed)
            end
        elseif action.kind=="upgrade" and MatchAction then
            local id=placements[action.ref]
            if id then send(MatchAction,"upgrade",id) end
        end
    end
    Runtime.macroPlaying=false
end
Tabs.Macro:AddSection("Macro")
input(Tabs.Macro,"MacroName","Create Profile","Default",function(v)
    Config.macroName=safeName(v)
end)
Tabs.Macro:AddButton({Title="Create Profile",Callback=createMacro})
toggle(Tabs.Macro,"MacroRecording","Record Macro",false,function(v)
    if v then
        if Runtime.macroPlaying then notify("Stop Auto Macro before recording") return end
        startRecord()
        if not Runtime.hookReady then notify("Remote recording unavailable in this executor") end
    else stopRecord() end
end)
Tabs.Macro:AddButton({Title="Save Macro",Callback=function()
    stopRecord()
    local ok,err=writeJSON(profilePath(Config.profileName),{version=2,config=copyPlain(Config,0),
        existing={SelectedUnits=copyPlain(S.SelectedUnits,0),TraitTargets=copyPlain(S.TraitTargets,0),
        CapsuleTargets=copyPlain(S.CapsuleTargets,0),AutoTraits=S.AutoTraits,AutoStars=S.AutoStars}})
    if ok then notify("Macro saved") else notify(toText(err)) end
end})
local macroToggle=toggle(Tabs.Macro,"AutoMacro","Auto Macro",false,function(v)
    Runtime.autoMacro=v==true
    if not v then Runtime.macroPlaying=false end
end)
local function updateMiscAvatar()
    local userIcon,gameIcon="","rbxthumb://type=GameIcon&id="..game.PlaceId.."&w=150&h=150"
    pcall(function()
        userIcon=Players:GetUserThumbnailAsync(LocalPlayer.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size150x150)
    end)
    local display=toText(LocalPlayer.DisplayName)
    local profileText=display.."  @"..LocalPlayer.Name.."\nUser ID: "..LocalPlayer.UserId
    local level=attr(LocalPlayer,"Level")
    if level then profileText=profileText.."\nLevel: "..toText(level) end
    if UI.AvatarGame and UI.AvatarGame.SetDesc then
        pcall(function()UI.AvatarGame:SetDesc("RE Adventures • "..game.PlaceId)end)
    end
    if UI.PlayerProfile and UI.PlayerProfile.SetDesc then
        pcall(function()UI.PlayerProfile:SetDesc(profileText)end)
    end
    if UI.PlayerAvatar and UI.PlayerAvatar.SetDesc then
        pcall(function()UI.PlayerAvatar:SetDesc("@"..LocalPlayer.Name)end)
    end
end
Tabs.Misc:AddSection("Profile")
UI.AvatarGame=Tabs.Misc:AddParagraph({Title="Avatar Game",Content="RE Adventures",Image="rbxthumb://type=GameIcon&id="..game.PlaceId.."&w=150&h=150"})
UI.PlayerProfile=Tabs.Misc:AddParagraph({Title="Player Profile",Content=LocalPlayer.Name})
local avatarUri="rbxthumb://type=AvatarHeadShot&id="..LocalPlayer.UserId.."&w=150&h=150"
UI.PlayerAvatar=Tabs.Misc:AddParagraph({Title="Player Avatar",Content=LocalPlayer.DisplayName,Image=avatarUri})
Tabs.Misc:AddSection("Automation")
toggle(Tabs.Misc,"AutoLuck","Auto Luck Potion",false,function(v)Config.luck=v==true end)
toggle(Tabs.Misc,"AutoCodes","Auto Redeem Codes",false,function(v)Config.codes=v==true end)
local CodeCandidates={}
local function refreshCodes()
    table.clear(CodeCandidates)
    for _,name in ipairs({"CodeData","CodesData","RedeemCodes","Codes"}) do
        local instance=RS:FindFirstChild(name)
        if instance and instance:IsA("ModuleScript") then
            local ok,data=pcall(require,instance)
            if ok and type(data)=="table" then
                for k,v in pairs(data) do
                    if type(k)=="string" and (v==true or type(v)=="table") then
                        CodeCandidates[k]=true
                    elseif type(v)=="string" then CodeCandidates[v]=true end
                end
            end
        end
    end
end
local luckLast=0
local codeLast=0
task.spawn(function()
    while S.Running do
        if Config.luck and not isInMatch() and LuckPotion and os.clock()-luckLast>30 then
            luckLast=os.clock()
            local items=S.Items or {}
            for key,count in pairs(items) do
                local name=toText(key):lower()
                if name:find("luck",1,true) and tonumber(count) and tonumber(count)>0 then
                    pcall(function()LuckPotion:InvokeServer("use",key)end)
                    break
                end
            end
        end
        if Config.codes and not isInMatch() and RedeemCode and os.clock()-codeLast>15 then
            codeLast=os.clock()
            refreshCodes()
            for code in pairs(CodeCandidates) do
                if not Config.codeDone[code] then
                    local ok,result=pcall(function()return RedeemCode:InvokeServer(code)end)
                    Config.codeDone[code]=true
                    if not ok then Env.__CE_RE105_LAST_ERROR="Code redemption failed" end
                    break
                end
            end
        end
        task.wait(2)
    end
end)
local function exportExisting()
    return {SelectedUnits=copyPlain(S.SelectedUnits,0),TraitTargets=copyPlain(S.TraitTargets,0),
        CapsuleTargets=copyPlain(S.CapsuleTargets,0),AutoTraits=S.AutoTraits,AutoStars=S.AutoStars,
        AntiAFK=S.AntiAFK,AutoRejoin=S.AutoRejoin,AutoExecute=S.AutoExecute,
        StarMode=S.StarMode,StarAmount=S.StarAmount,SkipStarAnimations=S.SkipStarAnimations,
        SelectAllCapsules=S.SelectAllCapsules,SelectAllUnits=S.SelectAllUnits}
end
local function saveProfile()
    local name=safeName(Config.profileName)
    Config.profileName=name
    local ok,err=writeJSON(profilePath(name),{version=2,config=copyPlain(Config,0),existing=exportExisting()})
    if not ok then notify("Save failed: "..toText(err)); return false end
    writeJSON(IndexFile,{last=name,autoLoad=Config.autoLoad})
    notify("Profile saved: "..name)
    return true
end
local function loadProfile(name)
    local data=readJSON(profilePath(name))
    if not data or type(data.config)~="table" then return false end
    local prev=data.config
    Config.sections=prev.sections or Config.sections
    for _,n in ipairs(Sections) do newSection(n) end
    Config.webhook=prev.webhook or Config.webhook
    Config.macros=prev.macros or Config.macros
    Config.macroName=prev.macroName or Config.macroName
    Config.profileName=safeName(name)
    Config.autoLoad=prev.autoLoad==true
    Config.autoCloseUI=prev.autoCloseUI==true
    Config.stat=prev.stat or Config.stat
    Config.luck=prev.luck==true
    Config.codes=prev.codes==true
    Config.codeDone=prev.codeDone or {}
    local old=data.existing or {}
    for _,key in ipairs({"SelectedUnits","TraitTargets","CapsuleTargets"}) do
        if type(old[key])=="table" then S[key]=copyPlain(old[key],0) end
    end
    for _,key in ipairs({"AutoTraits","AutoStars","AntiAFK","AutoRejoin","AutoExecute","SkipStarAnimations","SelectAllCapsules","SelectAllUnits"}) do
        if type(old[key])=="boolean" then S[key]=old[key] end
    end
    for _,key in ipairs({"StarMode","StarAmount"}) do if old[key]~=nil then S[key]=old[key] end end
    local on={
        Story="Story Mode",Raids="Raids",Castle="Infinite Castle",Portals="Portals"
    }
    for prefix,section in pairs(on) do
        local cfg=Config.sections[section]
        for id,field in pairs({Place="autoPlace",Upgrade="autoUpgrade",Replay="autoReplay",Skip="autoWaveSkip",Vote="autoVoteStart"}) do
            local c=UI[prefix.."_"..id]
            if c and c.SetValue then pcall(function()c:SetValue(cfg[field])end)end
        end
        local slot=UI[prefix.."_Slot"]
        if slot and slot.SetValue then pcall(function()slot:SetValue(tostring(cfg.slot))end)end
    end
    for id,value in pairs({
        WebhookEnabled=Config.webhook.enabled,WebhookURL=Config.webhook.url,
        StatEnabled=Config.stat.enabled,StatType=Config.stat.stat,
        AutoLuck=Config.luck,AutoCodes=Config.codes,AutoMacro=false,
        SettingsAutoClose=Config.autoCloseUI,SettingsAutoLoad=Config.autoLoad,
        MacroName=Config.macroName,SettingsProfile=Config.profileName,
    }) do
        local c=UI[id]
        if c and c.SetValue then pcall(function()c:SetValue(value)end)end
    end
    if ctx.UnitDropdown and ctx.UnitDropdown.SetValue then
        local labels={}
        for id in pairs(S.SelectedUnits or {}) do
            local name=ctx.UnitIdToLabel[id]
            if name then labels[name]=true end
        end
        pcall(function()ctx.UnitDropdown:SetValue(labels)end)
    end
    if ctx.CapsuleDropdown and ctx.CapsuleDropdown.SetValue then
        pcall(function()ctx.CapsuleDropdown:SetValue(S.CapsuleTargets)end)
    end
    if ctx.AutoTraitsToggle and ctx.AutoTraitsToggle.SetValue then
        pcall(function()ctx.AutoTraitsToggle:SetValue(S.AutoTraits)end)
    end
    if ctx.AutoStarsToggle and ctx.AutoStarsToggle.SetValue then
        pcall(function()ctx.AutoStarsToggle:SetValue(S.AutoStars)end)
    end
    refreshMarkerLists()
    redrawMarkers()
    notify("Profile loaded: "..name)
    return true
end
Tabs.Settings:AddSection("Profiles")
input(Tabs.Settings,"SettingsProfile","Create Profile","Default",function(v)
    Config.profileName=safeName(v)
end)
Tabs.Settings:AddButton({Title="Create Profile",Callback=function()
    Config.profileName=safeName(Config.profileName)
    saveProfile()
end})
Tabs.Settings:AddButton({Title="Save Profile",Callback=saveProfile})
toggle(Tabs.Settings,"SettingsAutoLoad","Auto Load Profile",false,function(v)
    Config.autoLoad=v==true
    writeJSON(IndexFile,{last=Config.profileName,autoLoad=Config.autoLoad})
end)
toggle(Tabs.Settings,"SettingsAutoClose","Auto Close UI",false,function(v)
    Config.autoCloseUI=v==true
end)
local wasMatched=isInMatch()
local lastMode,lastMap=modeForMatch(),mapKey()
local lastStatRefresh=0
listen(LocalPlayer:GetAttributeChangedSignal("MatchJoined"),function()
    local joined=isInMatch()
    if joined and not wasMatched then
        Runtime.round=Runtime.round+1
        Runtime.placed={}
        Runtime.last={}
        Runtime.macroPlaying=false
        if Config.autoCloseUI and Window.Minimize then pcall(function()Window:Minimize()end)end
    elseif not joined and wasMatched then
        Runtime.macroPlaying=false
        for _,name in ipairs(Sections) do Config.sections[name].capture=false end
    end
    wasMatched=joined
    redrawMarkers()
end)
if MatchState and MatchState.OnClientEvent then
    listen(MatchState.OnClientEvent,function(data)
        if type(data)~="table" then return end
        local old=Runtime.match.state
        Runtime.match=data
        local st=data.state
        if st~=old and (st==MatchConfig.STATE.VICTORY or st==MatchConfig.STATE.DEFEAT) then
            enqueueWebhook((st==MatchConfig.STATE.VICTORY and "Victory" or "Defeat").." | Mode: "..
                modeForMatch().." | Map: "..mapKey())
        end
    end)
end
task.spawn(function()
    while S.Running do
        local mode,key=modeForMatch(),mapKey()
        if mode~=lastMode or key~=lastMap then
            lastMode,lastMap=mode,key
            redrawMarkers()
            refreshMarkerLists()
        end
        for _,name in ipairs(Sections) do
            local ok,err=pcall(processSection,name)
            if not ok then
                local id="section-error:"..name
                if cooldown(id,8) then
                    setLast(id)
                    Env.__CE_RE105_LAST_ERROR=toText(err)
                end
            end
        end
        local macroRunKey="macroRound:"..tostring(Runtime.round)
        if Runtime.autoMacro and not Runtime.macroPlaying and isInMatch() and not Runtime.last[macroRunKey] then
            local macro=Config.macros[safeName(Config.macroName)]
            if macro and macro.map==mapKey() and macro.mode==modeForMatch() and #macro.actions>0 then
                setLast(macroRunKey)
                task.spawn(replayMacro)
            end
        end
        if os.clock()-lastStatRefresh>7 then
            lastStatRefresh=os.clock()
            updateStatUnits()
            updateMiscAvatar()
        end
        task.wait(0.55)
    end
end)
local index=readJSON(IndexFile)
if index and index.autoLoad and index.last then
    task.defer(function()
        task.wait(0.4)
        if S.Running then loadProfile(index.last) end
    end)
end
refreshMarkerLists()
updateStatUnits()
updateMiscAvatar()
local oldCleanup=Env.__SARTEX_UD105_CLEANUP
Env.__SARTEX_UD105_CLEANUP=function()
    Runtime.macroPlaying=false
    Runtime.macroRecording=false
    Env.__CE105_MACRO_RECORD=nil
    for _,connection in ipairs(Links) do pcall(function()connection:Disconnect()end)end
    if markerFolder.Parent then markerFolder:Destroy() end
    if type(oldCleanup)=="function" then oldCleanup() end
end
return true
end