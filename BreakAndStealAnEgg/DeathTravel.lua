-- CAT EMPIRE / Break and Steal an Egg: experimental Death Travel.
-- Controlled base <-> original Pet pulses. No player-hitbox target or fake inventory success.
return function(ctx)
    local S, LP, CS = ctx.S, ctx.Player, ctx.CS
    local state = {active=false, phase="idle", generation=0, pulses=0, attempts=0}
    local helpers, cycle

    local function carrying()
        return LP:GetAttribute("Carrying") ~= nil or LP:GetAttribute("CarryingJail") == true
    end
    local function rawRoot()
        local char=LP.Character
        local root=char and char:FindFirstChild("HumanoidRootPart")
        return root and root:IsA("BasePart") and root or nil
    end
    local function isActive()
        return state.active and S.Running and S.AutoFarmEggs and S.DeathTravel
    end
    local function canAct(generation)
        return isActive() and state.generation==generation
            and ctx.CanMove("Farm") and not ctx.InHell()
    end
    local function status(message)
        if S.Step~=message then S.Step=message end
    end
    local function received()
        if not helpers or not cycle then return false end
        local count=helpers.placedCount()
        if cycle.beforePlaced~=nil and count>cycle.beforePlaced then
            return true,"Pen AnimalsPlaced increased"
        end
        local tool=helpers.newTool()
        if tool then
            local root=rawRoot()
            if root and helpers.bankable(root.Position) then
                return true,"AnimalTool replicated after returning to base"
            end
        end
        return false
    end
    local function basePoint()
        -- The delivery destination MUST belong to the player's own Plot, never to the player.
        local plot=ctx.Plot()
        local hitbox
        local shared=ctx.Shared
        local module=shared and shared:FindFirstChild("SafeZoneQuery")
        if module and module:IsA("ModuleScript") then
            local ok,query=pcall(require,module)
            if ok and type(query)=="table" and type(query.GetOwnedPlotHitbox)=="function" then
                local found,part=pcall(query.GetOwnedPlotHitbox,LP.UserId)
                if found and typeof(part)=="Instance" and part:IsA("BasePart") then hitbox=part end
            end
        end
        if not hitbox and plot then
            if plot:IsA("BasePart") then hitbox=plot
            else hitbox=plot:FindFirstChild("Hitbox") end
        end
        if not hitbox or not hitbox:IsA("BasePart") or not hitbox:IsDescendantOf(workspace) then
            return nil
        end
        return hitbox.Position+Vector3.new(0,hitbox.Size.Y/2+3,0)
    end
    local function guardAt(origin)
        local guard,nearest
        for _,model in ipairs(CS:GetTagged("ZoneGuard")) do
            if model:IsA("Model") and model:IsDescendantOf(workspace) then
                local pos=ctx.Position(model)
                local distance=pos and (pos-origin).Magnitude
                if distance and (not nearest or distance<nearest) then
                    guard,nearest=model,distance
                end
            end
        end
        return nearest and nearest<320 and guard or nil
    end
    local function samePet()
        if not helpers then return nil end
        local model=helpers.recoveryPickup()
        if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace)
            or model:GetAttribute("Despawning")==true then return nil end
        local owner=model:GetAttribute("ReservedUserId")
        if owner~=nil and owner~=LP.UserId then return nil end
        return model
    end
    local function promptFor(pet)
        if not pet then return nil end
        local prompt=helpers and helpers.findPrompt and helpers.findPrompt(pet)
        if not prompt then prompt=pet:FindFirstChildWhichIsA("ProximityPrompt",true) end
        return prompt and prompt.Parent and prompt.Enabled and prompt or nil
    end
    local function teleportTo(target,generation)
        if not canAct(generation) or typeof(target)~="Vector3" then return false end
        local root=rawRoot()
        if not root or not root.Parent then return false end
        -- Preserve an upright, stable orientation; never use player Root as the destination.
        local forward=root.CFrame.LookVector
        local horizontal=Vector3.new(forward.X,0,forward.Z)
        if horizontal.Magnitude<0.01 then horizontal=Vector3.new(0,0,-1) end
        local ok=pcall(function()
            root.CFrame=CFrame.lookAt(target,target+horizontal.Unit)
        end)
        if ok then state.pulses=state.pulses+1 end
        return ok
    end
    local function tryPrompt(pet,generation)
        if not canAct(generation) or carrying() then return false end
        local prompt=promptFor(pet)
        if not prompt then return false end
        local root=rawRoot()
        local location=ctx.Position(prompt)
        if not root or not location
            or (root.Position-location).Magnitude>prompt.MaxActivationDistance+1 then
            return false
        end
        local now=os.clock()
        if now-(state.lastPrompt or 0)<math.max(0.32,prompt.HoldDuration+0.15) then return false end
        state.lastPrompt=now
        local ok,err=pcall(function()
            if type(fireproximityprompt)=="function" then
                fireproximityprompt(prompt)
            else
                prompt:InputHoldBegin()
                task.wait(math.max(0.08,prompt.HoldDuration+0.05))
                if prompt.Parent then prompt:InputHoldEnd() end
            end
        end)
        if not ok then ctx.Error("Death Travel prompt",err) end
        return ok
    end
    local function stop()
        state.generation=state.generation+1
        state.active=false
        state.phase="idle"
        state.busy=false
        state.guard=nil
        state.character=nil
        state.pet=nil
        state.base=nil
        helpers,cycle=nil,nil
    end
    local function start(targetCycle,callbacks)
        if not S.AutoFarmEggs or not S.DeathTravel or not carrying()
            or not targetCycle or not targetCycle.targetPet then return false end
        local root,hum=ctx.Root()
        if not root or not hum then return false end
        local base=basePoint()
        if not base then
            status("Death Travel: own Plot Hitbox not found; using normal delivery")
            return false
        end
        local guard=guardAt(targetCycle.origin or root.Position)
        if not guard then
            status("Death Travel: zone guard missing; normal delivery")
            return false
        end
        stop()
        helpers,cycle=callbacks,targetCycle
        state.active=true
        state.phase="lure"
        state.started=os.clock()
        state.character=LP.Character
        state.guard=guard
        state.base=base
        state.pulses=0
        state.attempts=0
        state.lastBurst=0
        state.lastPrompt=0
        state.lastCarriedPosition=root.Position
        state.guardPulse=guard:GetAttribute("CatchPulse")
        state.visitedBase=false
        state.respawned=false
        state.missingSince=nil
        state.dropDetectedAt=nil
        status("Death Travel: provoking zone guard (test)")
        return true
    end
    local function startPulse()
        if not isActive() or state.busy or not ctx.CanMove("Farm") then return end
        local pet=samePet()
        local base=basePoint()
        if not pet or not base then return end
        local now=os.clock()
        local gap=state.attempts<2 and 0.85 or (state.attempts<5 and 2.1 or 3.2)
        if now-(state.lastBurst or 0)<gap then return end
        local generation=state.generation
        state.busy=true
        state.lastBurst=now
        state.attempts=state.attempts+1
        state.phase="pulse"
        status("Death Travel: base <-> same Pet, cycle "..tostring(state.attempts))
        task.spawn(function()
            local ok,err=pcall(function()
                -- One bounded burst. Further bursts require a new cooldown and valid Pet.
                for pass=1,2 do
                    if not canAct(generation) or carrying() then break end
                    pet=samePet()
                    base=basePoint()
                    if not pet or not base then break end
                    local petPos=ctx.Position(pet)
                    if not petPos then break end
                    if not teleportTo(base,generation) then break end
                    state.visitedBase=true
                    task.wait(0.055)
                    if not canAct(generation) then break end
                    if not teleportTo(petPos+Vector3.new(0,2.7,0),generation) then break end
                    task.wait(0.075)
                    if not canAct(generation) then break end
                    tryPrompt(pet,generation)
                    task.wait(0.075)
                    if carrying() then break end
                end
                if canAct(generation) then
                    base=basePoint()
                    if base then
                        teleportTo(base,generation)
                        state.visitedBase=true
                    end
                end
            end)
            if not ok then ctx.Error("Death Travel pulse",err) end
            if state.generation==generation then
                state.busy=false
                state.phase="verify"
                state.verifyAt=os.clock()
            end
        end)
    end
    local function markDrop()
        if not isActive() then return end
        if state.phase~="lure" and state.phase~="waitHit" and state.phase~="carried" then return end
        if received() then return end
        state.dropDetectedAt=os.clock()
        state.phase="recover"
        state.missingSince=nil
        status("Death Travel: Pet dropped; preparing base/pet pulse")
    end
    local function step()
        if not isActive() or not cycle or not helpers then
            stop()
            return "fallback"
        end
        if not ctx.CanMove("Farm") or ctx.InHell() then return "busy" end
        local done,reason=received()
        if done then
            status("Death Travel: delivery confirmed - "..reason)
            stop()
            return "delivered"
        end
        local root,hum=ctx.Root()
        local now=os.clock()
        if state.phase=="lure" or state.phase=="waitHit" then
            if not carrying() then markDrop();return "busy" end
            if root then state.lastCarriedPosition=root.Position end
            local guard=state.guard
            local position=guard and guard:IsDescendantOf(workspace) and ctx.Position(guard)
            if not position then stop();return "fallback" end
            if guard:GetAttribute("CatchPulse")~=state.guardPulse then
                state.guardPulse=guard:GetAttribute("CatchPulse")
                state.phase="waitHit"
            end
            if root and hum then hum:MoveTo(position) end
            if now-state.started>23 then stop();return "fallback" end
            status("Death Travel: getting hit by zone guard")
            return "busy"
        end
        if state.phase=="recover" then
            if carrying() then
                state.phase="carried"
                state.carriedAt=now
                status("Death Travel: Pet recovered; returning to own Plot")
                return "busy"
            end
            if state.busy then return "busy" end
            local pet=samePet()
            if pet then
                state.missingSince=nil
                if rawRoot() then startPulse() end
            else
                state.missingSince=state.missingSince or now
                if now-state.missingSince>6 then
                    stop()
                    return "gone"
                end
                status("Death Travel: waiting for original dropped Pet")
            end
            return "busy"
        end
        if state.phase=="pulse" then
            if state.busy then return "busy" end
            state.phase="verify"
            state.verifyAt=now
        end
        if state.phase=="verify" then
            if carrying() then
                state.phase="carried"
                state.carriedAt=now
                return "busy"
            end
            done,reason=received()
            if done then stop();return "delivered" end
            if now-(state.verifyAt or now)>.5 then
                state.phase="recover"
            else
                status("Death Travel: waiting for server carry/bank result")
            end
            return "busy"
        end
        if state.phase=="carried" then
            if not carrying() then
                state.phase="recover"
                state.missingSince=nil
                return "busy"
            end
            -- If the reset already placed us near the base, native delivery can finish.
            if root and helpers.bankable(root.Position) then
                status("Death Travel: carrying inside own safe area; awaiting credit")
            end
            if now-(state.carriedAt or now)>1.3 then
                stop()
                return "fallback"
            end
            return "busy"
        end
        if state.phase=="postRespawn" then
            if not root then
                status("Death Travel: waiting for character respawn")
                return "busy"
            end
            if carrying() then
                stop()
                return "fallback"
            end
            local pet=samePet()
            if pet then
                state.phase="recover"
                state.missingSince=nil
                status("Death Travel: recovering same Pet after respawn")
                return "busy"
            end
            state.missingSince=state.missingSince or now
            if now-state.missingSince>6 then stop();return "gone" end
            return "busy"
        end
        stop()
        return "fallback"
    end
    ctx.Links[#ctx.Links+1]=LP:GetAttributeChangedSignal("Carrying"):Connect(function()
        if not isActive() then return end
        if not carrying() then markDrop()
        elseif state.phase=="recover" or state.phase=="verify" then
            state.phase="carried"
            state.carriedAt=os.clock()
        end
    end)
    ctx.Links[#ctx.Links+1]=CS:GetInstanceAddedSignal("AnimalPickup"):Connect(function()
        if not isActive() then return end
        if state.phase=="recover" then state.missingSince=nil end
    end)
    ctx.Links[#ctx.Links+1]=LP.CharacterAdded:Connect(function()
        if not isActive() then return end
        state.generation=state.generation+1
        state.respawned=true
        state.phase="postRespawn"
        state.busy=false
        state.missingSince=nil
        status("Death Travel: respawn; checking original Pet or inventory")
    end)
    local engine={Start=start,Step=step,Stop=stop,State=state}
    ctx.DeathTravel=engine
    return stop
end
