-- CAT EMPIRE | Death Travel Trace | Passive diagnostic, no gameplay actions
-- Place ID 114326934417838
local PLACE = 114326934417838
if game.PlaceId ~= PLACE and game.GameId ~= PLACE then
    warn("[CAT EMPIRE TRACE] Not Break and Steal an Egg; collector not started")
    return
end
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local PS = game:GetService("ProximityPromptService")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer
if not LP then warn("[CAT EMPIRE TRACE] LocalPlayer unavailable"); return end
local env = (getgenv and getgenv()) or _G
local previous = env.__CAT_EMPIRE_DEATH_TRACE
if type(previous) == "table" and type(previous.Stop) == "function" then
    pcall(previous.Stop)
end
local active, start = true, os.clock()
local filename = "CAT_EMPIRE_DeathTravel_" .. tostring(os.time()) .. ".jsonl"
local connections, queue, archive = {}, {}, {}
local fileOk = type(writefile) == "function"
local incremental = fileOk and type(appendfile) == "function"
local lastFlush, elapsedMax = os.clock(), 300
local playerRoot, humanoid, character, plot, backpack
local safeQuery
do
    local shared = RS:FindFirstChild("Shared")
    local module = shared and shared:FindFirstChild("SafeZoneQuery")
    if module and module:IsA("ModuleScript") then
        local ok, value = pcall(require, module)
        if ok and type(value) == "table" then safeQuery = value end
    end
end
local function vec(value)
    if typeof(value) ~= "Vector3" then return nil end
    return {math.floor(value.X*10+.5)/10, math.floor(value.Y*10+.5)/10, math.floor(value.Z*10+.5)/10}
end
local function pos(item)
    if not item or not item.Parent then return nil end
    local ok, value = pcall(function()
        if item:IsA("BasePart") then return item.Position end
        if item:IsA("Model") then return item:GetPivot().Position end
        if item:IsA("Attachment") then return item.WorldPosition end
        return nil
    end)
    if ok then return value end
end
local function idOf(item)
    if not item then return nil end
    local out = {name = item.Name, class = item.ClassName}
    for _,key in ipairs({"AnimalUID", "AnimalGuid", "AnimalId", "PetId", "UniqueId", "UID", "AnimalName", "ZoneId",
        "ReservedUserId", "Despawning", "Weight", "Mutation", "Health"}) do
        local value = item:GetAttribute(key)
        if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
            out[key] = value
        end
    end
    out.position = vec(pos(item))
    return out
end
local function safeFlags()
    local root = playerRoot
    if not root or not root.Parent or not safeQuery then return nil end
    local values = {}
    if type(safeQuery.IsPositionSafe) == "function" then
        local ok, yes = pcall(safeQuery.IsPositionSafe, root.Position)
        if ok then values.isSafe = yes == true end
    end
    if type(safeQuery.IsBankable) == "function" then
        local ok, yes = pcall(safeQuery.IsBankable, LP.UserId, root.Position)
        if ok then values.bankable = yes == true end
    end
    return values
end
local function nearbyAnimals(origin, radius)
    local out = {}
    if not origin then return out end
    for _,item in ipairs(CS:GetTagged("AnimalPickup")) do
        local point = pos(item)
        if point then
            local distance = (point-origin).Magnitude
            if distance <= (radius or 65) then
                local record = idOf(item)
                record.distance = math.floor(distance*10+.5)/10
                out[#out+1] = record
            end
        end
    end
    table.sort(out, function(a,b) return a.distance < b.distance end)
    local nearest = {}
    for i=1,math.min(#out,5) do nearest[i]=out[i] end
    return nearest
end
local function nearestGuard(origin)
    if not origin then return nil end
    local best, distance
    for _,obj in ipairs(CS:GetTagged("ZoneGuard")) do
        local point = pos(obj)
        if point then
            local dist=(point-origin).Magnitude
            if not distance or dist < distance then best, distance = obj, dist end
        end
    end
    if not best then return nil end
    return {name=best.Name, distance=math.floor(distance*10+.5)/10,
        phase=best:GetAttribute("ChaseState"), catchPulse=best:GetAttribute("CatchPulse"), position=vec(pos(best))}
end
local function serverNow()
    local ok, value = pcall(function() return workspace:GetServerTimeNow() end)
    return ok and value or nil
end
local function snapshot()
    local root = playerRoot
    local origin = root and root.Parent and root.Position or nil
    local flags = safeFlags()
    return {
        position=vec(origin),
        health=humanoid and humanoid.Parent and humanoid.Health or nil,
        walkSpeed=humanoid and humanoid.Parent and humanoid.WalkSpeed or nil,
        carrying=LP:GetAttribute("Carrying"),
        carryingJail=LP:GetAttribute("CarryingJail"),
        beingChased=LP:GetAttribute("BeingChased"),
        bankable=flags and flags.bankable or nil,
        safe=flags and flags.isSafe or nil,
        animalsPlaced=plot and plot.Parent and plot:GetAttribute("AnimalsPlaced") or nil,
        nearestGuard=nearestGuard(origin),
        nearbyPets=nearbyAnimals(origin,60),
    }
end
local function record(kind, details, withState)
    if not active then return end
    local event = {ms=math.floor((os.clock()-start)*1000), serverTime=serverNow(), event=kind, data=details}
    if withState then event.state = snapshot() end
    local ok, serialized = pcall(HttpService.JSONEncode, HttpService, event)
    if not ok then return end
    queue[#queue+1]=serialized
    archive[#archive+1]=serialized
    if #archive > 8000 then table.remove(archive,1) end
    if kind~="SAMPLE" then
        print("[CAT EMPIRE TRACE] "..tostring(event.ms).."ms "..kind)
    end
end
local function flush()
    if not fileOk or #queue == 0 then return end
    local text = table.concat(queue,"\n").."\n"
    local ok
    if incremental then
        ok=pcall(appendfile,filename,text)
    else
        ok=pcall(writefile,filename,table.concat(archive,"\n").."\n")
    end
    if ok then
        table.clear(queue)
    else
        fileOk=false
        warn("[CAT EMPIRE TRACE] File output failed; use __CAT_EMPIRE_DEATH_TRACE.GetLog()")
    end
    lastFlush=os.clock()
end
local function listen(signal, callback)
    local ok, conn = pcall(function() return signal:Connect(callback) end)
    if ok and conn then connections[#connections+1]=conn end
end
local charConnections = {}
local function trackChar(signal, callback)
    local ok, conn=pcall(function() return signal:Connect(callback) end)
    if ok and conn then charConnections[#charConnections+1]=conn end
end
local function trackTool(tool, action, container)
    if not tool:IsA("Tool") then return end
    record(action, {tool=idOf(tool),container=container},true)
end
local function onCharacter(model)
    for _,connection in ipairs(charConnections) do pcall(function() connection:Disconnect() end) end
    table.clear(charConnections)
    character=model
    playerRoot=model:FindFirstChild("HumanoidRootPart") or model:WaitForChild("HumanoidRootPart",10)
    humanoid=model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid",10)
    record("CHARACTER_ADDED",{},true)
    if humanoid then
        local prevHealth=humanoid.Health
        trackChar(humanoid.HealthChanged,function(health)
            record("HEALTH_CHANGED",{from=prevHealth,to=health},true)
            prevHealth=health
        end)
        trackChar(humanoid.Died,function() record("HUMANOID_DIED",{},true) end)
        trackChar(humanoid.StateChanged,function(from,to)
            if to==Enum.HumanoidStateType.Dead or to==Enum.HumanoidStateType.FallingDown
                or to==Enum.HumanoidStateType.Ragdoll then
                record("HUMANOID_STATE",{before=tostring(from),after=tostring(to)},true)
            end
        end)
    end
    trackChar(model.ChildAdded,function(child) if child:IsA("Tool") then trackTool(child,"CHARACTER_TOOL_ADDED","Character") end end)
    trackChar(model.ChildRemoved,function(child) if child:IsA("Tool") then trackTool(child,"CHARACTER_TOOL_REMOVED","Character") end end)
end
listen(LP.CharacterRemoving,function(c) record("CHARACTER_REMOVING",{name=c.Name},true) end)
listen(LP.CharacterAdded,onCharacter)
if LP.Character then task.defer(onCharacter,LP.Character) end
local function onBackpack(item)
    if not item then return end
    backpack=item
    listen(item.ChildAdded,function(obj) trackTool(obj,"BACKPACK_TOOL_ADDED","Backpack") end)
    listen(item.ChildRemoved,function(obj) trackTool(obj,"BACKPACK_TOOL_REMOVED","Backpack") end)
end
if LP:FindFirstChildOfClass("Backpack") then onBackpack(LP:FindFirstChildOfClass("Backpack")) end
listen(LP.ChildAdded,function(obj) if obj:IsA("Backpack") then onBackpack(obj) end end)
for _,attribute in ipairs({"Carrying","CarryingJail","BeingChased"}) do
    listen(LP:GetAttributeChangedSignal(attribute),function()
        record("PLAYER_ATTR_"..attribute,{value=LP:GetAttribute(attribute)},true)
    end)
end
local petWatch = {}
local function trackPet(item)
    if petWatch[item] or not item:IsA("Model") then return end
    petWatch[item]=true
    record("PET_APPEARED",idOf(item),true)
    for _,attribute in ipairs({"ReservedUserId","Despawning","AnimalName","ZoneId"}) do
        listen(item:GetAttributeChangedSignal(attribute),function()
            record("PET_ATTRIBUTE",{pet=idOf(item),attribute=attribute,value=item:GetAttribute(attribute)},true)
        end)
    end
    listen(item.AncestryChanged,function(_,parent)
        if parent==nil then record("PET_REMOVED",idOf(item),true) end
    end)
end
for _,obj in ipairs(CS:GetTagged("AnimalPickup")) do trackPet(obj) end
listen(CS:GetInstanceAddedSignal("AnimalPickup"),trackPet)
listen(CS:GetInstanceRemovedSignal("AnimalPickup"),function(item)
    record("PET_UNTAGGED",idOf(item),true)
end)
listen(CS:GetInstanceRemovedSignal("BreakableEgg"),function(item)
    record("EGG_UNTAGGED",idOf(item),true)
end)
local guardWatch={}
local function trackGuard(model)
    if not model:IsA("Model") or guardWatch[model] then return end
    guardWatch[model]=true
    for _,attr in ipairs({"CatchPulse","ChaseState"}) do
        listen(model:GetAttributeChangedSignal(attr),function()
            record("GUARD_"..attr,{guard=idOf(model),value=model:GetAttribute(attr)},true)
        end)
    end
end
for _,model in ipairs(CS:GetTagged("ZoneGuard")) do trackGuard(model) end
listen(CS:GetInstanceAddedSignal("ZoneGuard"),trackGuard)
listen(PS.PromptTriggered,function(prompt,player)
    if player and player ~= LP then return end
    record("PROMPT_TRIGGERED",{prompt=prompt.Name,action=prompt.ActionText,position=vec(pos(prompt.Parent))},true)
end)
local function onPlot(model)
    if plot==model then return end
    plot=model
    record("PLOT_IDENTIFIED",{name=model.Name,animalsPlaced=model:GetAttribute("AnimalsPlaced")},true)
    listen(model:GetAttributeChangedSignal("AnimalsPlaced"),function()
        record("ANIMALS_PLACED_CHANGED",{amount=model:GetAttribute("AnimalsPlaced")},true)
    end)
end
local function findPlot()
    local container=workspace:FindFirstChild("Plots")
    if not container then return end
    for _,model in ipairs(container:GetChildren()) do
        if model:GetAttribute("OwnerUserId")==LP.UserId then onPlot(model);return end
    end
end
findPlot()
local lastSafe,lastBank,lastCarrying,lastPosition
local lastSample=0
local api = {}
function api.GetLog()
    return table.concat(archive,"\n").."\n"
end
function api.GetFileName()
    return fileOk and filename or nil
end
function api.Mark(label)
    record("USER_MARK",{label=tostring(label):sub(1,100)},true)
    flush()
end
function api.Stop()
    if not active then return end
    record("CAPTURE_STOPPED",{elapsed=os.clock()-start},true)
    flush()
    active=false
    for _,connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
    for _,connection in ipairs(charConnections) do pcall(function() connection:Disconnect() end) end
    env.__CAT_EMPIRE_DEATH_TRACE=nil
    print("[CAT EMPIRE TRACE] stopped; file: "..filename)
end
env.__CAT_EMPIRE_DEATH_TRACE=api
if fileOk then
    local ok=pcall(writefile,filename,"")
    if not ok then fileOk=false end
end
record("CAPTURE_STARTED",{placeId=game.PlaceId,gameId=game.GameId,file=fileOk and filename or "console_only"},true)
task.spawn(function()
    while active do
        if os.clock()-start > elapsedMax then api.Stop();break end
        local ok,err=pcall(function()
            if not plot or not plot.Parent then findPlot() end
            local current=LP:GetAttribute("Carrying")
            local state=safeFlags()
            local safe=state and state.isSafe or nil
            local bank=state and state.bankable or nil
            if safe~=lastSafe and safe~=nil then
                record(safe and "SAFE_ENTER" or "SAFE_EXIT",{},true)
            end
            if bank~=lastBank and bank~=nil then
                record(bank and "BANKABLE_ENTER" or "BANKABLE_EXIT",{},true)
            end
            if current~=lastCarrying then
                record(current==nil and "CARRY_LOST" or "CARRY_ACQUIRED",
                    {from=lastCarrying,to=current},true)
            end
            lastCarrying,lastSafe,lastBank=current,safe,bank
            local due=(os.clock()-lastSample)>=((current~=nil or LP:GetAttribute("BeingChased")~=nil) and .20 or .7)
            if due then
                local stateFrame=snapshot()
                local currentPos=stateFrame.position
                if current~=nil or LP:GetAttribute("BeingChased")~=nil or
                    (stateFrame.nearestGuard and stateFrame.nearestGuard.distance<65) or
                    (stateFrame.nearbyPets and #stateFrame.nearbyPets>0) then
                    record("SAMPLE",nil,true)
                end
                lastPosition=currentPos
                lastSample=os.clock()
            end
            if os.clock()-lastFlush>2.0 then flush() end
        end)
        if not ok then warn("[CAT EMPIRE TRACE] Sampling: "..tostring(err)) end
        task.wait(.12)
    end
end)
print("[CAT EMPIRE TRACE] Passive capture started. Use __CAT_EMPIRE_DEATH_TRACE.Stop() after the run.")
print("[CAT EMPIRE TRACE] Output file: "..filename.." (executor workspace, when writefile is available)")
