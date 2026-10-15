-- CAT EMPIRE | Break and Steal an Egg | Experimental Death Travel
-- Isolated mode: does not affect the standard farm unless explicitly enabled.
return function(ctx)
    local S, LP, CS = ctx.S, ctx.Player, ctx.CS
    local state = {phase="idle", active=false, character=nil, guard=nil}
    local helpers, cycle
    local function carrying()
        return LP:GetAttribute("Carrying") ~= nil or LP:GetAttribute("CarryingJail") == true
    end
    local function rawRoot()
        local character = LP.Character
        return character and character:FindFirstChild("HumanoidRootPart")
    end
    local function nativeHumanoid()
        local character = LP.Character
        return character and character:FindFirstChildOfClass("Humanoid")
    end
    local function position(object)
        return ctx.Position(object)
    end
    local function isActive()
        return state.active and S.Running and S.AutoFarmEggs and S.DeathTravel
    end
    local function announce(message)
        if S.Step ~= message then S.Step=message end
    end
    local function received()
        if not cycle or not helpers then return false end
        local placed=helpers.placedCount()
        if cycle.beforePlaced ~= nil and placed>cycle.beforePlaced then
            return true, "Pen count increased"
        end
        local newTool=helpers.newTool()
        if newTool then
            local root=rawRoot()
            if root and root.Parent and helpers.bankable(root.Position) then
                return true, "New AnimalTool registered in safe area"
            end
        end
        return false
    end
    local function guardAt(origin)
        local nearest,dist
        for _,guard in ipairs(CS:GetTagged("ZoneGuard")) do
            if guard:IsA("Model") and guard:IsDescendantOf(workspace) then
                local at=position(guard)
                local d=at and (origin-at).Magnitude
                if d and (not dist or d<dist) then nearest,dist=guard,d end
            end
        end
        if dist and dist<320 then return nearest end
        return nil
    end
    local function samePet()
        if not helpers then return nil end
        local model=helpers.recoveryPickup()
        if not model or not model.Parent or not model:IsDescendantOf(workspace)
            or model:GetAttribute("Despawning")==true then return nil end
        local reserved=model:GetAttribute("ReservedUserId")
        if reserved~=nil and reserved~=LP.UserId then return nil end
        return model
    end
    local function choosePrompt(pet)
        if not pet then return nil end
        if type(helpers.findPrompt)=="function" then
            return helpers.findPrompt(pet)
        end
        return pet:FindFirstChildWhichIsA("ProximityPrompt",true)
    end
    local function placeAtPet(pet)
        local root=rawRoot()
        local petPosition=position(pet)
        if not root or not root.Parent or not petPosition then return false end
        if (root.Position-petPosition).Magnitude>7 then
            -- One optional reposition at the dropped Pet, never a teleport to the Plot.
            -- Do not alter speed, health, or the server's carry state.
            root.CFrame=CFrame.new(petPosition+Vector3.new(0,3,0),
                petPosition+Vector3.new(0,3,-1))
        end
        return true
    end
    local function immediatePickup()
        if not isActive() or (state.phase~="drop" and state.phase~="recover") then return end
        if not ctx.CanMove("Farm") or ctx.InHell() then return end
        if carrying() then return end
        local pet=samePet()
        if not pet then return end
        local now=os.clock()
        if state.lastAttemptPet~=pet then
            state.lastAttemptPet=pet
            state.lastAttempt=0
        end
        if now-(state.lastAttempt or 0)<0.35 then return end
        state.lastAttempt=now
        state.pet=pet
        state.lastDropPosition=position(pet) or state.lastDropPosition
        if not placeAtPet(pet) then return end
        local prompt=choosePrompt(pet)
        if not prompt or not prompt.Parent or not prompt.Enabled then return end
        local root=rawRoot()
        local promptPos=position(prompt)
        if not root or not promptPos
            or (promptPos-root.Position).Magnitude>prompt.MaxActivationDistance+1 then return end
        local ok,err=pcall(function()
            if type(fireproximityprompt)=="function" then
                fireproximityprompt(prompt)
            else
                prompt:InputHoldBegin()
                task.delay(math.max(0.1,prompt.HoldDuration+0.05),function()
                    if prompt.Parent then pcall(function() prompt:InputHoldEnd() end) end
                end)
            end
        end)
        if not ok then ctx.Error("DeathTravel pickup",err) end
    end
    local function markDrop()
        if not isActive() or state.phase~="lure" and state.phase~="waitDeath" then return end
        if received() then return end
        state.phase="drop"
        state.dropAt=os.clock()
        state.lastDropPosition=position(rawRoot()) or state.lastCarriedPosition
        state.lastAttempt=0
        state.lastAttemptPet=nil
        announce("Death Travel: guard dropped Pet; recovering")
        -- The server may create AnimalPickup within this same death transition.
        task.defer(immediatePickup)
    end
    local function stop()
        state.active=false
        state.phase="idle"
        state.guard=nil
        state.pet=nil
        state.character=nil
        state.lastAttemptPet=nil
        state.lastAttempt=0
        helpers=nil
        cycle=nil
    end
    local function start(targetCycle,callbacks)
        if not S.DeathTravel or not S.AutoFarmEggs or not carrying()
            or not targetCycle or not targetCycle.targetPet then return false end
        local root,hum=ctx.Root()
        if not root or not hum then return false end
        local guard=guardAt(targetCycle.origin or root.Position)
        if not guard then
            announce("Death Travel: guard unavailable; using normal Safe Zone")
            return false
        end
        stop()
        helpers=callbacks
        cycle=targetCycle
        state.active=true
        state.guard=guard
        state.character=LP.Character
        state.phase="lure"
        state.started=os.clock()
        state.lastCarriedPosition=root.Position
        state.guardPulse=guard:GetAttribute("CatchPulse")
        state.lastAttempt=0
        state.lostAfter=nil
        state.respawned=false
        announce("Death Travel: attracting zone guard")
        return true
    end
    local function step()
        if not isActive() or not cycle or not helpers then
            stop()
            return "fallback"
        end
        if not ctx.CanMove("Farm") or ctx.InHell() then
            return "busy"
        end
        local accepted,why=received()
        if accepted then
            announce("Death Travel: delivery confirmed ("..why..")")
            stop()
            return "delivered"
        end
        local now=os.clock()
        local root,hum=ctx.Root()
        if state.phase=="lure" or state.phase=="waitDeath" then
            if not carrying() then
                markDrop()
                return "busy"
            end
            if root then
                state.lastCarriedPosition=root.Position
            end
            local guard=state.guard
            local guardPos=guard and guard:IsDescendantOf(workspace) and position(guard)
            if not guardPos then
                stop()
                return "fallback"
            end
            local pulse=guard:GetAttribute("CatchPulse")
            if pulse~=state.guardPulse then
                state.guardPulse=pulse
                state.phase="waitDeath"
                announce("Death Travel: guard attack detected; waiting for Pet drop")
            end
            if root and hum then
                hum:MoveTo(guardPos)
                if (root.Position-guardPos).Magnitude<14 then
                    announce("Death Travel: within guard attack range")
                end
            end
            if now-state.started>22 then
                -- Avoid locking the farm if this zone guard never attacks.
                stop()
                return "fallback"
            end
            return "busy"
        end
        if state.phase=="drop" or state.phase=="recover" then
            if carrying() then
                state.phase="waitRespawn"
                state.recoveredAt=now
                announce("Death Travel: same Pet recovered; waiting for respawn/bank")
                return "busy"
            end
            immediatePickup()
            if LP.Character~=state.character then
                state.respawned=true
                state.phase="postRespawn"
                announce("Death Travel: respawn detected; validating Pet")
                return "busy"
            end
            local pet=samePet()
            if not pet then
                state.lostAfter=state.lostAfter or now
                if now-state.lostAfter>7 then
                    stop()
                    return "gone"
                end
                announce("Death Travel: waiting for dropped Pet replication")
            else
                state.lostAfter=nil
                announce("Death Travel: retrying the same Pet ("..pet.Name..")")
            end
            return "busy"
        end
        if state.phase=="waitRespawn" then
            if LP.Character~=state.character then
                state.respawned=true
                state.phase="postRespawn"
                announce("Death Travel: character respawned; verifying delivery")
                return "busy"
            end
            if not carrying() then
                state.phase="drop"
                state.dropAt=now
                task.defer(immediatePickup)
                return "busy"
            end
            if now-(state.recoveredAt or now)>4 then
                -- If the guard knockback does not kill, resume native-safe-zone travel.
                stop()
                return "fallback"
            end
            return "busy"
        end
        if state.phase=="postRespawn" then
            accepted,why=received()
            if accepted then
                stop()
                return "delivered"
            end
            if carrying() then
                -- Pet survived respawn; the existing Farm module handles safe-zone entry.
                stop()
                return "fallback"
            end
            if not root then
                announce("Death Travel: waiting for respawn character")
                return "busy"
            end
            state.phase="recover"
            state.lastAttempt=0
            state.lastAttemptPet=nil
            state.lostAfter=nil
            announce("Death Travel: Pet not banked; trying same drop after respawn")
            return "busy"
        end
        stop()
        return "fallback"
    end
    local carrySignal=LP:GetAttributeChangedSignal("Carrying"):Connect(function()
        if not isActive() then return end
        if not carrying() then markDrop() end
    end)
    ctx.Links[#ctx.Links+1]=carrySignal
    local animalAdded=CS:GetInstanceAddedSignal("AnimalPickup"):Connect(function()
        if not isActive() then return end
        if state.phase=="drop" or state.phase=="recover" then task.defer(immediatePickup) end
    end)
    ctx.Links[#ctx.Links+1]=animalAdded
    local onCharacter=LP.CharacterAdded:Connect(function()
        if not isActive() then return end
        state.respawned=true
        if state.phase~="idle" then
            state.phase="postRespawn"
            announce("Death Travel: new character; inspecting delivery")
        end
    end)
    ctx.Links[#ctx.Links+1]=onCharacter
    local engine={Start=start,Step=step,Stop=stop,State=state}
    ctx.DeathTravel=engine
    return stop
end
